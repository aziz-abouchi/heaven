// HEAVEN:WASM_FIX2
const std = @import("std");
const sp = @import("shell_parser_types.zig");
const builtin = @import("builtin");

extern fn heaven_log(ptr: [*]const u8, len: usize) void;

pub const target = struct {
    pub const os = struct { pub const tag = .freestanding; };
    pub const cpu = struct { pub const arch = .wasm32; };
    pub const is_debug = (builtin.mode == .Debug);
    pub const is_wasm = true;
};

pub const allocator = std.heap.wasm_allocator;

pub fn getenv(_: []const u8) ?[]const u8 { return null; }

pub fn readFileAllocCwd(alloc: std.mem.Allocator, p_: []const u8, max: usize) ![]u8 {
    _ = alloc; _ = p_; _ = max;
    return error.FileNotFound;
}

// Stubs no-op pour compat API natif.
pub var debug_enabled: bool = false;
pub fn dbg(comptime fmt: []const u8, args: anytype) void { _ = fmt; _ = args; }

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

pub fn readLine(alloc: std.mem.Allocator) ![]u8 { _ = alloc; return error.Unsupported; }

pub const fs = struct {
    pub const File = struct {
        pub const OpenError = error{Unsupported};
        pub const ReadError = error{Unsupported};
        pub const WriteError = error{Unsupported};
        pub fn close(self: File) void { _ = self; }
        pub fn writeAll(self: File, buf: []const u8) !void { _ = self; _ = buf; return error.Unsupported; }
        pub fn readAll(self: File, buf: []u8) !usize { _ = self; _ = buf; return error.Unsupported; }
    };
    pub fn openFile(p: []const u8, _: anytype) !File { _ = p; return error.Unsupported; }

    pub const path = struct {
        pub fn basename(p: []const u8) []const u8 { return p; }
        pub fn dirname(p: []const u8) []const u8 { return p; }
        pub fn extension(p: []const u8) []const u8 { return p; }
        pub fn isAbsolute(p: []const u8) bool { return p.len > 0 and p[0] == '/'; }
        pub fn join(alloc: std.mem.Allocator, parts: []const []const u8) error{ NotFound, OutOfMemory }![]u8 {
            _ = alloc; _ = parts; return error.NotFound;
        }
    };

    pub const Dir = struct {
        pub fn readFileAlloc(self: Dir, alloc: std.mem.Allocator, p_: []const u8, max: usize) ![]u8 {
            _ = self; _ = alloc; _ = p_; _ = max;
            return error.Unsupported;
        }
        pub fn createFile(self: Dir, p_: []const u8, _: anytype) !File {
            _ = self; _ = p_; return error.Unsupported;
        }
        pub fn openFile(self: Dir, p_: []const u8, _: anytype) !File {
            _ = self; _ = p_; return error.Unsupported;
        }
    };
    pub fn cwd() Dir { return .{}; }
};

pub const shell_parser_types = sp;
pub const net = struct {
    pub fn listenTcp(_: u16) !i64 { return error.NotSupported; }
    pub fn accept(_: i64) !i64 { return error.NotSupported; }
    pub fn read(_: i64, _: []u8) !usize { return error.NotSupported; }
    pub fn write(_: i64, _: []const u8) !usize { return error.NotSupported; }
    pub fn close(_: i64) void {}
    pub fn httpRespond(_: i64, _: []const u8) !void { return error.Unsupported; }
};

pub const ShellParser = sp.ShellParser;
pub const init = ShellParser.init;
pub const parse = ShellParser.parse;
pub const reset = ShellParser.reset;

pub const time = struct {
    pub fn timestampMs() i64 { return 0; }
    pub fn nanoTimestamp() i128 { return 0; }
    pub const ns_per_s: u64 = 1_000_000_000;
    pub const ns_per_us: u64 = 1_000;
    pub const milliTimestamp = timestampMs;
};

pub fn readEnergyUJ() !u64 { return error.Unsupported; }

pub const profiler = struct {
    pub const ResourceUsage = struct {
        utime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        stime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        maxrss: u64 = 0,
    };
    pub fn getResourceUsage() ResourceUsage { return .{}; }
    pub fn readEnergyUJ() ?u64 { return null; }
};

var dummy_payload_buf: [1]u8 = .{0};

pub const js_env = struct {
    pub fn js_console_log(ptr: [*]const u8, len: usize) void { _ = ptr; _ = len; }
    pub fn js_drain_message_queue() u32 { return 0; }
    pub fn js_get_peer_id(_: u32, out: *[16]u8) void { _ = out; }
    pub fn js_get_msg_type(_: u32) u32 { return 0; }
    pub fn js_get_payload_ptr(_: u32) usize { _ = &dummy_payload_buf; return 0; }
    pub fn js_get_payload_len(_: u32) usize { return 0; }
    pub fn js_broadcast_proof_request(_: [*]const u8, _: usize) void {}
    pub fn js_free_message(_: u32) void {}
};
