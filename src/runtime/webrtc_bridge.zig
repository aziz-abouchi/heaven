const std = @import("std");
const platform = @import("platform");
const network_queue = @import("queue");

// Variables globales pour stocker les références nécessaires au pont
pub var global_queue: *network_queue.MessageQueue = undefined;
pub var global_allocator: std.mem.Allocator = undefined;

// Cette fonction est exportée et sera appelée par le C++
export fn on_rtc_message(remote_peer_id: [*c]const u8, msg: [*c]const u8, len: usize) void {
    const data_slice = msg[0..len];
    const peer_slice = std.mem.span(remote_peer_id);

    // 1. Duplication pour la queue (sécurité mémoire)
    const payload = global_allocator.dupe(u8, data_slice) catch return;

    // 2. Préparation du PeerID
    var pid: [16]u8 = std.mem.zeroes([16]u8);
    @memcpy(pid[0..@min(pid.len, peer_slice.len)], peer_slice);

    // 3. Injection dans la file
    global_queue.push(.{
        .msg_type = .egraph_sync,
        .peer_id = pid,
        .payload = payload,
        .timestamp = @as(u64, @intCast(std.time.milliTimestamp())),
    }) catch |err| {
        platform.dbg("[RTC] Erreur injection queue: {any}\n", .{err});
        global_allocator.free(payload);
    };
}
