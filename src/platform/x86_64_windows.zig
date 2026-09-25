const std = @import("std");
pub const target = @import("target.zig");
const builtin = @import("builtin");
const queue_mod = @import("queue");
pub const MessageQueue = queue_mod.MessageQueue;
pub const rtc = @import("webrtc.zig");
const c = @cImport({
    @cInclude("rtc/datachannel.hpp");
});
const Driver = @import("driver");
const NetworkDriver = Driver.NetworkDriver;

pub var debug_enabled: bool = false;

/// Debug conditionnel : activé par HEAVEN_DEBUG=1
pub fn dbg(comptime fmt: []const u8, args: anytype) void {
    if (debug_enabled) debug.print(fmt, args);
}

pub fn getenv(key: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(std.heap.page_allocator, key) catch null;
}

// --- STDIN / STDOUT / STDERR ---

pub fn writeStdout(buf: []const u8) !usize {
    const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) orelse return error.BadFileDescriptor;
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.BadFileDescriptor;
    var written: u32 = 0;
    const result = std.os.windows.kernel32.WriteFile(handle, buf.ptr, @intCast(buf.len), &written, null);
    if (result == 0) return error.WriteFailed;
    return written;
}

pub fn readStdin(buf: []u8) !usize {
    const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) orelse return error.BadFileDescriptor;
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.BadFileDescriptor;
    var bytes_read: u32 = 0;
    const result = std.os.windows.kernel32.ReadFile(handle, buf.ptr, @intCast(buf.len), &bytes_read, null);
    if (result == 0) return error.ReadFailed;
    return bytes_read;
}

// --- NETWORK & SOCKETS ---

pub fn setNonBlocking(socket: std.posix.socket_t) !void {
    var mode: c_ulong = 1;
    _ = std.os.windows.ws2_32.ioctlsocket(socket, std.os.windows.ws2_32.FIONBIO, &mode);
}

// --- PROCESS CONTROL ---

pub const ProcessResult = struct {
    exit_code: u8,
};

pub fn spawnProcess(alloc: std.mem.Allocator, argv: []const []const u8) !ProcessResult {
    var child = std.process.Child.init(argv, alloc);
    const term = try child.spawnAndWait();

    return switch (term) {
        .Exited => |code| ProcessResult{ .exit_code = @truncate(code) },
        else => ProcessResult{ .exit_code = 1 },
    };
}

pub const profiler = @import("profiler_windows.zig");

// Alias to standard library for full feature support
pub const posix = std.posix;
pub const os = std.os;

// Importation centralisée des headers C
pub const ts = @cImport({
    @cInclude("tree_sitter/api.h");
});

// Déclarations des parsers
pub extern fn tree_sitter_heaven() *ts.TSLanguage;
pub extern fn tree_sitter_pie() *ts.TSLanguage;
pub extern fn tree_sitter_c() *ts.TSLanguage;
pub extern fn tree_sitter_zig() *ts.TSLanguage;

// ═══════════════════════════════════════════════════════════
// THREAD ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const Thread = std.Thread;

// ═══════════════════════════════════════════════════════════
// FILESYSTEM ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const fs = std.fs;

// ═══════════════════════════════════════════════════════════
// I/O ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const io = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        std.debug.print(fmt, args);
    }

    pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
        const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) orelse return error.BadFileDescriptor;
        if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.BadFileDescriptor;
        const file = std.fs.File{ .handle = handle };
        return file.reader().readUntilDelimiterAlloc(alloc, '\n', 4096);
    }
};

pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
    var buf: [4096]u8 = undefined;
    const handle = std.os.windows.kernel32.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) orelse return error.BadFileDescriptor;
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.BadFileDescriptor;
    
    var bytes_read: u32 = 0;
    const result = std.os.windows.kernel32.ReadFile(handle, &buf, @intCast(buf.len), &bytes_read, null);
    if (result == 0) return error.ReadFailed;
    
    if (bytes_read == 0) return error.EndOfStream;
    const line = buf[0..bytes_read];
    // Supprimer le '\n' final
    const line_clean = if (line.len > 0 and line[line.len - 1] == '\n')
        line[0 .. line.len - 1]
    else
        line;
    return try alloc.dupe(u8, line_clean);
}

// ═══════════════════════════════════════════════════════════
// DEBUG ABSTRACTION
// ═══════════════════════════════════════════════════════════

pub const debug = std.debug;

// ═══════════════════════════════════════════════════════════
// NETWORK ABSTRACTION (WebSocket + WebRTC)
// ═══════════════════════════════════════════════════════════

