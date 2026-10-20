// src/platform/tls_stub.zig — stub TLS pour wasm/freestanding
// L'API est identique a tls.zig mais retourne error.Unsupported.
// Wire dans build.zig pour target.cpu.arch == .wasm32.

const std = @import("std");

pub const TlsError = error{
    Unsupported,
    InitFailed,
    ConnectFailed,
    ReadFailed,
    WriteFailed,
};

pub const TlsConn = struct {};

pub fn connect(_: i64, _: [*:0]const u8) TlsError!TlsConn {
    return error.Unsupported;
}

pub fn write(_: *TlsConn, _: []const u8) TlsError!usize {
    return error.Unsupported;
}

pub fn read(_: *TlsConn, _: []u8) TlsError!usize {
    return error.Unsupported;
}

pub fn close(_: *TlsConn) void {}

test "stub: connect retourne Unsupported" {
    try std.testing.expectError(error.Unsupported, connect(0, "x"));
}
