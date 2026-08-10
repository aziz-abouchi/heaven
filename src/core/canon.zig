const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const Lit = expr.Lit;
const Allocator = std.mem.Allocator;
const platform = @import("platform");

const Sym = expr.Sym;
const Span = expr.Span;

pub fn compareExpr(store: *const Store, a: Id, b: Id) std.math.Order {
    const na = store.get(a);
    const nb = store.get(b);
    const rank_a = tagRank(na.tag);
    const rank_b = tagRank(nb.tag);
    if (rank_a != rank_b) return std.math.order(rank_a, rank_b);

    return switch (na.tag) {
        .lit => compareLit(store, na.aux, nb.aux),
        .sym => std.math.order(na.payload, nb.payload),
        .apply => {
            const op_a = store.get(na.payload);
            const op_b = store.get(nb.payload);
            if (op_a.tag == .sym and op_b.tag == .sym) {
                if (op_a.payload != op_b.payload)
                    return std.math.order(op_a.payload, op_b.payload);
            }
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
        .bind => {
            const cmp_sym = std.math.order(na.payload, nb.payload);
            if (cmp_sym != .eq) return cmp_sym;
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
        .lambda => {
            const cmp_sym = std.math.order(na.payload, nb.payload);
            if (cmp_sym != .eq) return cmp_sym;
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
        .relation => {
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
        else => std.math.order(a, b),
    };
}

fn tagRank(tag: Tag) u8 {
    return switch (tag) {
        .lit => 0,
        .sym => 1,
        .apply => 2,
        .bind => 3,
        .lambda => 4,
        .relation => 5,
        .hole => 6,
        else => 7,
    };
}

fn compareLit(store: *const Store, aux_a: u32, aux_b: u32) std.math.Order {
    const la = store.lits.items[aux_a];
    const lb = store.lits.items[aux_b];
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
        .unit => .eq,
        .runtime => |va| switch (lb) {
            .runtime => |vb| {
                const ord = std.math.order(@intFromEnum(va), @intFromEnum(vb));
                if (ord != .eq) return ord;
                const payload_a: u64 = switch (va) {
                    inline else => |x| x,
                };
                const payload_b: u64 = switch (vb) {
                    inline else => |x| x,
                };
                return std.math.order(payload_a, payload_b);
            },
            else => .eq,
        },
    };
}

fn litRank(l: Lit) u8 {
    return switch (l) {
        .int => 0,
        .float => 1,
        .boolean => 2,
        .str => 3,
        .unit => 4,
        .runtime => 5,
    };
}

pub fn canonicalizeAC(store: *Store, id: Id) !Id {
    const node = store.get(id);
    if (node.tag != .apply) return id;
    const op = store.get(node.payload);
    if (op.tag != .sym) return id;

    const name = store.interner.resolve(op.payload);
    const is_commutative = std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "*") or
        std.mem.eql(u8, name, "&") or std.mem.eql(u8, name, "|") or
        std.mem.eql(u8, name, "=");
    if (!is_commutative) return id;

    const pool = store.pool.items;
    const args = node.span_a.slice(pool);
    if (args.len <= 2) return id;

    var flat: std.ArrayList(Id) = .empty;
    defer flat.deinit(store.allocator);
    try flattenAC(store, id, name, &flat);

    const Context = struct {
        store: *Store,
        pub fn lessThan(ctx: @This(), a: Id, b: Id) bool {
            return compareExpr(ctx.store, a, b) == .lt;
        }
    };
    std.mem.sort(Id, flat.items, Context{ .store = store }, Context.lessThan);

    return rebuildAC(store, op.payload, flat.items);
}

fn flattenAC(store: *Store, id: Id, op_name: []const u8, out: *std.ArrayList(Id)) !void {
    const node = store.get(id);
    if (node.tag != .apply) {
        try out.append(store.allocator, id);
        return;
    }
    const op = store.get(node.payload);
    if (op.tag != .sym or !std.mem.eql(u8, store.interner.resolve(op.payload), op_name)) {
        try out.append(store.allocator, id);
        return;
    }
    const pool = store.pool.items;
    const args = node.span_a.slice(pool);
    for (args[1..]) |arg| {
        try flattenAC(store, arg, op_name, out);
    }
}

fn rebuildAC(store: *Store, op_sym: Sym, items: []const Id) !Id {
    if (items.len == 0) unreachable;
    if (items.len == 1) return items[0];

    const sym_node = try store.addNode(.{ .tag = .sym, .payload = op_sym, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    var cur = items[0];
    for (items[1..]) |item| {
        const span = try store.reserveSpan(3);
        store.pool.items[span.start] = sym_node;
        store.pool.items[span.start + 1] = cur;
        store.pool.items[span.start + 2] = item;
        cur = try store.addNode(.{ .tag = .apply, .payload = sym_node, .aux = 0, .span_a = span, .span_b = Span.EMPTY });
    }
    return cur;
}

pub fn canonicalize(store: *Store, allocator: Allocator, id: Id) !Id {
    _ = allocator;
    return canonicalizeAC(store, id);
}

pub fn canonEqStr(store: *const expr.Store, a: expr.Id, b: expr.Id, allocator: std.mem.Allocator) !bool {
    _ = store; _ = a; _ = b; _ = allocator;
    return false; // Stub temporaire
}