pub const Network = struct {
    ws_client: ?std.net.Stream = null,
    peer_connections: std.StringHashMap(PeerConnection),
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Network {
        return Network{
            .ws_client = null,
            .peer_connections = std.StringHashMap(PeerConnection).init(alloc),
            .allocator = alloc,
        };
    }

    // WebSocket (signaling)
    pub fn connectToSignaling(self: *Network, url: []const u8) !void {
        const uri = try std.Uri.parse(url);
        self.ws_client = try std.net.tcpConnectToHost(
            self.allocator,
            uri.host.?,
            uri.port orelse 80,
        );
    }

    pub fn announceNode(self: *Network, capabilities: []const u8) !void {
        if (self.ws_client) |ws| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "{{\"type\":\"announce\",\"capabilities\":\"{s}\"}}",
                .{capabilities},
            );
            defer self.allocator.free(msg);
            _ = try ws.write(msg);
        }
    }

    pub fn discoverPeers(self: *Network) ![][]const u8 {
        _ = self;
        return &[_][]const u8{ "peer1", "peer2" };
    }

    // WebRTC (data plane)
    pub fn connectToPeer(self: *Network, peer_id: []const u8) !void {
        if (std.mem.startsWith(u8, peer_id, "rtc:")) {
            try rtc.WebRTC.init();
            return;
        }

        const conn = try std.net.tcpConnectToHost(self.allocator, peer_id, 9000);
        try self.peer_connections.put(peer_id, .{ .stream = conn });
    }

    pub fn sendToPeer(self: *Network, peer_id: []const u8, data: []const u8) !void {
        if (self.peer_connections.get(peer_id)) |peer| {
            _ = try peer.stream.write(data);
        }
    }

    pub fn receiveFromPeer(self: *Network, peer_id: []const u8) ![]const u8 {
        if (self.peer_connections.get(peer_id)) |peer| {
            var buf: [4096]u8 = undefined;
            const n = try peer.stream.read(&buf);
            return buf[0..n];
        }
        return error.PeerNotFound;
    }
    pub fn onPeerMessage(self: *Network, peer_id: []const u8, data: []const u8) !void {
        if (data.len == 0) return error.EmptyPayload;

        try self.message_queue.push(.{
            .peer_id = peer_id,
            .msg_type = .egraph_sync,
            .payload = data,
            .timestamp = time.milliTimestamp(),
        });
    }
};

const PeerConnection = struct {
    stream: std.net.Stream,
};

pub const time = struct {
    pub const ns_per_s = std.time.ns_per_s;
    pub const ns_per_us = std.time.ns_per_us;

    pub fn milliTimestamp() i64 {
        return std.time.milliTimestamp();
    }

    pub fn nanoTimestamp() i128 {
        return std.time.nanoTimestamp();
    }

    pub fn sleep(ns: u64) void {
        std.time.sleep(ns);
    }
};

pub fn allocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

// Native implementation
fn native_send(ctx: *anyopaque, data: []const u8) void {
    const channel: *c.DataChannel = @ptrCast(@alignCast(ctx));
    channel.send(data);
}

pub fn createNativeDriver(channel: *c.DataChannel) NetworkDriver {
    return .{
        .send_fn = native_send,
        .ctx = @ptrCast(channel),
    };
}

pub fn init_network() !void {
    try rtc.init();
    std.debug.print("Heaven: WebRTC Layer Ready.\n", .{});
}

// ═══════════════════════════════════════════════════════════
// SHELL PARSER (Tree-sitter natif)
// ═══════════════════════════════════════════════════════════

pub const shell_parser_types = @import("shell_parser_types");

/// Parser par défaut : grammaire Heaven
pub const ShellParser = shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven);

/// Parser multi-langage : union taguée pour supporter plusieurs grammaires
pub const MultiParser = union(shell_parser_types.Language) {
    heaven: shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven),
    pie: shell_parser_types.TreeSitterParser(ts, tree_sitter_pie),
    c: shell_parser_types.TreeSitterParser(ts, tree_sitter_c),
    zig: shell_parser_types.TreeSitterParser(ts, tree_sitter_zig),

    pub fn init(alloc: std.mem.Allocator, lang: shell_parser_types.Language) shell_parser_types.ParseError!MultiParser {
        return switch (lang) {
            .heaven => .{ .heaven = try shell_parser_types.TreeSitterParser(ts, tree_sitter_heaven).init(alloc) },
            .pie => .{ .pie = try shell_parser_types.TreeSitterParser(ts, tree_sitter_pie).init(alloc) },
            .c => .{ .c = try shell_parser_types.TreeSitterParser(ts, tree_sitter_c).init(alloc) },
            .zig => .{ .zig = try shell_parser_types.TreeSitterParser(ts, tree_sitter_zig).init(alloc) },
        };
    }

    pub fn parse(self: *MultiParser, source: []const u8) shell_parser_types.ParseError!shell_parser_types.Matrix {
        return switch (self.*) {
            inline else => |*p| p.parse(source),
        };
    }

    pub fn reset(self: *MultiParser) void {
        switch (self.*) {
            inline else => |*p| p.reset(),
        }
    }

    pub fn deinit(self: *MultiParser) void {
        switch (self.*) {
            inline else => |*p| p.deinit(),
        }
    }
};

// ═══════════════════════════════════════════════════════════
// STREAM I/O ABSTRACTION (gestion d'erreur spécifique Windows)
// ═══════════════════════════════════════════════════════════

/// Lecture d'un stream réseau.
/// Sur Windows, ReadFile peut retourner ERROR_INVALID_PARAMETER (87)
/// quand le client ferme la connexion. On convertit ces erreurs
/// bénignes en fin de connexion (0 octets) pour éviter le spin loop.
pub fn streamRead(stream: std.net.Stream, buffer: []u8) std.net.Stream.ReadError!usize {
    return stream.read(buffer) catch |err| {
        if (err == error.Unexpected or err == error.InputOutput) return @as(usize, 0);
        return err;
    };
}

// Windows n'a pas de capteur d'énergie comme Intel RAPL
pub fn readEnergyUJ() !u64 {
    return error.NotSupported;
}
