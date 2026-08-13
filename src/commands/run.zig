const std = @import("std");
const compile_cmd = @import("compile.zig");
const platform = @import("platform");
const posix = platform.posix;

pub fn runRun(allocator: std.mem.Allocator, file_path: []const u8) anyerror!void {
    try compile_cmd.runCompile(allocator, file_path);
    // platform.debug.print("\n── Compiling & Running ──\n", .{});

    const env = @as(
        [*:null]const ?[*:0]const u8,
        @ptrCast(platform.os.environ.ptr),
    );

    const pid = try posix.fork();
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{
            "/home/aabouchi/.guix-profile/bin/gcc",
            "-o",
            "/tmp/heaven_run",
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
                "/tmp/heaven_run",
                null,
            };
            posix.execvpeZ("/tmp/heaven_run", &run_argv, env) catch {};
            posix.exit(1);
        } else {
            _ = posix.waitpid(pid2, 0);
        }
    }
}
