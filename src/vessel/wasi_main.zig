// HEAVEN:wasi_main — entrée WASI (Wasmtime).
// Minimal : args -> eval -> stdout. Pas de REPL interactif.
// Voir docs/spec/_platform_refactor_plan.md (chantier stubs WASI).
const std = @import("std");
const heaven_expr = @import("heaven_expr");
const platform = @import("platform");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        platform.io.printOut("usage: heaven-wasi <expr>\n", .{});
        return;
    }

    // Joindre tous les args en une expression unique.
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    for (args[1..], 0..) |a, i| {
        if (i > 0) try buf.append(allocator, ' ');
        try buf.appendSlice(allocator, a);
    }

    const heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    const result = try heaven.eval(buf.items);
    defer allocator.free(result);

    platform.io.printOut("{s}\n", .{result});
}
