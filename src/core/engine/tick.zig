const std = @import("std");
const MessageQueue = @import("../network/queue.zig").MessageQueue;
const EGraph = @import("../inference/eqsat/egraph.zig").EGraph;

pub const Engine = struct {
    egraph: EGraph,
    queue: *MessageQueue,
    tick_count: u64,
    allocator: std.mem.Allocator,

    const TICK_BUDGET_MS: u64 = 16;
    const MAX_MESSAGES_PER_TICK: usize = 10;

    pub fn tick(self: *Engine) !void {
        const start_time = std.time.milliTimestamp();

        // PHASE 1 : Traitement des messages entrants
        var messages_processed: usize = 0;
        while (messages_processed < MAX_MESSAGES_PER_TICK) {
            if (self.queue.pop()) |msg| {
                try self.handleMessage(msg);
                messages_processed += 1;
            } else {
                break;
            }
        }

        // PHASE 2 : Travail local sur l'E-Graph
        const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        const remaining_budget = if (elapsed < TICK_BUDGET_MS)
            TICK_BUDGET_MS - elapsed
        else
            0;

        if (remaining_budget > 0) {
            try self.egraph.saturate(remaining_budget);
        }

        // PHASE 3 : Envoi des résultats
        try self.flushOutgoingMessages();

        self.tick_count += 1;
    }

    fn handleMessage(self: *Engine, msg: MessageQueue.Message) !void {
        switch (msg.msg_type) {
            .handshake => try self.handleHandshake(msg),
            .egraph_sync => try self.handleEGraphSync(msg),
            .proof_request => try self.handleProofRequest(msg),
            .work_steal_request => try self.handleWorkSteal(msg),
            else => {},
        }
    }

    fn handleHandshake(self: *Engine, msg: MessageQueue.Message) !void {
        _ = self;
        const handshake = try std.mem.bytesToValue(Handshake, msg.payload);
        platform.debug.print("Handshake from peer: protocol v{}, caps: {}\n", .{
            handshake.protocol_version,
            handshake.capabilities,
        });
    }

    fn handleEGraphSync(self: *Engine, msg: MessageQueue.Message) !void {
        const nodes = try deserializeENodes(self.allocator, msg.payload);
        defer self.allocator.free(nodes);

        for (nodes) |node| {
            _ = try self.egraph.addExpr(node);
        }
    }

    fn handleWorkSteal(self: *Engine, msg: MessageQueue.Message) !void {
        const subgraph = try self.egraph.extractWorkUnit();
        if (subgraph) |work| {
            try self.sendToPeer(msg.peer_id, .work_steal_response, work);
        }
    }

    fn flushOutgoingMessages(self: *Engine) !void {
        _ = self;
    }

    fn sendToPeer(self: *Engine, peer_id: [16]u8, msg_type: MessageQueue.MessageType, payload: []const u8) !void {
        _ = self;
        _ = peer_id;
        _ = msg_type;
        _ = payload;
    }
};

const Handshake = extern struct {
    node_id: [16]u8,
    protocol_version: u32,
    capabilities: u32,
};
