const std = @import("std");
const compile_cmd = @import("compile.zig");
const platform = @import("platform");
const posix = platform.posix;

pub fn runTest(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const result = try platform.spawnProcess(alloc, args);
    if (result.exit_code != 0) {
        return error.TestFailed;
    }
}
