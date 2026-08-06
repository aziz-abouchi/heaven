const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const Lit = expr.Lit;
const Allocator = std.mem.Allocator;
const platform = @import("platform");

// ═══════════════════════════════════════════════════════════════
// Ordre total sur les expressions — fondation de la canonical form
// ═══════════════════════════════════════════════════════════════

pub fn compareExpr(store: *const Store, a: Id, b: Id) std.math.Order {
    const na = store.get(a);
    const nb = store.get(b);

    // Ordre par catégorie : lit < sym < apply < bind < relation
    const rank_a = tagRank(na.tag);
    const rank_b = tagRank(nb.tag);
    if (rank_a != rank_b) return std.math.order(rank_a, rank_b);

    return switch (na.tag) {
        .lit => compareLit(store, na.aux, nb.aux),
        .sym => std.math.order(na.payload, nb.payload),
        .apply => {
            // na.payload est un Id du nœud sym de l'opérateur
            const op_a = store.get(na.payload);
            const op_b = store.get(nb.payload);
            // Comparer les opérateurs par leur Sym (payload du nœud sym)
            if (op_a.tag == .sym and op_b.tag == .sym) {
                if (op_a.payload != op_b.payload)
                    return std.math.order(op_a.payload, op_b.payload);
            }
            // Puis les enfants
            const pool = store.pool.items;
            const args_a = na.span_a.slice(pool);
            const args_b = nb.span_a.slice(pool);
            const min_len = @min(args_a.len, args_b.len);
            for (0..min_len) |i| {
                const c = compareExpr(store, args_a[i], args_b[i]);
                if (c != .eq) return c;
            }
            return std.math.order(args_a.len, args_b.len);
        },
        else => std.math.order(a, b), // fallback: ordre d'insertion
    };
}

fn tagRank(tag: Tag) u8 {
    return switch (tag) {
        .lit => 0,
        .sym => 1,
        .apply => 2,
        .bind => 3,
        .relation => 4,
        .hole => 5,
        else => 6,
    };
}

fn compareLit(store: *const Store, aux_a: u32, aux_b: u32) std.math.Order {
    const la = store.lits.items[aux_a];
    const lb = store.lits.items[aux_b];
    // Ordre par type de littéral : int < float < bool < str < unit
    const ra = litRank(la);
    const rb = litRank(lb);
    if (ra != rb) return std.math.order(ra, rb);
    return switch (la) {
        .int => |va| switch (lb) {
            .int => |vb| std.math.order(va, vb),
            else => .eq,
        },
        .float => |va| switch (lb) {
            .float => |vb| std.math.order(va, vb),
            else => .eq,
        },
        .boolean => |va| switch (lb) {
            .boolean => |vb| std.math.order(@intFromBool(va), @intFromBool(vb)),
            else => .eq,
        },
        .str => |va| switch (lb) {
            .str => |vb| {
                const name_a = store.interner.resolve(va);
                const name_b = store.interner.resolve(vb);
                return std.mem.order(u8, name_a, name_b);
            },
            else => .eq,
        },
        .runtime => |va| switch (lb) {
            .runtime => |vb| std.math.order(@intFromEnum(va), @intFromEnum(vb)),
            else => .eq,
        },
        else => .eq,
    };
}

fn litRank(l: Lit) u8 {
    return switch (l) {
        .int => 0,
        .float => 1,
        .boolean => 2,
        .str => 3,
        .unit => 4,
        else => 5,
    };
}

// ═══════════════════════════════════════════════════════════════
// Canonicalisation AC
// ═══════════════════════════════════════════════════════════════

