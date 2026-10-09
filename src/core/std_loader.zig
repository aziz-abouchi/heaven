//! std_loader.zig — chargement des sources Heaven au boot (RFC-0001 4/5).
//!
//! Extrait de heaven_expr.zig. Chargé par `Heaven.init` pour peupler
//! le FunctionRegistry avec io.hvn + les std/*.hvn, ligne par ligne
//! via `heaven.eval` (chemin qui passe par evalDataDecl → ctor_arity OK).
//!
//! Le paramètre `heaven` est `anytype` pour éviter un cycle d'import
//! avec heaven_expr.zig (Heaven y est défini). En pratique : un
//! `*Heaven` avec les champs `allocator: Allocator`, `current_module:
//! ?[]const u8`, `eval: fn([]const u8) ![]u8`.

const std = @import("std");
const platform = @import("platform");

/// Fichiers chargés au boot, dans l'ordre.
pub const files = [_][]const u8{
    "core/io.hvn",
    "core/std/bool.hvn",
    "core/std/list.hvn",
    "core/std/option.hvn",
    "core/std/pair.hvn",
    "core/std/result.hvn",
    "core/stream.hvn",
    "core/io_stream.hvn",
    "core/http.hvn",
    "core/bigint.hvn",
    "core/std/array.hvn",
    "core/std/string.hvn",
    "core/std/hashmap.hvn",
    "core/std/recursion.hvn",
    "core/std/lens.hvn",
};

/// Charge tous les fichiers std dans le `heaven` fourni.
pub fn loadAll(heaven: anytype) void {
    for (files) |path| loadOne(heaven, path);
}

/// Charge un fichier ligne par ligne via `heaven.eval`. Ignore les
/// lignes vides et les commentaires (`#`, `--`, `//`, `;;`).
/// Sauve/restaure `heaven.current_module` : un fichier std peut
/// contenir `module Foo`, et sans ce restore l'état fuit après init
/// (cassait les tests module v1).
pub fn loadOne(heaven: anytype, path: []const u8) void {
    const source = platform.fs.cwd().readFileAlloc(
        heaven.allocator,
        path,
        64 * 1024,
    ) catch |err| {
        platform.dbg("[std_loader] readFileAlloc {s} failed: {}\n", .{ path, err });
        return;
    };
    defer heaven.allocator.free(source);

    const old_module = heaven.current_module;
    defer {
        if (heaven.current_module) |m| heaven.allocator.free(m);
        heaven.current_module = old_module;
    }

    // Accumulation multi-ligne : on joint les lignes tant que les
    // parentheses ne sont pas equilibrees. Permet les definitions
    // lisibles (let ... in sur plusieurs lignes).
    // Accumulation par indentation : une ligne non-indentee (colonne 0)
    // commence un nouveau statement. Toutes les lignes indentees qui
    // suivent sont des continuations (style Haskell/Python).
    var accumulate_buffer = std.ArrayListUnmanaged(u8){};
    defer accumulate_buffer.deinit(heaven.allocator);
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        if (std.mem.startsWith(u8, trimmed, "--")) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        if (std.mem.startsWith(u8, trimmed, ";;")) continue;

        // Indentation : la ligne originale commence par un espace/tab.
        const is_indented = line.len > 0 and (line[0] == ' ' or line[0] == '\t');

        // Si le buffer est non vide et que la ligne n'est PAS indentee,
        // c'est un nouveau statement : evaluer l'ancien.
        if (accumulate_buffer.items.len > 0 and !is_indented) {
            const result = heaven.eval(accumulate_buffer.items) catch |err| {
                platform.dbg("[std_loader] {s} '{s}' failed: {}\n", .{ path, accumulate_buffer.items, err });
                accumulate_buffer.clearRetainingCapacity();
                continue;
            };
            heaven.allocator.free(result);
            accumulate_buffer.clearRetainingCapacity();
        }

        // Ajouter la ligne au buffer.
        if (accumulate_buffer.items.len > 0) {
            accumulate_buffer.append(heaven.allocator, ' ') catch continue;
        }
        accumulate_buffer.appendSlice(heaven.allocator, trimmed) catch continue;
    }
    // Reste eventuel.
    if (accumulate_buffer.items.len > 0) {
        const result = heaven.eval(accumulate_buffer.items) catch |err| {
            platform.dbg("[std_loader] {s} 'final' failed: {}\n", .{ path, err });
            return;
        };
        heaven.allocator.free(result);
    }
}

// ─── Tests ───

test "std_loader — files contient les 6 entrées attendues" {
    try std.testing.expectEqual(@as(usize, 12), files.len);
    try std.testing.expectEqualStrings("core/io.hvn", files[0]);
    try std.testing.expectEqualStrings("core/std/bool.hvn", files[1]);
    try std.testing.expectEqualStrings("core/std/result.hvn", files[5]);
}
