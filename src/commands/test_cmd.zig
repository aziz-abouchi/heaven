const std = @import("std");
const platform = @import("platform");

pub fn runTest(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) return error.TestFailed;

    // Relance le binaire courant avec --run-test : isole le fichier
    // dans un sous-processus (panic/abort/crash = échec local, la
    // suite peut continuer), comme runTestDir (test_runner.zig).
    const exe_path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(exe_path);

    const result = try platform.spawnProcess(alloc, &.{ exe_path, "--run-test", args[0] });
    if (result.exit_code != 0) {
        return error.TestFailed;
    }
}
