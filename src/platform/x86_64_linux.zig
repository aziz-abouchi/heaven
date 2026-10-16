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

// --- NETWORK & SOCKETS ---

pub fn setNonBlocking(socket: std.posix.socket_t) !void {
    if (target.is_windows) {
        var mode: c_ulong = 1;
        _ = std.os.windows.ws2_32.ioctlsocket(socket, std.os.windows.ws2_32.FIONBIO, &mode);
    } else {
        const fd = socket;
        const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        // Sur macOS, O.NONBLOCK est dans un packed struct ; on utilise la constante POSIX
        const O_NONBLOCK = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos => @as(u32, 0x0004),
            .linux => @as(u32, 0o4000),
            else => @as(u32, 0x0004),
        };
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | O_NONBLOCK);
    }
}


pub const profiler = switch (builtin.os.tag) {
    .linux => @import("profiler_linux.zig"),
    .macos, .ios, .tvos, .watchos => @import("profiler_darwin.zig"),
    .windows => @import("profiler_windows.zig"),
    else => struct {
        pub const ResourceUsage = struct {
            user_time_ns: u64 = 0,
            system_time_ns: u64 = 0,
            max_rss_bytes: usize = 0,
        };
        pub fn getResourceUsage() ResourceUsage {
            return .{};
        }
    },
};

// Alias to standard library for full feature support
pub const posix = std.posix;
pub const os = std.os;

