//! Unification de premier ordre sur `expr.Id` (Core IR).
//!
//! Ne dépend que du `Store` et d'un `Allocator`. Utilisé par :
//! - `tactics.zig` (apply / reflexivity)
//! - `heaven_expr.zig` (type-dep v2d : unifier un résultat de ctor
//!   avec un domaine indexé, ex. `Vec (succ k)` vs `Vec (succ n)`).
//!
//! Les métavariables sont des nœuds `Tag.evar`. La substitution lie
//! `payload` (u32) → `Id`.

const std = @import("std");
const expr = @import("expr");
const Id = expr.Id;
const Store = expr.Store;
const canon = @import("canon");

pub const Subst = std.AutoHashMapUnmanaged(u32, Id);

pub const Ctx = struct {
    store: *Store,
    allocator: std.mem.Allocator,
};

pub const UnifyError = error{
    Mismatch,
    OutOfMemory,
};

/// Unification. Retourne `true` si `a` et `b` peuvent être unifiés,
/// en remplissant `subst` au passage. Retourne `false` sinon (sans
/// rollback partiel — l'appelant doit jeter la subst en cas d'échec).
pub fn unify(ctx: *const Ctx, a: Id, b: Id, subst: *Subst) UnifyError!bool {
    if (a == b) return true;

    // Normalisation AC pour l'unification modulo arithmetique (v2f)
    // Cela permet d'unifier `add x y` avec `add y x`, ou `+ 2 3` avec `+ 3 2`.
    const norm_a = try canon.canonicalizeAC(ctx.store, a);
    const norm_b = try canon.canonicalizeAC(ctx.store, b);
    
    if (norm_a == norm_b) return true;

    if (ctx.store.isEvar(a)) |pa| {
        if (subst.get(pa)) |bound| return unify(ctx, bound, b, subst);
        subst.put(ctx.allocator, pa, b) catch return error.OutOfMemory;
        return true;
    }
    if (ctx.store.isEvar(b)) |pb| {
        if (subst.get(pb)) |bound| return unify(ctx, a, bound, subst);
        subst.put(ctx.allocator, pb, a) catch return error.OutOfMemory;
        return true;
    }

    if (expr.structuralEql(ctx.store, a, b)) return true;
    if (a >= ctx.store.len() or b >= ctx.store.len()) return false;

    const na = ctx.store.get(a);
    const nb = ctx.store.get(b);
    if (na.tag != .apply or nb.tag != .apply) return false;

    // span_a = [head] ++ args.
    if (!try unify(ctx, na.payload, nb.payload, subst)) return false;
    const all_a = ctx.store.spanSliceConst(na.span_a);
    const all_b = ctx.store.spanSliceConst(nb.span_a);
    if (all_a.len != all_b.len) return false;
    for (all_a, all_b) |x, y| {
        if (!try unify(ctx, x, y, subst)) return false;
    }
    return true;
}

/// Substitue les evars liées dans `e`.
pub fn instantiate(ctx: *const Ctx, e: Id, subst: *const Subst) UnifyError!Id {
    if (e >= ctx.store.len()) return e;
    if (ctx.store.isEvar(e)) |p| {
        if (subst.get(p)) |bound| return instantiate(ctx, bound, subst);
        return e;
    }
    const node = ctx.store.get(e);
    switch (node.tag) {
        .apply => {
            const new_func = try instantiate(ctx, node.payload, subst);
            const all = ctx.store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try ctx.allocator.dupe(Id, all[1..]);
            defer ctx.allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(ctx.allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try instantiate(ctx, a, subst);
                try new_args.append(ctx.allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return ctx.store.apply(new_func, new_args.items) catch return error.OutOfMemory;
        },
        else => return e,
    }
}

/// Réécrit `from` par `to` dans `e`, en récursion sur les `.apply`.
pub fn rewriteIn(ctx: *const Ctx, e: Id, from: Id, to: Id) UnifyError!Id {
    if (expr.structuralEql(ctx.store, e, from)) return to;
    if (e >= ctx.store.len()) return e;
    const node = ctx.store.get(e);
    switch (node.tag) {
        .apply => {
            const new_func = try rewriteIn(ctx, node.payload, from, to);
            const all = ctx.store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try ctx.allocator.dupe(Id, all[1..]);
            defer ctx.allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(ctx.allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try rewriteIn(ctx, a, from, to);
                try new_args.append(ctx.allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return ctx.store.apply(new_func, new_args.items) catch return error.OutOfMemory;
        },
        else => return e,
    }
}


test "unification modulo AC - commutativite" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator);
    defer store.deinit();
    
    const ctx = Ctx{ .store = &store, .allocator = allocator };
    var subst = Subst{};
    defer subst.deinit(allocator);
    
    // Créer : add x y
    const x = try store.sym("x");
    const y = try store.sym("y");
    const add_sym = try store.sym("add");
    const add_x_y = try store.apply(add_sym, &.{ x, y });
    
    // Créer : add y x
    const add_y_x = try store.apply(add_sym, &.{ y, x });
    
    // Tester l'unification
    const result = try unify(&ctx, add_x_y, add_y_x, &subst);
    try std.testing.expect(result);
}

test "unification modulo AC - avec evars" {
    const allocator = std.testing.allocator;
    var store = try Store.init(allocator);
    defer store.deinit();
    
    const ctx = Ctx{ .store = &store, .allocator = allocator };
    var subst = Subst{};
    defer subst.deinit(allocator);
    
    // Créer : add x y
    const x = try store.sym("x");
    const y = try store.sym("y");
    const add_sym = try store.sym("add");
    const add_x_y = try store.apply(add_sym, &.{ x, y });
    
    // Créer une evar
    const evar = try store.evar(0);
    
    // Unifier add x y avec evar
    const result = try unify(&ctx, add_x_y, evar, &subst);
    try std.testing.expect(result);
    
    // Vérifier que evar est liée à add x y
    const bound = subst.get(0);
    try std.testing.expect(bound != null);
}
