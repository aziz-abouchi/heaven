const std = @import("std");

// Renommer le paramètre pour éviter le masquage
pub fn args(alloc: std.mem.Allocator) ![][]const u8 {
    var argv = try std.process.argsAlloc(alloc);
    // ignorer le nom du programme si besoin
    return argv[1..];
}

pub const allocator = std.heap.wasm_allocator;

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args_: anytype) void {
        std.debug.print(fmt, args_);
    }
    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        const stdin = std.io.getStdIn().reader();
        return try stdin.readUntilDelimiterAlloc(alloc, '\n', 4096);
    }
};

pub const ShellParser = @import("shell_parser");

pub const time = struct {
    pub fn timestampMs() i64 {
        return std.time.milliTimestamp();
    }
};

pub const fs = struct {
    pub const cwd = struct {
        pub fn readFileAlloc(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
            return std.fs.cwd().readFileAlloc(alloc, path, 1024 * 1024);
        }
        pub fn createFile(path: []const u8, data: []const u8) !void {
            try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
        }
    };
};

pub fn getEnv(alloc: std.mem.Allocator, key: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(alloc, key) catch |e| switch (e) {
        error.EnvironmentVariableNotFound => return null,
        else => return e,
    };
}
