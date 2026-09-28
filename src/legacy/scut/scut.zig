const std = @import("std");
const network = @import("network.zig");
const protocol = @import("protocol");
const dispatch = @import("../core/dispatch.zig");

pub const initNetwork = network.init;
pub const sendToPeer = network.sendTo;
pub const listenForPeers = network.listen;
pub const broadcastExistence = network.broadcast;
pub const sendRPC = network.sendRPC;
pub const listPeers = network.listPeers;

pub const sendTaskToPeer = network.sendTaskToAll;

fn handleMessage(allocator: std.mem.Allocator, header: protocol.Header, payload: []const u8) void {
    switch (header.kind) {
        .MatrixSync => {
            const node = allocator.create(dispatch.CommandNode) catch return;
            node.* = .{
                .data = .{ .MatrixSync = payload },
            };
            dispatch.command_queue.put(node);
        },
        else => {},
    }
}
