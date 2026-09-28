// src/core/kernel_bridge.zig — Pont Expr (Store) ↔ Term kernel Peano
// Option B : vit côté core car kernel_mod n'a pas expr en dep.
// Iso-morphisme pools : Id (Store) ↔ u32 (TermPool).
const std = @import("std");
const expr = @import("expr");
const kernel = @import("kernel");

const Store = expr.Store;
const Id = expr.Id;
const peano = kernel.peano;
const TermPool = peano.TermPool;

/// Traduit une expression Core (6 primitives) en Term kernel Peano.
/// Périmètre : lit(int) [→ Peano], sym [→ ref par hash de nom],
/// apply binop arithmétique [+ → add (δ-règles), * → mul],
/// apply générique [curryfié].
/// bind/lambda/relation : error.UnsupportedExprTag.
pub fn exprToTerm(store: *const Store, pool: *TermPool, id: Id) anyerror!u32 {
    const node = store.get(id);
    switch (node.tag) {
        .lit => {
            const lit = store.lits.items[node.aux];
            return switch (lit) {
                .int => |v| intToPeano(pool, v),
                else => error.UnsupportedLit,
            };
        },
        .sym => {
            const name = store.interner.resolve(node.payload);
            return pool.mkRef(std.hash.Wyhash.hash(0, name));
        },
        .apply => {
            const args = node.span_a.slice(store.pool.items);
            // Convention span_a : [0] = func_id. Sécurité : si [0] ≠
            // payload, traiter tout span_a comme args.
            const args_slice: []const Id = if (args.len > 0 and args[0] == node.payload)
                args[1..]
            else
                args;

            // Binop arithmétique → refs kernel (add : δ-règles actives)
            if (args_slice.len == 2) {
                const func_node = store.get(node.payload);
                if (func_node.tag == .sym) {
                    const op = store.interner.resolve(func_node.payload);
                    if (opToRef(pool, op)) |ref| {
                        const l = try exprToTerm(store, pool, args_slice[0]);
                        const r = try exprToTerm(store, pool, args_slice[1]);
                        return pool.mkApp(try pool.mkApp(ref, l), r);
                    }
                }
            }
            // Curryfication générique
            var func_term = try exprToTerm(store, pool, node.payload);
            for (args_slice) |arg| {
                const arg_term = try exprToTerm(store, pool, arg);
                func_term = try pool.mkApp(func_term, arg_term);
            }
            return func_term;
        },
        else => return error.UnsupportedExprTag,
    }
}

fn opToRef(pool: *TermPool, op: []const u8) ?u32 {
    const name: []const u8 = if (std.mem.eql(u8, op, "+"))
        "add"
    else if (std.mem.eql(u8, op, "*"))
        "mul"
    else
        return null; // pas une binop kernel
    return pool.mkRef(std.hash.Wyhash.hash(0, name)) catch null; // OOM → null (rare, acceptable)
}

fn intToPeano(pool: *TermPool, v: i64) anyerror!u32 {
    if (v < 0) return error.UnsupportedLit;
    var term = try pool.mkZero();
    var i: i64 = 0;
    while (i < v) : (i += 1) {
        term = try pool.mkSucc(term);
    }
    return term;
}

/// Déclare tous les symboles libres d'une expression comme axiomes
/// `name : Nat` dans le pool kernel. Requis par infer (l.436) : une
/// ref non déclarée → InvalidAxiom → verify échoue. Idempotent.
/// Version pragmatique : tout symbole libre est un Nat (cohérent
/// avec l'arithmétique du langage) — à raffiner quand le pont
/// connaîtra les types Heaven.
pub fn declareFreeSymbols(store: *const Store, pool: *TermPool, id: Id) !void {
    const node = store.get(id);
    switch (node.tag) {
        .sym => {
            const name = store.interner.resolve(node.payload);
            const hash = std.hash.Wyhash.hash(0, name);
            if (pool.lookupAxiom(hash) == null) {
                const nat_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "Nat"));
                _ = try pool.declareAxiom(name, nat_ref);
            }
        },
        .apply => {
            const args = node.span_a.slice(store.pool.items);
            const args_slice: []const Id = if (args.len > 0 and args[0] == node.payload)
                args[1..]
            else
                args;
            for (args_slice) |arg| try declareFreeSymbols(store, pool, arg);
        },
        .lit => {},
        else => {},
    }
}

// ═══ Test : le pont en isolation ═══
const testing = std.testing;

test "exprToTerm — x + 0 → add(x, zero), verify refl" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const plus = try store.sym("+");
    const applied = try store.apply(plus, &.{ x, zero }); // apply écrit [func, x, zero] lui-même

    var pool = TermPool.init(allocator);
    defer pool.deinit();
    try peano.initNatAxioms(&pool);

    const term = try exprToTerm(&store, &pool, applied);
    const x_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "x"));
    const add_ref = try pool.mkRef(std.hash.Wyhash.hash(0, "add"));
    const expected = try pool.mkApp(try pool.mkApp(add_ref, x_ref), try pool.mkZero());
    try testing.expectEqual(expected, term);

    // Preuve complète : Eq(add(x,zero), x) par refl — passe par
    // la δ-règle add(n, zero) → n dans la conversion
    const eq_type = try pool.mkEq(term, x_ref);
    const refl = try pool.mkRefl(x_ref);
    try testing.expect(try peano.verify(&pool, refl, eq_type));
}
