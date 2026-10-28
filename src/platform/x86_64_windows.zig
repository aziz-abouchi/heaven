// src/platform/x86_64_windows.zig — Windows x86_64 platform layer.
// 2026-10-27 (E4 Windows) : réécrit sur le modèle de
// x86_64_linux.zig. La majorité des exports pointent vers les
// modules PARTAGÉS (target, io_console, process, time,
// net_sockets, parser_ts) qui testent déjà `target.is_windows`.
// Les vrais POSIX-only sont stubés explicitement.

// HEAVEN:windows full shim
const std = @import("std");

// ─── Modules partagés (cross-platform) ───
pub const target = @import("target.zig");
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
// 2026-10-27 (E4 Windows) : net_sockets.zig utilise std.os.linux.syscall
// (POSIX-only). Sur Windows, on ne l'importe PAS — on définit net et
// setNonBlocking en local, avec les mêmes signatures publiques.
// Le serveur HTTP (platform.net.listenTcp) utilise std.net.Address
// qui est cross-platform — ça marche sans net_sockets.zig.
// 2026-10-28 : vraie implémentation cross-platform via std.posix
// + std.net.Stream. Windows supporte socket/bind/listen/accept/close/
// connect (WSAStartup auto dans std.posix.socket), et les E/S passent
// par std.net.Stream (recv/send natifs).
pub const net_sockets = @import("net_sockets.zig");
pub const net = net_sockets.net;
// setNonBlocking : voir net_sockets.zig

pub const parser_ts = @import("parser_ts.zig");
pub const ts = parser_ts.ts;
pub const tree_sitter_heaven = parser_ts.tree_sitter_heaven;
pub const tree_sitter_pie = parser_ts.tree_sitter_pie;
pub const tree_sitter_c = parser_ts.tree_sitter_c;
pub const tree_sitter_zig = parser_ts.tree_sitter_zig;

pub const shell_parser_types = parser_ts.shell_parser_types;
pub const ShellParser = parser_ts.ShellParser;
pub const MultiParser = parser_ts.MultiParser;

// ─── Std passthrough ───
pub const Thread = std.Thread;
pub const fs = std.fs;
pub const debug = std.debug;
// 2026-10-27 (E4 Windows) : PAS de std.posix exposé (interdit
// sur Windows). Utiliser std.fs.File pour les opérations fd.
pub const posix = struct {
    // 2026-10-27 (E4 Windows) : stubs exhaustifs pour la compilation.
    // Tout appel réseau renvoie error.Unsupported : le swarm P2P
    // (scut/network.zig) n'est pas disponible sur Windows. Le REPL
    // et le serveur HTTP utilisent platform.net (net_sockets.zig),
    // pas ces stubs — ils fonctionnent normalement.
    pub const socket_t = usize;
    pub const socklen_t = u32;
    pub const AF = struct {
        pub const UNSPEC: u16 = 0;
        pub const INET: u16 = 2;
        pub const INET6: u16 = 10;
    };
    pub const SOCK = struct {
        pub const STREAM: u16 = 1;
        pub const DGRAM: u16 = 2;
        pub const RAW: u16 = 3;
    };
    pub fn socket(_: anytype, _: anytype, _: anytype) !socket_t {
        return error.Unsupported;
    }
    pub fn bind(_: socket_t, _: anytype, _: anytype) !void {
        return error.Unsupported;
    }
    pub fn sendto(_: socket_t, _: []const u8, _: anytype, _: anytype, _: anytype) !usize {
        return error.Unsupported;
    }
    pub fn recvfrom(_: socket_t, _: []u8, _: anytype, _: anytype, _: anytype) !usize {
        return error.Unsupported;
    }
    pub fn setsockopt(_: socket_t, _: anytype, _: anytype, _: anytype, _: anytype) !void {
        return error.Unsupported;
    }
    pub fn getsockopt(_: socket_t, _: anytype, _: anytype, _: anytype, _: anytype) !void {
        return error.Unsupported;
    }
    pub fn close(_: socket_t) void {}
};
pub const os = std.os;

// ─── Allocator ───
pub fn allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

// ─── File IO cross-platform ───
pub fn readFileAllocCwd(alloc: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size > max) return error.FileTooBig;
    return try file.readToEndAlloc(alloc, stat.size);
}

// ─── getEnv (variante qui alloue) ───
pub fn getEnv(alloc: std.mem.Allocator, key: []const u8) !?[]u8 {
    return std.process.getEnvVarOwned(alloc, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
}

// ─── args sans argv[0] ───
pub fn args(alloc: std.mem.Allocator) ![][]const u8 {
    return std.process.argsAlloc(alloc)[1..];
}

// ─── stream read ───
pub fn streamRead(stream: std.net.Stream, buffer: []u8) std.net.Stream.ReadError!usize {
    return stream.read(buffer);
}

// ─── webrtc : stub Windows ───
pub const rtc = struct {
    // 2026-10-27 (E4 Windows) : WebRTC stub (pas de libdatachannel).
    // Signature alignée sur webrtc.zig:17 (init() !void, pas d'alloc).
    pub const WebRTC = struct {
        pub fn init() !void {
            // Pas de libdatachannel sur Windows -> on no-op silencieusement.
            // Les appels ultérieurs à createOffer/etc. échoueront.
            return;
        }
        pub fn deinit() void {}
        pub fn createOffer() ![]u8 {
            return error.Unsupported;
        }
        pub fn createAnswer() ![]u8 {
            return error.Unsupported;
        }
        pub fn setRemoteDescription(_: []const u8) !void {
            return error.Unsupported;
        }
        pub fn send(_: []const u8) !void {
            return error.Unsupported;
        }
    };
    pub fn init(_: std.mem.Allocator) !void {
        return error.Unsupported;
    }
    pub fn deinit() void {}
};

// ─── Profiler : stub Windows ───
pub const profiler = struct {
    // 2026-10-27 (E4 Windows) : ResourceUsage aligné sur
    // std.posix.rusage Linux (utime/stime/maxrss). Tous les
    // champs requis par profiler.zig:52 et wasm_cmd.zig:205.
    pub const ResourceUsage = struct {
        utime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        stime: struct { sec: i64 = 0, usec: i64 = 0 } = .{},
        maxrss: u64 = 0,
    };
    pub fn getResourceUsage() ResourceUsage { return .{}; }
    pub fn getChildrenUsage() ResourceUsage { return .{}; }
    pub fn readEnergyUj() ?u64 { return null; }
    pub fn readTempMc(_: u8) ?i64 { return null; }
    pub fn init(_: std.mem.Allocator) !void {}
    pub fn deinit() void {}
    pub fn snapshot(_: std.mem.Allocator) ![]u8 {
        return error.Unsupported;
    }
};

// ─── RAPL energy : Linux-only ───
pub fn readEnergyUJ() !u64 {
    return 0;
}

// 2026-10-27 (E4 Windows) : stdin TTY detection via std.fs cross-platform.
pub fn isatty() bool {
    return std.fs.File.stdin().isTty();
}

// 2026-10-27 (E4 Windows) : SIGALRM indisponible, no-op.
// Le preempt_flag reste false -> pas de preemption timer.
pub fn armPreemptTimer(_: *const fn (i32) callconv(.c) void) void {}

// 2026-10-28 : rawSyscall portable (Linux-only, -1 ailleurs).
pub const intrinsics = @import("intrinsics.zig");
