//! Handler IO par défaut (natif) : exécute réellement les effets
//! `Print`, `ReadFile`, `WriteFile`, `ReadLine`.
//!
//! Extrait de `heaven_expr.zig` pour préparer RFC-0001 (découpage du
//! monolithe). Le handler est une pure fonction `(store, label, arg) → ?Id` ;
//! il n'a pas d'état et ne dépend d'aucun contexte `Heaven`.

const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const engine_expr = @import("engine_expr");

const Store = expr.Store;

/// Handler IO par défaut (natif) : exécute réellement les effets.
/// Retourne `null` si le label n'est pas reconnu, ce qui laisse
/// `perform` retomber sur son comportement one-shot.
pub fn defaultIOHandler(
    store: *Store,
    label: []const u8,
    arg: ?expr.Id,
) engine_expr.EvalError!?expr.Id {
    if (std.mem.eql(u8, label, "Print")) {
        if (arg) |a| {
            const s = expr.toStringInfix(store, a, store.allocator) catch return null;
            defer store.allocator.free(s);
            platform.debug.print("{s}\n", .{s});
        }
        return try store.unitLit();
    }

    if (std.mem.eql(u8, label, "ReadFile")) {
        const path_id = arg orelse return null;
        const path = extractString(store, path_id) orelse return null;
        const content = platform.fs.cwd().readFileAlloc(
            store.allocator,
            path,
            1024 * 1024,
        ) catch return null;
        defer store.allocator.free(content);
        const sym = try store.interner.intern(content);
        return try store.lit(.{ .str = sym });
    }

    if (std.mem.eql(u8, label, "WriteFile")) {
        const pair_id = arg orelse return null;
        const pair_node = store.get(pair_id);
        if (pair_node.tag != .apply) return null;
        const children = store.spanSliceConst(pair_node.span_a);
        var path_id: ?expr.Id = null;
        var content_id: ?expr.Id = null;
        if (children.len == 2) {
            path_id = children[0];
            content_id = children[1];
        } else if (children.len == 3) {
            path_id = children[1];
            content_id = children[2];
        } else return null;

        const path = extractString(store, path_id.?) orelse return null;
        const content = extractString(store, content_id.?) orelse return null;

        const file = platform.fs.cwd().createFile(path, .{}) catch return null;
        defer file.close();
        file.writeAll(content) catch return null;
        return try store.unitLit();
    }

    if (std.mem.eql(u8, label, "ReadLine")) {
        const line = platform.readLine(store.allocator) catch return null;
        defer store.allocator.free(line);
        const sym = try store.interner.intern(line);
        return try store.lit(.{ .str = sym });
    }

    return null;
}

/// Extrait une string d'un Id de littéral. Retourne null si `id`
/// n'est pas un littéral `.str`.
fn extractString(store: *Store, id: expr.Id) ?[]const u8 {
    if (id >= store.len()) return null;
    const node = store.get(id);
    if (node.tag != .lit) return null;
    const lit = store.lits.items[node.aux];
    if (lit != .str) return null;
    return store.interner.resolve(lit.str);
}
