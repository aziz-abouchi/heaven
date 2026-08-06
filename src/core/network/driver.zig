const queue_mod = @import("queue");
const MessageQueue = queue_mod.MessageQueue;

pub const NetworkDriver = struct {
    // Les fonctions que le noyau appelle
    send_fn: *const fn (ctx: *anyopaque, data: []const u8) void,

    // Le contexte permet de stocker les données spécifiques à l'implémentation
    // (ex: pointeur vers libdatachannel sur native, ou handle JS sur wasm)
    ctx: *anyopaque,
    queue: *MessageQueue,

    pub fn send(self: NetworkDriver, data: []const u8) void {
        self.send_fn(self.ctx, data);
    }

    pub fn push(self: NetworkDriver, peer_id: []const u8, data: []const u8) !void {
        // Copie des données pour la file
        const payload = try self.queue.allocator.dupe(u8, data);
        try self.queue.push(.{
            .peer_id = peer_id,
            .payload = payload,
            .msg_type = .egraph_sync,
        });
    }
};
