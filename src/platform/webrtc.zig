// src/platform/webrtc.zig
// Pont WebRTC — déclarations externes directes (pattern tcc.zig).
// Les symboles sont fournis soit par webrtc_impl.cpp (-Dnetwork=true),
// soit par webrtc_stub.c (-Dnetwork=false).

const std = @import("std");

const RTCMessageCallback = *const fn ([*c]const u8, [*c]const u8, usize) callconv(.c) void;

extern fn rtc_init(on_message: RTCMessageCallback) c_int;
extern fn rtc_send(remote_peer_id: [*c]const u8, data: [*c]const u8, len: usize) c_int;
extern fn rtc_poll() void;
extern fn rtc_get_local_sdp() [*c]const u8;
extern fn rtc_set_remote_sdp(sdp: [*c]const u8) void;

pub const WebRTC = struct {
    pub fn init() !void {
        if (rtc_init(onMessageCallback) != 0) {
            return error.WebRTCInitFailed;
        }
    }

    pub fn tick() void {
        rtc_poll();
    }

    pub fn send(peer_id: []const u8, data: []const u8) !void {
        if (rtc_send(peer_id.ptr, data.ptr, data.len) != 0) {
            return error.SendFailed;
        }
    }

    pub fn getLocalSdp() []const u8 {
        const sdp = rtc_get_local_sdp();
        return if (sdp) |s| std.mem.span(s) else "";
    }

    pub fn setRemoteSdp(sdp: []const u8) void {
        rtc_set_remote_sdp(sdp.ptr);
    }
};

// Callback appelé par le C lorsque des données arrivent
export fn onMessageCallback(peer_id_ptr: [*c]const u8, msg_ptr: [*c]const u8, len: usize) void {
    const peer_id = std.mem.span(peer_id_ptr);
    const data = msg_ptr[0..len];
    
    std.debug.print("Message reçu de {s}: {s}\n", .{ peer_id, data });

    // TODO: router vers handlers (comportement original inchangé —
    // recopie le corps existant de ton onMessageCallback si différent)
}