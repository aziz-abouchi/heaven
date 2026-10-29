const std = @import("std");
const platform = @import("platform");
const test_runner = @import("../runtime/test_runner.zig");

pub fn runTest(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) return error.TestFailed;
    const target = args[0];

    // Détection dir vs file : si openDir réussit, c'est un dossier
    if (std.fs.cwd().openDir(target, .{})) |_| {
        const any_failed = try test_runner.runTestDir(alloc, target);
        if (any_failed) return error.TestFailed;
        return;
    } else |_| {
        // Fichier : comportement actuel (1 subprocess)
        const exe_path = try std.fs.selfExePathAlloc(alloc);
        defer alloc.free(exe_path);
        const result = try platform.spawnProcess(alloc, &.{ exe_path, "--run-test", target });
        if (result.exit_code != 0) return error.TestFailed;
    }
}
