const std = @import("std");
const Guppy = @import("../pkg/guppy.zig").Guppy;

test "Valider l'initialisation du projet via CLI" {
    const allocator = std.testing.allocator;

    // Test de la commande 'pkg init'
    try Guppy.handleCli(allocator, &[_][]const u8{"init"});
    defer std.fs.cwd().deleteFile("guppy.toml") catch {};

    const stat = try std.fs.cwd().statFile("guppy.toml");
    try std.testing.expect(stat.size > 0);
}
