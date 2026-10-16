const std = @import("std");
const shell_parser_types = @import("shell_parser_types.zig");

pub fn args(alloc: std.mem.Allocator) ![][]const u8 {
    return std.process.argsAlloc(alloc)[1..];
}

pub fn initConsole() void {}

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args_: anytype) void {
        std.debug.print(fmt, args_);
    }
    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        const stdin = std.io.getStdIn().reader();
        return try stdin.readUntilDelimiterAlloc(alloc, '\n', 4096);
    }
};

pub const allocator = std.heap.page_allocator;

pub const ShellParser = @import("shell_parser");

pub const MultiParser = union(shell_parser_types.Language) {
    heaven: ShellParser,
    turtle, // ✅ Manquait
};

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

pub const net = struct {

    // D-SH4 : socket/connect TCP client. Pas de support en V0
    // sur cette cible. Voir _selfhosting_roadmap.md.

    // D-SH4 : UDP raw syscalls. Pas de support en V0.

    pub fn setRecvTimeout(_: i64, _: u64) void {}

    pub fn socketUdp() i64 { return -1; }
    pub fn sendtoUdp(_: i64, _: []const u8, _: u16, _: []const u8) i64 { return -1; }
    pub fn recvfromUdp(_: i64, _: []u8) i64 { return -1; }

    pub fn socketTcp() i64 {
        return -1;
    }

    pub fn connectTcp(_: []const u8, _: u16) !i64 {
        return error.NotSupported;
    }

    pub fn listenTcp(port: u16) !std.net.Server {
        return std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port).listen(.{});
    }
};