pub fn canonicalize(store: *Store, allocator: Allocator, id: Id) !Id {
    const node = store.get(id);

    return switch (node.tag) {
        .lit, .sym, .hole => id, // Formes déjà canoniques

        .apply => {
            const op_id = node.payload;
            const op_node = store.get(op_id);
            if (op_node.tag != .sym) return id;
            const op_name = store.interner.resolve(op_node.payload);

            // Capturer les args AVANT toute récursion (store.pool peut être réalloué)
            var args_buf: [32]Id = undefined;
            const args_count = blk: {
                const pool = store.pool.items;
                const args = node.span_a.slice(pool);
                const n = @min(args.len, 32);
                @memcpy(args_buf[0..n], args[0..n]);
                break :blk n;
            };
            const args = args_buf[0..args_count];

            // Maintenant récurser sans risque
            var canon_args = std.ArrayListUnmanaged(Id){};
            defer canon_args.deinit(allocator);
            for (args) |arg| {
                try canon_args.append(allocator, try canonicalize(store, allocator, arg));
            }

            if (isAC(op_name)) {
                return try canonicalizeAC(store, allocator, op_id, op_name, canon_args.items);
            }
            // Non-AC : reconstruit avec enfants canoniques
            return try store.apply(op_id, canon_args.items);
        },

        .bind => {
            const inner = try canonicalize(store, allocator, node.aux);
            return try store.bindSym(node.payload, inner);
        },

        else => id,
    };
}

fn isAC(op: []const u8) bool {
    return std.mem.eql(u8, op, "+") or
        std.mem.eql(u8, op, "*") or
        std.mem.eql(u8, op, "∧") or
        std.mem.eql(u8, op, "∨") or
        std.mem.eql(u8, op, "and") or
        std.mem.eql(u8, op, "or");
}

fn canonicalizeAC(
    store: *Store,
    allocator: Allocator,
    func_id: Id, // <-- ID du nœud symbole
    op_name: []const u8,
    args: []const Id,
) !Id {
    // 1. Aplatir les imbrications (a + (b + c)) → [a, b, c]
    var flat = std.ArrayListUnmanaged(Id){};
    defer flat.deinit(allocator);
    try flattenAC(store, op_name, args, &flat, allocator);

    // 2. Séparer constantes et non-constantes
    var consts = std.ArrayListUnmanaged(Id){};
    defer consts.deinit(allocator);
    var others = std.ArrayListUnmanaged(Id){};
    defer others.deinit(allocator);

    for (flat.items) |arg| {
        const n = store.get(arg);
        if (n.tag == .lit) {
            try consts.append(allocator, arg);
        } else {
            try others.append(allocator, arg);
        }
    }

    // 3. Fusionner les constantes
    const merged_const = try mergeConsts(store, op_name, consts.items);

    // 4. Éliminer les identités
    const identity = identityFor(op_name);
    var result = std.ArrayListUnmanaged(Id){};
    defer result.deinit(allocator);

    if (merged_const) |mc| {
        const mcn = store.get(mc);
        const is_identity = isIdentity(store, mcn, identity);
        const is_absorbing = isAbsorbing(store, mcn, op_name);
        if (is_absorbing) return mc; // x * 0 = 0
        if (!is_identity) try result.append(allocator, mc);
    }

    // 5. Trier les non-constantes
    // Tri manuel (bulles) pour éviter un bug d'alignement dans std.sort.block
    var i: usize = 0;
    while (i < others.items.len) : (i += 1) {
        var j: usize = 0;
        while (j < others.items.len - 1 - i) : (j += 1) {
            if (compareExpr(store, others.items[j], others.items[j + 1]) == .gt) {
                const tmp = others.items[j];
                others.items[j] = others.items[j + 1];
                others.items[j + 1] = tmp;
            }
        }
    }

    for (others.items) |o| try result.append(allocator, o);

    // 6. Reconstruire
    if (result.items.len == 0) {
        return try store.int(if (std.mem.eql(u8, op_name, "+")) 0 else 1);
    }
    if (result.items.len == 1) return result.items[0];
    return try store.apply(func_id, result.items); // <-- utiliser func_id
}

