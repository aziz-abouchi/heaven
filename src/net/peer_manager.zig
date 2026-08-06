const std = @import("std");
const datachannel = @cImport({
    @cInclude("datachannel.h");
});

pub const Peer = struct {
    id: [16]u8, // UID v7 du pair
    connection: *datachannel.rtcDataChannel,
    status: enum { idle, connecting, ready, error },
};

pub const PeerManager = struct {
    peers: std.ArrayList(Peer),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PeerManager {
        return .{
            .peers = std.ArrayList(Peer).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn broadcast(self: *PeerManager, message: []const u8) void {
        for (self.peers.items) |peer| {
            if (peer.status == .ready) {
                // Envoi des données via le DataChannel
                _ = datachannel.rtcSendData(peer.connection, message.ptr, message.len);
            }
        }
    }
};
