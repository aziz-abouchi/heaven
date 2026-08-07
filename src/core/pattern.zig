const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

/// Vérifie l'égalité structurelle de deux nœuds (comparaison récursive).
/// Ne compare que les 6 primitives. Les extensions doivent être lowered.
pub fn exprStructuralEq(store: *const Store, a: Id, b: Id) bool {
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != nb.tag) return false;

    const prim_a = na.tag.asPrimitive();
    const prim_b = nb.tag.asPrimitive();
    if (prim_a == null or prim_b == null) return false;

    return switch (prim_a.?) {
        .sym => na.payload == nb.payload,
        .lit => {
            const la = store.lits.items[na.aux];
            const lb = store.lits.items[nb.aux];
            return la.eql(lb);
        },
        .apply => {
            if (!exprStructuralEq(store, na.payload, nb.payload)) return false;
            const ca = na.span_a.slice(store.pool.items);
            const cb = nb.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprStructuralEq(store, x, y)) return false;
            }
            return true;
        },
        .bind => exprStructuralEq(store, na.aux, nb.aux),
        .lambda => {
            if (na.payload != nb.payload) return false;
            const ca = na.span_a.slice(store.pool.items);
            const cb = nb.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprStructuralEq(store, x, y)) return false;
            }
            return true;
        },
        .relation => {
            if (na.payload != nb.payload) return false;
            const ca = na.span_a.slice(store.pool.items);
            const cb = nb.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprStructuralEq(store, x, y)) return false;
            }
            const ba = na.span_b.slice(store.pool.items);
            const bb = nb.span_b.slice(store.pool.items);
            if (ba.len != bb.len) return false;
            for (ba, bb) |x, y| {
                if (!exprStructuralEq(store, x, y)) return false;
            }
            return true;
        },
    };
}

/// Pattern matching structurel. Les symboles d'une seule lettre minuscule sont des variables.
/// Ne matche que sur les 6 primitives.
pub fn exprPatternMatch(
    store: *const Store,
    pattern: Id,
    target: Id,
    bindings: *std.AutoHashMapUnmanaged(u32, Id),
    allocator: std.mem.Allocator,
) bool {
    if (pattern >= store.len() or target >= store.len()) return false;
    const pn = store.get(pattern);
    const tn = store.get(target);

    const prim_p = pn.tag.asPrimitive();
    const prim_t = tn.tag.asPrimitive();
    if (prim_p == null or prim_t == null) return false;

    // Variable : symbole d'une seule lettre minuscule
    if (prim_p.? == .sym) {
        const name = store.interner.resolve(pn.payload);
        if (name.len == 1 and name[0] >= 'a' and name[0] <= 'z') {
            if (bindings.get(pn.payload)) |existing| {
                return exprStructuralEq(store, existing, target);
            }
            bindings.put(allocator, pn.payload, target) catch return false;
            return true;
        }
    }

    if (pn.tag != tn.tag) return false;

    return switch (prim_p.?) {
        .sym => pn.payload == tn.payload,
        .lit => store.lits.items[pn.aux].eql(store.lits.items[tn.aux]),
        .apply => {
            if (!exprPatternMatch(store, pn.payload, tn.payload, bindings, allocator)) return false;
            const ca = pn.span_a.slice(store.pool.items);
            const cb = tn.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprPatternMatch(store, x, y, bindings, allocator)) return false;
            }
            return true;
        },
        .bind => exprPatternMatch(store, pn.aux, tn.aux, bindings, allocator),
        .lambda => {
            if (pn.payload != tn.payload) return false;
            const ca = pn.span_a.slice(store.pool.items);
            const cb = tn.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprPatternMatch(store, x, y, bindings, allocator)) return false;
            }
            return true;
        },
        .relation => {
            if (pn.payload != tn.payload) return false;
            const ca = pn.span_a.slice(store.pool.items);
            const cb = tn.span_a.slice(store.pool.items);
            if (ca.len != cb.len) return false;
            for (ca, cb) |x, y| {
                if (!exprPatternMatch(store, x, y, bindings, allocator)) return false;
            }
            const ba = pn.span_b.slice(store.pool.items);
            const bb = tn.span_b.slice(store.pool.items);
            if (ba.len != bb.len) return false;
            for (ba, bb) |x, y| {
                if (!exprPatternMatch(store, x, y, bindings, allocator)) return false;
            }
            return true;
        },
    };
}