fn flattenAC(
    store: *const Store,
    op_name: []const u8,
    args: []const Id,
    out: *std.ArrayListUnmanaged(Id),
    allocator: Allocator,
) !void {
    for (args) |arg| {
        const n = store.get(arg);
        if (n.tag == .apply) {
            const func_node = store.get(n.payload);
            if (func_node.tag == .sym) {
                const name = store.interner.resolve(func_node.payload);
                if (std.mem.eql(u8, name, op_name)) {
                    // Capturer avant récursion
                    var sub_buf: [32]Id = undefined;
                    const sub_count = blk: {
                        const pool = store.pool.items;
                        const sub = n.span_a.slice(pool);
                        const cnt = @min(sub.len, 32);
                        @memcpy(sub_buf[0..cnt], sub[0..cnt]);
                        break :blk cnt;
                    };
                    try flattenAC(store, op_name, sub_buf[0..sub_count], out, allocator);
                    continue;
                }
            }
        }
        try out.append(allocator, arg);
    }
}

const Identity = union(enum) { int: i64, none };

fn identityFor(op: []const u8) Identity {
    if (std.mem.eql(u8, op, "+")) return .{ .int = 0 };
    if (std.mem.eql(u8, op, "*")) return .{ .int = 1 };
    return .none;
}

fn isIdentity(store: *const Store, node: expr.Expr, identity: Identity) bool {
    if (node.tag != .lit) return false;
    const l = store.lits.items[node.aux];
    return switch (identity) {
        .int => |v| switch (l) {
            .int => |lv| lv == v,
            else => false,
        },
        .none => false,
    };
}

fn isAbsorbing(store: *const Store, node: expr.Expr, op: []const u8) bool {
    if (!std.mem.eql(u8, op, "*")) return false;
    if (node.tag != .lit) return false;
    const l = store.lits.items[node.aux];
    return switch (l) {
        .int => |v| v == 0,
        else => false,
    };
}

fn mergeConsts(store: *Store, op: []const u8, consts: []const Id) !?Id {
    if (consts.len == 0) return null;
    var acc: i64 = if (std.mem.eql(u8, op, "+")) 0 else 1;
    for (consts) |c| {
        const n = store.get(c);
        if (n.tag != .lit) continue;
        const l = store.lits.items[n.aux];
        switch (l) {
            .int => |v| {
                if (std.mem.eql(u8, op, "+")) {
                    acc += v;
                } else {
                    acc *= v;
                }
            },
            else => {},
        }
    }
    return try store.int(acc);
}

fn canonEq(store: *const Store, a: Id, b: Id) bool {
    return expr.nodeEql(store, a, b);
}

pub fn canonEqStr(store: *const Store, a: Id, b: Id, allocator: Allocator) !bool {
    const sa = try expr.toStringInfix(store, a, allocator);
    defer allocator.free(sa);
    const sb = try expr.toStringInfix(store, b, allocator);
    defer allocator.free(sb);
    return std.mem.eql(u8, sa, sb);
}

pub fn exprEqual(store: *const Store, a: Id, b: Id) bool {
    return expr.nodeEql(store, a, b);
}

pub fn printExpr(store: *const Store, id: Id, depth: u32) void {
    const node = store.get(id);
    for (0..depth) |_| platform.debug.print("  ", .{});

    switch (node.tag) {
        .lit => platform.debug.print("Lit({d})\n", .{store.getLit(id).int}),
        .sym => {
            // On utilise l'interner ici
            const name = store.interner.resolve(node.payload);
            platform.debug.print("Sym({s})\n", .{name});
        },
        .apply => {
            // 1. Récupérer le nœud de l'opérateur (le symbole) via node.payload
            const op_node = store.get(node.payload);

            // 2. Résoudre le nom via le payload du nœud opérateur
            const name = store.interner.resolve(op_node.payload);

            platform.debug.print("Apply({s})\n", .{name});

            // 3. Imprimer les enfants
            const pool = store.pool.items;
            for (node.span_a.slice(pool)) |child| {
                printExpr(store, child, depth + 1);
            }
        },
        else => platform.debug.print("Other({any})\n", .{node.tag}),
    }
}

