const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const parse = @import("parse");
const heaven_expr = @import("heaven_expr");
const codegen = @import("../backend/codegen.zig");

/// Convertit un pointeur C nul-terminé (issu de Tree-sitter) en slice Zig.
pub fn span(ptr: [*c]const u8) []const u8 {
    if (ptr == null) return "";
    return std.mem.span(ptr);
}

pub fn runCompile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    platform.debug.print("[COMPILER] Compilation de {s}...\n", .{file_path});

    // Lecture (pattern test_runner.zig — éprouvé sous Zig 0.15)
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const stat = try file.stat();
    const source = try allocator.alloc(u8, stat.size);
    defer allocator.free(source);
    _ = try file.readAll(source);

    // Pipeline canonique : Heaven (store+engine+env) → Parser → S-expr → Core
    var heaven = heaven_expr.Heaven.init(allocator) catch return error.HeavenInit;
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var parser = parse.Parser.init(heaven.store, &heaven.engine, &heaven.env, allocator);
    defer parser.deinit();

    const out_file = try std.fs.cwd().createFile("output.c", .{});
    defer out_file.close();
    try out_file.writeAll("// Code généré par Heaven Compiler\n#include <stdio.h>\n\n");

    var emitter = codegen.CodeGenerator.init(heaven.store);

    // Chaque ligne non-vide = une expression compilée
    // (même règle de skip que test_runner.zig)
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '/') continue;

        const root_id = try parser.parseSExpr(trimmed);
        try emitter.emitC(out_file, root_id);
        try out_file.writeAll(";\n");
    }

    platform.debug.print("[COMPILER] Succès : output.c généré.\n", .{});
}

pub fn emitFnDecl(
    allocator: std.mem.Allocator,
    source: []const u8,
    node: anytype,
    writer: anytype,
    header_writer: anytype,
) !void {
    _ = allocator;
    _ = header_writer;

    // Récupération du morceau de code source correspondant au nœud
    if (@hasField(@TypeOf(node), "start_byte") and @hasField(@TypeOf(node), "end_byte")) {
        const slice = source[node.start_byte..node.end_byte];
        try writer.writeAll(slice);
    } else {
        try writer.writeAll("// fn decl\n");
    }
}

pub fn emitStructDecl(
    source: []const u8,
    node: anytype,
    writer: anytype,
) !void {
    if (@hasField(@TypeOf(node), "start_byte") and @hasField(@TypeOf(node), "end_byte")) {
        const slice = source[node.start_byte..node.end_byte];
        try writer.writeAll(slice);
    } else {
        try writer.writeAll("// struct decl\n");
    }
}

pub fn emitEnumDecl(
    source: []const u8,
    node: anytype,
    writer: anytype,
) !void {
    if (@hasField(@TypeOf(node), "start_byte") and @hasField(@TypeOf(node), "end_byte")) {
        const slice = source[node.start_byte..node.end_byte];
        try writer.writeAll(slice);
    } else {
        try writer.writeAll("// enum decl\n");
    }
}

pub fn emitEffectDecl(
    source: []const u8,
    node: anytype,
    writer: anytype,
) !void {
    if (@hasField(@TypeOf(node), "start_byte") and @hasField(@TypeOf(node), "end_byte")) {
        const slice = source[node.start_byte..node.end_byte];
        try writer.writeAll(slice);
    } else {
        try writer.writeAll("// effect decl\n");
    }
}

pub fn emitTestDecl(
    source: []const u8,
    node: anytype,
    writer: anytype,
) !void {
    if (@hasField(@TypeOf(node), "start_byte") and @hasField(@TypeOf(node), "end_byte")) {
        const slice = source[node.start_byte..node.end_byte];
        try writer.writeAll(slice);
    } else {
        try writer.writeAll("// test decl\n");
    }
}
