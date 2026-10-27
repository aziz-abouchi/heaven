// HEAVEN:wasm32_wasi — implementation WASI preview1 (Wasmtime).
// Contrat identique a x86_64_linux.zig sauf net (pas de sockets en preview1).
// js_env est un no-op : WASI n'a pas de host JS. Voir _platform_refactor_plan.md.
const std = @import("std");
const builtin = @import("builtin");
const sp = @import("shell_parser_types.zig");

// ─── WASI preview1 externs ─────────────────────────────────────
const fd_t = u32;
const errno_t = u16;
const ciovec_t = extern struct { buf: [*]const u8, buf_len: usize };
const iovec_t = extern struct { buf: [*]u8, buf_len: usize };
const lookupflags_t = u32;
const oflags_t = u16;
const rights_t = u64;
const fdflags_t = u16;

extern "wasi_snapshot_preview1" fn fd_write(fd: fd_t, iovs: [*]const ciovec_t, iovs_len: usize, nwritten: *usize) errno_t;
extern "wasi_snapshot_preview1" fn fd_read(fd: fd_t, iovs: [*]const iovec_t, iovs_len: usize, nread: *usize) errno_t;
extern "wasi_snapshot_preview1" fn fd_close(fd: fd_t) errno_t;
extern "wasi_snapshot_preview1" fn path_open(dirfd: fd_t, dirflags: lookupflags_t, path: [*]const u8, path_len: usize, oflags: oflags_t, rights_base: rights_t, rights_inheriting: rights_t, fdflags: fdflags_t, opened_fd: *fd_t) errno_t;
extern "wasi_snapshot_preview1" fn clock_time_get(id: u32, precision: u64, time: *u64) errno_t;
extern "wasi_snapshot_preview1" fn random_get(buf: [*]u8, buf_len: usize) errno_t;

// ─── target ────────────────────────────────────────────────────
pub const target = struct {
    pub const os = builtin.os.tag;
    pub const arch = builtin.cpu.arch;
    pub const is_windows = false;
    pub const is_darwin = false;
    pub const is_linux = false;
    pub const is_wasm = true;
    pub const is_debug = builtin.mode == .Debug;
};

pub const allocator = std.heap.wasm_allocator;

// ─── io : fd_write/read WASI ───────────────────────────────────
pub const io = struct {
    fn writeFd(fd: fd_t, bytes: []const u8) void {
        if (bytes.len == 0) return;
        var iov = ciovec_t{ .buf = bytes.ptr, .buf_len = bytes.len };
        var n: usize = 0;
        _ = fd_write(fd, @ptrCast(&iov), 1, &n);
    }

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
        writeFd(2, s);
    }

    pub fn printOut(comptime fmt: []const u8, args: anytype) void {
        var buf: [4096]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
        writeFd(1, s);
    }

    pub fn readLine(a: std.mem.Allocator) ![]u8 {
        var tmp: [4096]u8 = undefined;
        var iov = iovec_t{ .buf = &tmp, .buf_len = tmp.len };
        var n: usize = 0;
        if (fd_read(0, @ptrCast(&iov), 1, &n) != 0) return error.ReadFailed;
        if (n == 0) return error.EndOfStream;
        var line = tmp[0..n];
        if (line.len > 0 and line[line.len - 1] == '\n') line = line[0 .. line.len - 1];
        return a.dupe(u8, line);
    }
};

pub const io_console = struct {
    pub var debug_enabled: bool = false;
    pub fn dbg(comptime fmt: []const u8, args: anytype) void {
        if (debug_enabled) io.print(fmt, args);
    }
};

pub const dbg = io_console.dbg;

pub const debug = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void { io.print(fmt, args); }
};

pub fn writeStdout(buf: []const u8) !usize {
    if (buf.len == 0) return 0;
    var iov = ciovec_t{ .buf = buf.ptr, .buf_len = buf.len };
    var n: usize = 0;
    _ = fd_write(1, @ptrCast(&iov), 1, &n);
    return n;
}

