const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

/// Vérifie l'égalité structurelle de deux nœuds (comparaison récursive).
pub fn exprStructuralEq(store: *const Store, a: Id, b: Id) bool {
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != nb.tag) return false;

    return switch (na.tag) {
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
        else => false,
    };
}

/// Pattern matching structurel. Les symboles d'une seule lettre minuscule sont des variables.
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

    // Variable : symbole d'une seule lettre minuscule
    if (pn.tag == .sym) {
        const name = store.interner.resolve(pn.payload);
        if (name.len == 1 and name[0] >= 'a' and name[0] <= 'z') {
            if (bindings.get(pn.payload)) |existing| {
                return exprStructuralEq(store, existing, target);
            }
            bindings.put(allocator, pn.payload, target) catch return false;
            return true;
        }
    }

    // Sinon, matching structurel strict
    if (pn.tag != tn.tag) return false;
    return switch (pn.tag) {
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
        else => false,
    };
}

/// Substitue les variables d'un pattern par leurs valeurs.
/// Compare par NOM de symbole (pas par payload) car pattern et corps peuvent
/// avoir des symboles internés séparément.
pub fn substitutePattern(
    store: *Store,
    pattern: Id,
    bindings: *std.AutoHashMapUnmanaged(u32, Id),
    allocator: std.mem.Allocator,
) !Id {
    if (pattern >= store.len()) return pattern;
    const pn = store.get(pattern);

    // Symbole : chercher par NOM dans les bindings
    if (pn.tag == .sym) {
        const name = store.interner.resolve(pn.payload);
        // D'abord essayer par payload direct
        if (bindings.get(pn.payload)) |replacement| return replacement;
        // Sinon, chercher par nom résolu
        var it = bindings.iterator();
        while (it.next()) |entry| {
            const bound_name = store.interner.resolve(entry.key_ptr.*);
            if (std.mem.eql(u8, bound_name, name)) {
                return entry.value_ptr.*;
            }
        }
        return pattern;
    }

    return switch (pn.tag) {
        .apply => {
            const func_id = pn.payload;
            const old_args = pn.span_a.slice(store.pool.items);

            // Substituer récursivement la fonction et tous les arguments
            const new_func = try substitutePattern(store, func_id, bindings, allocator);

            var new_args: [16]Id = undefined;
            var any_changed = false;
            for (old_args, 0..) |arg, i| {
                if (i >= 16) break;
                new_args[i] = try substitutePattern(store, arg, bindings, allocator);
                if (new_args[i] != arg) any_changed = true;
            }

            if (new_func != func_id or any_changed) {
                // Reconstruire l'apply avec les nouveaux arguments
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
        else => pattern,
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

    const x = try store.sym("x"); // variable
    const target = try store.int(42);
    var bindings = std.AutoHashMapUnmanaged(u32, Id){};
    defer bindings.deinit(allocator);
    try std.testing.expect(exprPatternMatch(&store, x, target, &bindings, allocator));
    try std.testing.expect(bindings.get(x) != null);
}