/// Substitue les variables d'un pattern par leurs valeurs.
/// Compare par NOM de symbole (pas par payload) car pattern et corps peuvent
/// avoir des symboles internés séparément.
/// Ne substitue que dans les 6 primitives.
pub fn substitutePattern(
    store: *Store,
    pattern: Id,
    bindings: *std.AutoHashMapUnmanaged(u32, Id),
    allocator: std.mem.Allocator,
) !Id {
    if (pattern >= store.len()) return pattern;
    const pn = store.get(pattern);
    const prim = pn.tag.asPrimitive();
    if (prim == null) return pattern;

    // Symbole : chercher par NOM dans les bindings
    if (prim.? == .sym) {
        const name = store.interner.resolve(pn.payload);
        if (bindings.get(pn.payload)) |replacement| return replacement;
        var it = bindings.iterator();
        while (it.next()) |entry| {
            const bound_name = store.interner.resolve(entry.key_ptr.*);
            if (std.mem.eql(u8, bound_name, name)) {
                return entry.value_ptr.*;
            }
        }
        return pattern;
    }

    return switch (prim.?) {
        .apply => {
            const func_id = pn.payload;
            const old_args = pn.span_a.slice(store.pool.items);
            const new_func = try substitutePattern(store, func_id, bindings, allocator);
            var new_args: [16]Id = undefined;
            var any_changed = false;
            for (old_args, 0..) |arg, i| {
                if (i >= 16) break;
                new_args[i] = try substitutePattern(store, arg, bindings, allocator);
                if (new_args[i] != arg) any_changed = true;
            }
            if (new_func != func_id or any_changed) {
                return store.apply(new_func, new_args[0..old_args.len]);
            }
            return pattern;
        },
        .bind => {
            const new_aux = try substitutePattern(store, pn.aux, bindings, allocator);
            if (new_aux != pn.aux) {
                return store.bindSym(pn.payload, new_aux);
            }
            return pattern;
        },
        .lambda => {
            const new_aux = try substitutePattern(store, pn.aux, bindings, allocator);
            var new_body: [16]Id = undefined;
            var any_changed = false;
            const old_body = pn.span_a.slice(store.pool.items);
            for (old_body, 0..) |arg, i| {
                if (i >= 16) break;
                new_body[i] = try substitutePattern(store, arg, bindings, allocator);
                if (new_body[i] != arg) any_changed = true;
            }
            if (new_aux != pn.aux or any_changed) {
                return store.push(.{
                    .tag = .lambda,
                    .payload = pn.payload,
                    .aux = new_aux,
                    .span_a = try store.pushSpan(new_body[0..old_body.len]),
                });
            }
            return pattern;
        },
        .relation => {
            var new_args = std.ArrayListUnmanaged(Id){};
            defer new_args.deinit(allocator);
            const old_args = pn.span_a.slice(store.pool.items);
            for (old_args) |arg| {
                try new_args.append(allocator, try substitutePattern(store, arg, bindings, allocator));
            }
            var new_body = std.ArrayListUnmanaged(Id){};
            defer new_body.deinit(allocator);
            const old_body = pn.span_b.slice(store.pool.items);
            for (old_body) |arg| {
                try new_body.append(allocator, try substitutePattern(store, arg, bindings, allocator));
            }
            return store.push(.{
                .tag = .relation,
                .payload = pn.payload,
                .span_a = try store.pushSpan(new_args.items),
                .span_b = try store.pushSpan(new_body.items),
            });
        },
        .lit => pattern,
    };
}

// ─── Tests ───

test "exprStructuralEq — identical symbols" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a1 = try store.sym("x");
    const a2 = try store.sym("x");
    try std.testing.expect(exprStructuralEq(&store, a1, a2));
}

test "exprStructuralEq — different symbols" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const a = try store.sym("x");
    const b = try store.sym("y");
    try std.testing.expect(!exprStructuralEq(&store, a, b));
}

test "exprPatternMatch — variable matches anything" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const target = try store.int(42);
    var bindings = std.AutoHashMapUnmanaged(u32, Id){};
    defer bindings.deinit(allocator);
    try std.testing.expect(exprPatternMatch(&store, x, target, &bindings, allocator));
    try std.testing.expect(bindings.get(x) != null);
}
