// src/scut/network_windows.zig — stub Windows du swarm P2P.
// Le vrai swarm (src/scut/network.zig) est POSIX-only : sockets UDP,
// sendto/recvfrom, sockaddr_in6. Sur Windows il n'est pas analyse
// (aucun import). Ce stub expose la meme API publique.
//
// Phase 6 : vrai swarm Windows via std.net.Address UDP (cross-platform).
// 2026-10-27 (E4 Windows).

const std = @import("std");

pub const Peer = struct {
    address: std.net.Address,
    last_seen: i64,
    last_sync: i64,
    view_version: u64,
    port: u16,
};

pub const IncomingWithAddr = struct {
    // 2026-10-27 (E4 Windows) : data est protocol.Incoming (union),
    // pas []const u8. bob_loop.zig switch sur .RawCode/.MatrixSync/etc.
    data: @import("protocol").Incoming,
    sender: std.net.Address,
    len: usize,
};

pub var self_origin: u64 = 0;
pub var known_peers: std.ArrayListUnmanaged(Peer) = .{};
pub var current_port: u16 = 0;

pub fn init(_: u16) !void {
    return error.Unsupported;
}
pub fn deinit() void {}
pub fn listen(_: std.mem.Allocator) !?IncomingWithAddr {
    return null;
}
pub fn sendHello() void {}
pub fn broadcast(_: anytype, _: anytype) !void {
    return error.NotSupported;
}
pub fn broadcastPresence() !void {
    return error.NotSupported;
}
pub fn sendTo(_: std.net.Address, _: []const u8) !void {
    return error.NotSupported;
}
pub fn handleIncoming(_: anytype, _: anytype, _: anytype, _: anytype, _: anytype) !void {
    return error.NotSupported;
}
pub fn merge(_: anytype) void {}
