const std = @import("std");
pub const target = @import("target.zig");
const builtin = @import("builtin");
const queue_mod = @import("queue");
pub const MessageQueue = queue_mod.MessageQueue;
pub const rtc = @import("webrtc.zig");

pub const io_console = @import("io_console.zig");
pub const dbg = io_console.dbg;
pub const getenv = io_console.getenv;
pub const ConsoleRawMode = io_console.ConsoleRawMode;
pub const enableRawMode = io_console.enableRawMode;
pub const disableRawMode = io_console.disableRawMode;
pub const initConsole = io_console.initConsole;
pub const writeStdout = io_console.writeStdout;
pub const readStdin = io_console.readStdin;
pub const io = io_console.io;
pub const readLine = io_console.readLine;

pub const process = @import("process.zig");
pub const spawnProcess = process.spawnProcess;
pub const ProcessResult = process.ProcessResult;
pub const time = @import("time.zig");
pub const profiler = @import("profiler_darwin.zig");
pub const posix = std.posix;
pub const os = std.os;

pub const net_sockets = @import("net_sockets.zig");
pub const net = net_sockets.net;
pub const setNonBlocking = net_sockets.setNonBlocking;

pub const parser_ts = @import("parser_ts.zig");
pub const ts = parser_ts.ts;
pub const tree_sitter_heaven = parser_ts.tree_sitter_heaven;
pub const tree_sitter_pie = parser_ts.tree_sitter_pie;
pub const tree_sitter_c = parser_ts.tree_sitter_c;
pub const tree_sitter_zig = parser_ts.tree_sitter_zig;

pub const Thread = std.Thread;
pub const fs = std.fs;

pub fn readFileAllocCwd(alloc: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, max);
}

pub const debug = std.debug;

pub fn allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

pub const shell_parser_types = parser_ts.shell_parser_types;
pub const ShellParser = parser_ts.ShellParser;
pub const MultiParser = parser_ts.MultiParser;

pub fn streamRead(stream: std.net.Stream, buffer: []u8) std.net.Stream.ReadError!usize {
    return stream.read(buffer);
}

pub fn readEnergyUJ() !u64 {
    return 0;
}
