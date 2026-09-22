const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const lowering = @import("../frontend/lowering.zig");
const codegen = @import("../backend/codegen.zig");

/// Convertit un pointeur C nul-terminé (issu de Tree-sitter) en slice Zig.
pub fn span(ptr: [*c]const u8) []const u8 {
    if (ptr == null) return "";
    return std.mem.span(ptr);
}

pub fn runCompile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    _ = platform; // Module platform disponible pour l'intégration I/O système
    std.debug.print("[COMPILER] Compilation de {s}...\n", .{file_path});

    var store = expr.Store.init(allocator);
    defer store.deinit();

    const sample_ast = lowering.ASTNode{
        .Call = .{
            .func = "add",
            .args = &.{
                .{ .Int = 10 },
                .{ .Int = 32 },
            },
        },
    };

    const core_id = try lowering.lowerAST(allocator, &store, sample_ast);

    const out_file = try std.fs.cwd().createFile("output.c", .{});
    defer out_file.close();

    try out_file.writeAll("// Code généré par Heaven Compiler\n#include <stdio.h>\n\n");

    var emitter = codegen.CodeGenerator.init(&store);
    try emitter.emitC(out_file, core_id);
    try out_file.writeAll(";\n");

    std.debug.print("[COMPILER] Succès : output.c généré.\n", .{});
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
