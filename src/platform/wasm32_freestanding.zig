const std = @import("std");

pub fn args(_: std.mem.Allocator) ![][]const u8 {
    return &.{};
}

pub const allocator = std.heap.wasm_allocator;

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args_: anytype) void {
        std.debug.print(fmt, args_);
    }
    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        _ = alloc;
        return error.Unsupported;
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
            _ = alloc;
            _ = path;
            return error.Unsupported;
        }
        pub fn createFile(path: []const u8, data: []const u8) !void {
            _ = path;
            _ = data;
            return error.Unsupported;
        }
    };
};

pub fn getEnv(alloc: std.mem.Allocator, key: []const u8) !?[]u8 {
    _ = alloc;
    _ = key;
    return null;
}
