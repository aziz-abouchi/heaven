const std = @import("std");
const sp = @import("shell_parser_types.zig");
const builtin = @import("builtin");

extern fn heaven_log(ptr: [*]const u8, len: usize) void;

pub const target = struct {
    pub const os = struct { pub const tag = .freestanding; };
    pub const cpu = struct { pub const arch = .wasm32; };
    pub const is_debug = (builtin.mode == .Debug);
};

pub const allocator = std.heap.wasm_allocator;

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        var buf: [512]u8 = undefined;
        var s = std.io.fixedBufferStream(&buf);
        s.writer().print(fmt, args) catch return;
        heaven_log(s.getWritten().ptr, s.getWritten().len);
    }
    pub fn readLine(alloc: std.mem.Allocator) ![]u8 { _ = alloc; return error.Unsupported; }
};

pub const debug = io;

pub const fs = struct {
    pub const File = struct {
        pub const OpenError = error{Unsupported};
    };
    pub fn openFile(p: []const u8, _: anytype) !File { _ = p; return error.Unsupported; }
    pub const cwd = struct {
        pub fn get() []const u8 { return ""; }
    };
};

pub const ShellParser = sp.ShellParser;
pub const init = ShellParser.init;
pub const parse = ShellParser.parse;
pub const reset = ShellParser.reset;

pub const time = struct {
    pub fn timestampMs() i64 { return 0; }
    pub const milliTimestamp = timestampMs;
};

pub const profiler = struct {
    pub const ResourceUsage = struct { utime: struct{sec:i64=0,usec:i64=0}={}, stime: struct{sec:i64=0,usec:i64=0}={}, maxrss:u64=0 };
    pub fn getResourceUsage() ResourceUsage { return .{}; }
    pub fn readEnergyUJ() ?u64 { return null; }
};

pub const js_env = struct {
    pub fn js_console_log(msg: []const u8) void { _ = msg; }
    pub fn js_drain_message_queue() ?[]const u8 { return null; }
};
