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

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        if (std.mem.startsWith(u8, trimmed, "--")) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;
        if (std.mem.startsWith(u8, trimmed, ";;")) continue;

        const result = heaven.eval(trimmed) catch |err| {
            platform.dbg("[std_loader] {s} '{s}' failed: {}\n", .{ path, trimmed, err });
            continue;
        };
        heaven.allocator.free(result);
    }
}

// ─── Tests ───

test "std_loader — files contient les 6 entrées attendues" {
    try std.testing.expectEqual(@as(usize, 6), files.len);
    try std.testing.expectEqualStrings("core/io.hvn", files[0]);
    try std.testing.expectEqualStrings("core/std/bool.hvn", files[1]);
    try std.testing.expectEqualStrings("core/std/result.hvn", files[5]);
}
