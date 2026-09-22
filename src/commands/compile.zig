const std = @import("std");
const expr = @import("expr");
const lowering = @import("../frontend/lowering.zig");
const codegen = @import("../backend/codegen.zig");

pub fn runCompile(allocator: std.mem.Allocator, file_path: []const u8) !void {
    std.debug.print("[COMPILER] Compilation de {s}...\n", .{file_path});

    var store = expr.Store.init(allocator);
    defer store.deinit();

    // Exemple AST à remplacer par la lecture/parsing effective du fichier .hvn
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

    // Émission du fichier de sortie C (output.c)
    const out_file = try std.fs.cwd().createFile("output.c", .{});
    defer out_file.close();

    var writer = out_file.writer();
    try writer.writeAll("// Code généré par Heaven Compiler\n#include <stdio.h>\n\n");

    var emitter = codegen.CodeGenerator.init(&store);
    try emitter.emitC(writer, core_id);
    try writer.writeAll(";\n");

    std.debug.print("[COMPILER] Succès : output.c généré.\n", .{});
}
