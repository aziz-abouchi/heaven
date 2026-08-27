const std = @import("std");
const queue_mod = @import("queue");
pub const MessageQueue = queue_mod.MessageQueue;
pub const rtc = @import("webrtc.zig");
const c = @cImport({
    // Assurez-vous que le nom du fichier header est correct
    // pour votre installation de libdatachannel
    @cInclude("rtc/datachannel.hpp");
});
const Driver = @import("driver");
const NetworkDriver = Driver.NetworkDriver;

pub var debug_enabled: bool = false;

/// Debug conditionnel : activé par HEAVEN_DEBUG=1
pub fn dbg(comptime fmt: []const u8, args: anytype) void {
    if (debug_enabled) debug.print(fmt, args);
}

// Alias to standard library for full feature support
pub const posix = std.posix;
pub const os = std.os;

// Importation centralisée des headers C
pub const ts = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub const libtcc = @cImport({
    @cInclude("libtcc.h");
});

// Déclarations des parsers (on unifie le typage ici)
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
        const stdin = std.io.getStdIn().reader();
        return stdin.readUntilDelimiterAlloc(alloc, '\n', 4096);
    }
};

pub fn readLine(alloc: std.mem.Allocator) ![]u8 {
    var buf: [4096]u8 = undefined;
    const n = try std.posix.read(0, &buf);
    if (n == 0) return error.EndOfStream;
    const line = buf[0..n];
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
        // Si c'est un ID WebRTC, on utilise notre nouvelle implémentation
        if (std.mem.startsWith(u8, peer_id, "rtc:")) {
            try rtc.WebRTC.init(); // On s'assure qu'il est initialisé
            // Logique de connexion WebRTC ici...
            return;
        }

        // Sinon, on garde votre logique TCP existante
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
        // Validation basique avant d'envoyer dans la MessageQueue
        if (data.len == 0) return error.EmptyPayload;

        // Push dans la file globale que vous avez définie
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
