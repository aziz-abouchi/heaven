const std = @import("std");
const Guppy = @import("../pkg/guppy.zig").Guppy;

test "Guppy Package Manager - Initialisation et Manifeste" {
    const allocator = std.testing.allocator;

    const args = &[_][]const u8{"init"};
    try Guppy.handleCli(allocator, args);
    defer std.fs.cwd().deleteFile("guppy.toml") catch {};

    const exists = try std.fs.cwd().statFile("guppy.toml");
    try std.testing.expect(exists.size > 0);
}
