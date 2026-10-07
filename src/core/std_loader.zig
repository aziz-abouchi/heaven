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
    var accumulate_buffer = std.ArrayListUnmanaged(u8){};
    defer accumulate_buffer.deinit(heaven.allocator);
    var depth: i32 = 0;
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 and depth == 0) continue;
        if (accumulate_buffer.items.len == 0) {
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '#') continue;
            if (std.mem.startsWith(u8, trimmed, "--")) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;
            if (std.mem.startsWith(u8, trimmed, ";;")) continue;
        }
        // Ajoute la ligne au buffer (avec espace si necessaire).
        if (accumulate_buffer.items.len > 0) {
            accumulate_buffer.append(heaven.allocator, ' ') catch continue;
        }
        accumulate_buffer.appendSlice(heaven.allocator, trimmed) catch continue;
        // Compte les parentheses ouvrantes/fermantes dans cette ligne.
        for (trimmed) |c| {
            if (c == '(') depth += 1;
            if (c == ')') depth -= 1;
        }
        // Si equilibre ET que le buffer ne finit pas par '=',
        // evaluer le bloc accumule. La condition sur '=' permet
        // d'attendre le body sur la ligne suivante.
        if (depth <= 0) {
            const buf_t = std.mem.trimRight(u8, accumulate_buffer.items, " \t\r");
            const ends_with_eq = buf_t.len > 0 and buf_t[buf_t.len - 1] == '=';
            if (!ends_with_eq) {
                const block = accumulate_buffer.items;
                const result = heaven.eval(block) catch |err| {
                    platform.dbg("[std_loader] {s} '{s}' failed: {}\n", .{ path, block, err });
                    accumulate_buffer.clearRetainingCapacity();
                    depth = 0;
                    continue;
                };
                heaven.allocator.free(result);
                accumulate_buffer.clearRetainingCapacity();
                depth = 0;
            }
        }
    }
    // Reste eventuel (parens non equilibrees).
    if (accumulate_buffer.items.len > 0) {
        const result = heaven.eval(accumulate_buffer.items) catch |err| {
            platform.dbg("[std_loader] {s} 'unterminated' failed: {}\n", .{ path, err });
            return;
        };
        heaven.allocator.free(result);
    }
}

// ─── Tests ───

test "std_loader — files contient les 6 entrées attendues" {
    try std.testing.expectEqual(@as(usize, 10), files.len);
    try std.testing.expectEqualStrings("core/io.hvn", files[0]);
    try std.testing.expectEqualStrings("core/std/bool.hvn", files[1]);
    try std.testing.expectEqualStrings("core/std/result.hvn", files[5]);
}
