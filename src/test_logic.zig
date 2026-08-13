const std = @import("std");
const matrix_lib = @import("./core/matrix.zig");
const parser_lib = @import("inference/parser.zig");
const reasoning_lib = @import("inference/reasoning.zig");
const guppy = @import("guppy.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = matrix_lib.Matrix.init(allocator);
    defer matrix.deinit();

    var parser = parser_lib.Parser{ .allocator = allocator, .matrix = &matrix };

    // platform.debug.print("\n--- CHARGEMENT DU SCRIPT HVN ---\n", .{});
    try parser.parseFile("scripts/test.hvn");

    // platform.debug.print("\n--- PHASE DE RÉDUCTION ---\n", .{});
    _ = try reasoning_lib.Reasoner.process(&matrix);

    // Export visuel
    try matrix.dumpGraphviz("matrix.dot");
    // platform.debug.print("\nGraphe exporté dans matrix.dot\n", .{});

    // Nettoyage final
    while (guppy.command_queue.get()) |cmd| {
        switch (cmd.data) {
            .AddSymbol => |s| allocator.free(s),
            else => {},
        }
        allocator.destroy(cmd);
    }
}