pub fn readStdin(buf: []u8) !usize {
    if (buf.len == 0) return 0;
    var iov = iovec_t{ .buf = buf.ptr, .buf_len = buf.len };
    var n: usize = 0;
    _ = fd_read(0, @ptrCast(&iov), 1, &n);
    return n;
}

pub fn getenv(_: []const u8) ?[]const u8 { return null; }

// ─── fs : path_open + fd_read ─────────────────────────────────
pub const fs = struct {
    pub const File = struct {
        pub const OpenError = error{ FileNotFound, AccessDenied, Unsupported };
        pub const ReadError = error{ ReadFailed, EndOfStream, FileTooBig, Unsupported };
        pub const WriteError = error{ WriteFailed, Unsupported };
        pub fn close(_: *const File) void {}
        pub fn writeAll(_: *const File, _: []const u8) !void { return error.Unsupported; }
    };

    fn openRead(p: []const u8) !fd_t {
        var fd: fd_t = 0;
        const RIGHTS_READ: rights_t = 2;
        const err = path_open(3, 0, p.ptr, p.len, 0, RIGHTS_READ, 0, 0, &fd);
        if (err != 0) return error.FileNotFound;
        return fd;
    }

    const Dir = struct {
        pub fn readFileAlloc(_: Dir, a: std.mem.Allocator, p: []const u8, max: usize) ![]u8 {
            const fd = try openRead(p);
            defer _ = fd_close(fd);
            var out = std.ArrayListUnmanaged(u8){};
            errdefer out.deinit(a);
            var chunk: [4096]u8 = undefined;
            while (true) {
                if (out.items.len >= max) return error.FileTooBig;
                var iov = iovec_t{ .buf = &chunk, .buf_len = chunk.len };
                var n: usize = 0;
                if (fd_read(fd, @ptrCast(&iov), 1, &n) != 0) return error.ReadFailed;
                if (n == 0) break;
                try out.appendSlice(a, chunk[0..n]);
            }
            return out.toOwnedSlice(a);
        }
        pub fn openFile(_: Dir, p: []const u8, _: anytype) !File {
            _ = try openRead(p);
            return File{};
        }
        pub fn createFile(_: Dir, _: []const u8, _: anytype) !File {
            return error.Unsupported;
        }
    };
    pub fn cwd() Dir { return .{}; }

    pub const path = std.fs.path;
};

pub fn readFileAllocCwd(a: std.mem.Allocator, p: []const u8, m: usize) ![]u8 {
    return fs.cwd().readFileAlloc(a, p, m);
}

// ─── time : clock_time_get ─────────────────────────────────────
pub const time = struct {
    pub const ns_per_s = std.time.ns_per_s;
    pub const ns_per_us = std.time.ns_per_us;
    pub fn milliTimestamp() i64 {
        var t: u64 = 0;
        _ = clock_time_get(0, 1_000_000, &t);
        return @intCast(t / 1_000_000);
    }
    pub fn nanoTimestamp() i128 {
        var t: u64 = 0;
        _ = clock_time_get(0, 1, &t);
        return @intCast(t);
    }
    pub fn sleep(_: u64) void {}
};


// ─── js_env : no-op (pas de host JS sous WASI/Wasmtime) ────────
pub const js_env = struct {
    pub fn js_console_log(_: [*]const u8, _: usize) void {}
    pub fn js_console_error(_: [*]const u8, _: usize) void {}
    pub fn js_drain_message_queue() u32 { return 0; }
    pub fn js_get_peer_id(_: u32, _: *[16]u8) void {}
    pub fn js_get_msg_type(_: u32) u32 { return 0; }
    pub fn js_get_timestamp(_: u32) i64 { return 0; }
    pub fn js_get_payload_ptr(_: u32) u32 { return 0; }
    pub fn js_get_payload_len(_: u32) u32 { return 0; }
    pub fn js_free_message(_: u32) void {}
    pub fn js_write_stdout(_: [*]const u8, _: usize) void {}
    pub fn js_write_stderr(_: [*]const u8, _: usize) void {}
    pub fn js_websocket_connect(_: [*]const u8, _: usize) i32 { return -1; }
    pub fn js_websocket_send(_: [*]const u8, _: usize) i32 { return -1; }
    pub fn js_rtc_connect(_: [*]const u8, _: usize) i32 { return -1; }
    pub fn js_rtc_send(_: [*]const u8, _: usize) i32 { return -1; }
    pub fn js_broadcast_proof_request(_: [*]const u8, _: usize) void {}
    pub fn vesselLogWrite(_: [*]const u8, _: usize) void {}
};

