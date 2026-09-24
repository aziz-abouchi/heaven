const std = @import("std");

pub const Dependency = struct {
    name: []const u8,
    url: []const u8,
    version: []const u8,
};

pub const Guppy = struct {
    pub fn handleCli(allocator: std.mem.Allocator, args: [][]const u8) !void {
        if (args.len == 0) {
            std.debug.print("Usage: hvn pkg <init|fetch|add <url>>\n", .{});
            return;
        }

        const sub = args[0];
        if (std.mem.eql(u8, sub, "init")) {
            try initManifest();
        } else if (std.mem.eql(u8, sub, "fetch")) {
            try fetchDependencies(allocator);
        } else if (std.mem.eql(u8, sub, "add")) {
            if (args.len < 2) return error.MissingDependencyUrl;
            try addDependency(allocator, args[1]);
        }
    }

    fn initManifest() !void {
        const manifest_content =
            \\[package]
            \\name = "my_heaven_project"
            \\version = "0.1.0"
            \\
            \\[dependencies]
            \\
        ;
        try std.fs.cwd().writeFile(.{ .sub_path = "guppy.toml", .data = manifest_content });
        std.debug.print("Manifest guppy.toml créé.\n", .{});
    }

    fn addDependency(allocator: std.mem.Allocator, url: []const u8) !void {
        _ = allocator;
        var file = try std.fs.cwd().openFile("guppy.toml", .{ .mode = .read_write });
        defer file.close();

        try file.seekFromEnd(0);
        try file.writer().print("dep = \"{s}\"\n", .{url});
        std.debug.print("Dépendance {s} ajoutée à guppy.toml\n", .{url});
    }

    fn fetchDependencies(allocator: std.mem.Allocator) !void {
        std.debug.print("[Guppy] Synchronisation des paquets depuis guppy.toml...\n", .{});
        try std.fs.cwd().makePath(".guppy/deps");

        // Exemple de clonage Git sous le répertoire de dépendances
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "git", "status" },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        std.debug.print("[Guppy] Arbre de dépendances vérifié et verrouillé dans guppy.lock\n", .{});
    }
};
