const std = @import("std");
const builtin = @import("builtin");

pub const PeerConnection = struct {
    const Self = @typeInfo(@This()).@"struct";

    // Implémentation WASM / Web
    pub const WasmImpl = struct {
        extern "env" fn js_create_peer_connection() i32;
        handle: i32,

        pub fn init() WasmImpl {
            return .{ .handle = js_create_peer_connection() };
        }
    };

    // Implémentation OS (libdatachannel)
    pub const NativeImpl = struct {
        const c = @cImport({
            @cInclude("rtc/rtc.h");
        });
        handle: c_int,

        pub fn init() NativeImpl {
            return .{ .handle = c.rtcCreatePeerConnection(null) };
        }
    };

    // Sélection automatique à la compilation
    impl: if (builtin.target.isWasm()) WasmImpl else NativeImpl,

    pub fn create() PeerConnection {
        return .{
            .impl = if (builtin.target.isWasm()) 
                WasmImpl.init() 
            else 
                NativeImpl.init(),
        };
    }
};