/// Reseau : interface uniforme cross-platform.
/// En natif, wrappe std.net + std.posix. En wasm, stubs qui
/// retournent error.NotSupported. Toute dependance std.net /
/// std.posix.sockaddr est confinee ici.
pub const net = struct {
    // HEAVEN:LISTEN_RAW — syscalls Linux (D-SH4)
    // bind(49), listen(50), accept(43), read(0), write(1), close(3),
    // setsockopt(54) pour SO_REUSEADDR.

    /// bind + listen sur 127.0.0.1:port. Retourne fd (>=0) ou -1.
    pub fn listenTcp(port: u16) !i64 {
        const fd_i = socketTcp();
        if (fd_i < 0) return error.InvalidInput;
        const fd: usize = @intCast(fd_i);

        // SO_REUSEADDR (level=1, optname=2, val=1)
        var on: c_int = 1;
        _ = std.os.linux.syscall5(.setsockopt, fd, 1, 2, @intFromPtr(&on), @sizeOf(c_int));

        // sockaddr_in 127.0.0.1:port
        var sa: [16]u8 = [_]u8{0} ** 16;
        sa[0] = 2; sa[1] = 0;
        sa[2] = @intCast((port >> 8) & 0xFF);
        sa[3] = @intCast(port & 0xFF);
        sa[4] = 127; sa[5] = 0; sa[6] = 0; sa[7] = 1;

        const br = std.os.linux.syscall3(.bind, fd, @intFromPtr(&sa), 16);
        if (@as(isize, @bitCast(br)) < 0) {
            _ = std.os.linux.syscall1(.close, fd);
            return error.InvalidInput;
        }
        // backlog = 128
        const lr = std.os.linux.syscall2(.listen, fd, 128);
        if (@as(isize, @bitCast(lr)) < 0) {
            _ = std.os.linux.syscall1(.close, fd);
            return error.InvalidInput;
        }
        return fd_i;
    }

    /// accept(fd, NULL, NULL). Retourne fd client (>=0) ou -1.
    pub fn accept(fd: i64) !i64 {
        const ufd: usize = @intCast(fd);
        const r = std.os.linux.syscall3(.accept, ufd, 0, 0);
        const signed: isize = @bitCast(r);
        if (signed < 0) return error.InvalidInput;
        return @intCast(signed);
    }

    pub fn read(fd: i64, buf: []u8) !usize {
        const ufd: usize = @intCast(fd);
        const r = std.os.linux.syscall3(.read, ufd, @intFromPtr(buf.ptr), buf.len);
        const signed: isize = @bitCast(r);
        if (signed < 0) return error.InvalidInput;
        return @intCast(signed);
    }

    pub fn write(fd: i64, data: []const u8) !usize {
        const ufd: usize = @intCast(fd);
        const r = std.os.linux.syscall3(.write, ufd, @intFromPtr(data.ptr), data.len);
        const signed: isize = @bitCast(r);
        if (signed < 0) return error.InvalidInput;
        return @intCast(signed);
    }

    pub fn close(fd: i64) void {
        const ufd: usize = @intCast(fd);
        _ = std.os.linux.syscall1(.close, ufd);
    }

    // HEAVEN:NET_CONNECT_RAW — syscalls Linux directs (D-SH4)
    // Pas de std.posix : ABI Linux x86_64.
    // socket(41), connect(42), close(3).
    // Autorise : std.mem / std.fmt (computation pure).
    // Interdit : std.posix.*, std.net.*, std.fs.* (wrappers portables).

    /// Parse "1.2.3.4" en 4 bytes (pure computation).
    fn parseIpv4(s: []const u8) ?[4]u8 {
        var bytes: [4]u8 = undefined;
        var it = std.mem.splitScalar(u8, s, '.');
        var idx: usize = 0;
        while (it.next()) |p| {
            if (idx >= 4) return null;
            bytes[idx] = std.fmt.parseInt(u8, p, 10) catch return null;
            idx += 1;
        }
        if (idx != 4) return null;
        return bytes;
    }

    /// socket(AF_INET, SOCK_STREAM, 0). Retourne fd (>=0) ou -1.
    pub fn socketTcp() i64 {
        const result = std.os.linux.syscall3(.socket, 2, 1, 0);
        const signed: isize = @bitCast(result);
        if (signed < 0) return -1;
        return @intCast(signed);
    }

    // HEAVEN:UDP_RAW — syscalls UDP (D-SH4)
    // socket(AF_INET, SOCK_DGRAM), sendto, recvfrom.

    /// socket(AF_INET, SOCK_DGRAM, 0). Retourne fd (>=0) ou -1.
    pub fn socketUdp() i64 {
        const result = std.os.linux.syscall3(.socket, 2, 2, 0);
        const signed: isize = @bitCast(result);
        if (signed < 0) return -1;
        return @intCast(signed);
    }

    /// Envoie un datagramme vers ip:port. Retourne nb bytes envoyes
    /// (>=0) ou -1.
    pub fn sendtoUdp(fd: i64, ip: []const u8, port: u16, data: []const u8) i64 {
        const bytes = parseIpv4(ip) orelse return -1;
        const ufd: usize = @intCast(fd);

        var sa: [16]u8 = [_]u8{0} ** 16;
        sa[0] = 2; sa[1] = 0;
        sa[2] = @intCast((port >> 8) & 0xFF);
        sa[3] = @intCast(port & 0xFF);
        sa[4] = bytes[0]; sa[5] = bytes[1]; sa[6] = bytes[2]; sa[7] = bytes[3];

        const r = std.os.linux.syscall6(.sendto, ufd,
            @intFromPtr(data.ptr), data.len, 0,
            @intFromPtr(&sa), 16);
        const signed: isize = @bitCast(r);
        if (signed < 0) return -1;
        return @intCast(signed);
    }

    /// Ajoute un timeout de reception a une socket (SO_RCVTIMEO).
    /// timeout_ns en nanosecondes.
    pub fn setRecvTimeout(fd: i64, timeout_ns: u64) void {
        // struct timeval x86_64 : tv_sec (8) + tv_usec (8) = 16 bytes
        const sec: u64 = timeout_ns / 1_000_000_000;
        const usec: u64 = (timeout_ns % 1_000_000_000) / 1000;
        var tv: [16]u8 = [_]u8{0} ** 16;
        @memcpy(tv[0..8], &@as([8]u8, @bitCast(sec)));
        @memcpy(tv[8..16], &@as([8]u8, @bitCast(usec)));
        const ufd: usize = @intCast(fd);
        // level=SOL_SOCKET (1), optname=SO_RCVTIMEO (20)
        _ = std.os.linux.syscall5(.setsockopt, ufd, 1, 20,
            @intFromPtr(&tv), 16);
    }

    /// Recoit un datagramme. Retourne nb bytes recus (>=0) ou -1.
    /// Bloque jusqu'a reception (fd non-bloquant non gere en V0).
    pub fn recvfromUdp(fd: i64, buf: []u8) i64 {
        const ufd: usize = @intCast(fd);
        const r = std.os.linux.syscall6(.recvfrom, ufd,
            @intFromPtr(buf.ptr), buf.len, 0, 0, 0);
        const signed: isize = @bitCast(r);
        if (signed < 0) return -1;
        return @intCast(signed);
    }

    /// connect(fd, sockaddr_in, 16). Retourne fd (>=0) ou -1.
    pub fn connectTcp(ip: []const u8, port: u16) !i64 {
        const bytes = parseIpv4(ip) orelse return error.InvalidInput;

        // sockaddr_in (16 bytes) :
        //   [0..2] family = AF_INET (2) little-endian
        //   [2..4] port  big-endian
        //   [4..8] addr  network order
        //   [8..16] zero
        var sa: [16]u8 = [_]u8{0} ** 16;
        sa[0] = 2;
        sa[1] = 0;
        sa[2] = @intCast((port >> 8) & 0xFF);
        sa[3] = @intCast(port & 0xFF);
        sa[4] = bytes[0];
        sa[5] = bytes[1];
        sa[6] = bytes[2];
        sa[7] = bytes[3];

        const fd_i = socketTcp();
        if (fd_i < 0) return error.InvalidInput;
        const fd: usize = @intCast(fd_i);

        const r = std.os.linux.syscall3(.connect, fd, @intFromPtr(&sa), 16);
        const signed: isize = @bitCast(r);
        if (signed < 0) {
            _ = std.os.linux.syscall1(.close, fd);
            return error.ConnectFailed;
        }
        return fd_i;
    }
};

