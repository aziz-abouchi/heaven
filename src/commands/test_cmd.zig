const std = @import("std");
const compile_cmd = @import("compile.zig");
const platform = @import("platform");
const posix = platform.posix;

pub fn runTest(allocator: std.mem.Allocator, file_path: []const u8) anyerror!void {
    // First compile normally
    try compile_cmd.runCompile(allocator, file_path);

    // Read the generated C, find main, inject test runner
    // For now: just compile and run, tests are in main
    platform.debug.print("── Running tests from {s} ──\n", .{file_path});

    const env = @as(
        [*:null]const ?[*:0]const u8,
        @ptrCast(platform.os.environ.ptr),
    );

    const pid = try posix.fork();
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{
            "/home/aabouchi/.guix-profile/bin/gcc",
            "-o",
            "/tmp/heaven_test_bin",
            "output.c",
            "-lm",
            null,
        };
        posix.execvpeZ("/home/aabouchi/.guix-profile/bin/gcc", &argv, env) catch {};
        posix.exit(1);
    } else {
        _ = posix.waitpid(pid, 0);

        const pid2 = try posix.fork();
        if (pid2 == 0) {
            const run_argv = [_:null]?[*:0]const u8{
                "/tmp/heaven_test_bin",
                null,
            };
            posix.execvpeZ("/tmp/heaven_test_bin", &run_argv, env) catch {};
            posix.exit(1);
        } else {
            _ = posix.waitpid(pid2, 0);
        }
    }
}
