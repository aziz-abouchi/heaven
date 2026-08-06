// src/platform/webrtc.zig
const std = @import("std");

// Import du pont C
pub const c = @cImport({
    @cInclude("/home/aabouchi/Desktop/Dev/langage/boot/src/platform/c_rtc.h");
});

pub const WebRTC = struct {
    pub fn init() !void {
        if (c.rtc_init(onMessageCallback) != 0) {
            return error.WebRTCInitFailed;
        }
    }

    pub fn tick() void {
        c.rtc_poll();
    }

    pub fn send(peer_id: []const u8, data: []const u8) !void {
        if (c.rtc_send(peer_id.ptr, data.ptr, data.len) != 0) {
            return error.SendFailed;
        }
    }
};

// Callback appelé par le C lorsque des données arrivent
export fn onMessageCallback(peer_id_ptr: [*c]const u8, msg_ptr: [*c]const u8, len: usize) void {
    const peer_id = std.mem.span(peer_id_ptr);
    const data = msg_ptr[0..len];

    std.debug.print("Message reçu de {s}: {s}\n", .{ peer_id, data });

    // Ici, on transmet au driver_mod
    // driver.handle_message(peer_id, data);
}