// Importation centralisée des headers C
pub const parser_ts = @import("parser_ts.zig");
pub const ts = parser_ts.ts;
pub const tree_sitter_heaven = parser_ts.tree_sitter_heaven;
pub const tree_sitter_pie = parser_ts.tree_sitter_pie;
pub const tree_sitter_c = parser_ts.tree_sitter_c;
pub const tree_sitter_zig = parser_ts.tree_sitter_zig;

// ═══════════════════════════════════════════════════════════
// THREAD ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const Thread = std.Thread;

// ═══════════════════════════════════════════════════════════
// FILESYSTEM ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const fs = std.fs;

/// Wrapper uniforme cross-platform pour lire un fichier depuis
/// le cwd. En natif, delegue a std.fs.cwd().readFileAlloc.
pub fn readFileAllocCwd(alloc: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, max);
}

// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
// DEBUG ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const debug = std.debug;

// ═══════════════════════════════════════════════════════════
// NETWORK ABSTRACTION (WebSocket + WebRTC)
// ═══════════════════════════════════════════════════════════



pub fn allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}


// ═══════════════════════════════════════════════════════════
// SHELL PARSER (Tree-sitter natif)
// ═══════════════════════════════════════════════════════════

pub const shell_parser_types = parser_ts.shell_parser_types;
pub const ShellParser = parser_ts.ShellParser;
pub const MultiParser = parser_ts.MultiParser;

// ═══════════════════════════════════════════════════════════
// STREAM I/O ABSTRACTION
// ═══════════════════════════════════════════════════════════

/// Lecture d'un stream réseau (wrapper simple pour cohérence multi-plateforme).
pub fn streamRead(stream: std.net.Stream, buffer: []u8) std.net.Stream.ReadError!usize {
    return stream.read(buffer);
}

// Exposer la lecture d'énergie
pub fn readEnergyUJ() !u64 {
    // Chemin typique pour l'énergie du CPU (Intel RAPL)
    const path = "/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj";
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var buf: [32]u8 = undefined;
    const len = try file.read(&buf);
    return std.fmt.parseInt(u64, std.mem.trim(u8, buf[0..len], "\n"), 10);
}