pub fn canonicalizeId(store: *Store, allocator: Allocator, id: Id) !Id {
    return canonicalize(store, allocator, id);
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "canon — x + 0 = x" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const expr_id = try store.binop("+", x, zero);

    const canon = try canonicalize(&store, allocator, expr_id);
    try std.testing.expect(canonEq(&store, x, canon));
}

test "canon — 0 + x = x" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const expr_id = try store.binop("+", zero, x);

    const canon = try canonicalize(&store, allocator, expr_id);
    try std.testing.expect(canonEq(&store, x, canon));
}

test "canon — x + y = y + x (commutativity)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const y = try store.sym("y");
    const xy = try store.binop("+", x, y);
    const yx = try store.binop("+", y, x);

    const cxy = try canonicalize(&store, allocator, xy);
    const cyx = try canonicalize(&store, allocator, yx);
    try std.testing.expect(try canonEqStr(&store, cxy, cyx, allocator));
}

test "canon — (a + b) + c = a + (b + c) (associativity)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a = try store.sym("a");
    const b = try store.sym("b");
    const c = try store.sym("c");
    const ab_c = try store.binop("+", try store.binop("+", a, b), c);
    const a_bc = try store.binop("+", a, try store.binop("+", b, c));

    const c1 = try canonicalize(&store, allocator, ab_c);
    const c2 = try canonicalize(&store, allocator, a_bc);
    try std.testing.expect(try canonEqStr(&store, c1, c2, allocator));
}

test "canon — 3 + 5 = 8 (constant folding)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const three = try store.int(3);
    const five = try store.int(5);
    const expr_id = try store.binop("+", three, five);
    const eight = try store.int(8);

    const canon = try canonicalize(&store, allocator, expr_id);
    try std.testing.expect(try canonEqStr(&store, eight, canon, allocator));
}

test "canon — x * 0 = 0 (absorbing)" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const expr_id = try store.binop("*", x, zero);

    const canon = try canonicalize(&store, allocator, expr_id);

    //platform.debug.print("\n--- DEBUG: x * 0 --- \n", .{});
    //printExpr(&store, canon, 0); // Utilise ton nouvel utilitaire ici
    //platform.debug.print("--------------------\n", .{});

    // 1. On vérifie le tag via le nœud (ce que vous faisiez déjà)
    const cn = store.get(canon);
    try std.testing.expect(cn.tag == .lit);

    // 2. On compare les ID via canonEqStr
    // Pas besoin de getLit(), on passe l'ID 'canon' directement.
    try std.testing.expect(try canonEqStr(&store, zero, canon, allocator));
}

test "canon — x + 1" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const one = try store.int(1);
    const expr_id = try store.binop("+", x, one);

    const canon = try canonicalize(&store, allocator, expr_id);
    const str = try expr.toString(&store, canon, allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("(+ 1 x)", str);
}

test "canon — x * 2" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const two = try store.int(2);
    const expr_id = try store.binop("*", x, two);

    const canon = try canonicalize(&store, allocator, expr_id);
    const str = try expr.toString(&store, canon, allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings("(* 2 x)", str);
}

test "canon — a + b ordre" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a = try store.sym("a");
    const b = try store.sym("b");
    const ba = try store.binop("+", b, a);
    const canon = try canonicalize(&store, allocator, ba);
    const str = try expr.toStringInfix(&store, canon, allocator);
    defer allocator.free(str);
    platform.debug.print("\ncanon(b+a) = {s}\n", .{str});
    // a est interné avant b → index(a) < index(b) → a avant b
    try std.testing.expectEqualStrings("(a + b)", str);
}