// ─── net : WASI preview1 n'a pas de sockets ────────────────────
pub const net = struct {
    pub fn socketTcp() i64 { return -1; }
    pub fn socketUdp() i64 { return -1; }
    pub fn sendtoUdp(_: i64, _: []const u8, _: u16, _: []const u8) i64 { return -1; }
    pub fn recvfromUdp(_: i64, _: []u8) i64 { return -1; }
    pub fn setRecvTimeout(_: i64, _: u64) void {}
    pub fn connectTcp(_: []const u8, _: u16) !i64 { return error.NotSupported; }
    pub fn listenTcp(_: u16) !i64 { return error.NotSupported; }
    pub fn accept(_: i64) !i64 { return error.NotSupported; }
    pub fn read(_: i64, _: []u8) !usize { return error.NotSupported; }
    pub fn write(_: i64, _: []const u8) !usize { return error.NotSupported; }
    pub fn close(_: i64) void {}
};

pub fn setNonBlocking(_: i32) !void { return error.Unsupported; }

// ─── shell parser ──────────────────────────────────────────────
pub const shell_parser_types = sp;
pub const ShellParser = sp.ShellParser;

pub const MultiParser = union(sp.Language) {
    heaven: void,
    pie: void,
    c: void,
    zig: void,
    turtle: void,

    pub fn init(_: std.mem.Allocator, lang: sp.Language) sp.ParseError!MultiParser {
        return switch (lang) {
            .heaven => .{ .heaven = {} },
            .pie => .{ .pie = {} },
            .c => .{ .c = {} },
            .zig => .{ .zig = {} },
            .turtle => .{ .turtle = {} },
        };
    }
    pub fn parse(_: *MultiParser, _: []const u8) sp.ParseError!sp.Matrix {
        return error.NotSupported;
    }
    pub fn reset(_: *MultiParser) void {}
    pub fn deinit(_: *MultiParser) void {}
};

// ─── profiler ──────────────────────────────────────────────────
pub const profiler = struct {
    pub const ResourceUsage = struct {
        utime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        stime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        maxrss: u64 = 0,
    };
    pub fn getResourceUsage() ResourceUsage { return .{}; }
};

pub fn readEnergyUJ() !u64 { return error.Unsupported; }

// ─── process / thread / misc ───────────────────────────────────
pub const ProcessResult = struct { exit_code: u8 };
pub fn spawnProcess(_: std.mem.Allocator, _: []const []const u8) !ProcessResult {
    return error.Unsupported;
}
pub const process = struct {
    pub const ProcessResult = @This().ProcessResult;
    pub const spawnProcess = @This().spawnProcess;
};
pub const Thread = std.Thread;
pub const MessageQueue = @import("queue").MessageQueue;
pub const rtc = struct {
    pub const WebRTC = struct {
        pub fn init() !void {}
        pub fn tick() void {}
        pub fn send(_: []const u8, _: []const u8) !void {}
        pub fn getLocalSdp() []const u8 { return ""; }
        pub fn setRemoteSdp(_: []const u8) void {}
    };
};

pub fn readLine(a: std.mem.Allocator) ![]u8 { return io.readLine(a); }
pub fn initConsole() void {}

pub fn streamRead(stream: anytype, buffer: []u8) !usize {
    return stream.read(buffer);
}

// 2026-10-27 (E4 Windows) : WASI has isatty.
pub fn isatty() bool {
    return std.posix.isatty(std.posix.STDIN_FILENO);
}
