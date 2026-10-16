// HEAVEN:process — extraction process (refactor plateforme)
const std = @import("std");

pub const ProcessResult = struct {
    exit_code: u8,
};

pub fn spawnProcess(alloc: std.mem.Allocator, argv: []const []const u8) !ProcessResult {
    var child = std.process.Child.init(argv, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| ProcessResult{ .exit_code = @truncate(code) },
        else => ProcessResult{ .exit_code = 1 },
    };
}
