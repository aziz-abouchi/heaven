// src/platform/tls.zig — TLS via OpenSSL FFI (2026-10-20)
// Minimal : extern fns manuelles (pas de @cImport, pas besoin des headers).
// Voir DECISIONS.md D-SH1.

const std = @import("std");

// Opaque pointers OpenSSL
pub const SSL_CTX = opaque {};
pub const SSL = opaque {};

// Methods
extern fn TLS_client_method() *const anyopaque;

// Context
extern fn SSL_CTX_new(method: *const anyopaque) ?*SSL_CTX;
extern fn SSL_CTX_free(ctx: ?*SSL_CTX) void;

// Connection
extern fn SSL_new(ctx: *SSL_CTX) ?*SSL;
extern fn SSL_set_fd(ssl: *SSL, fd: c_int) c_int;
extern fn SSL_connect(ssl: *SSL) c_int;
extern fn SSL_get_error(ssl: *const SSL, ret: c_int) c_int;
extern fn SSL_ctrl(ssl: *SSL, cmd: c_int, larg: c_long, parg: ?*anyopaque) c_long;

// I/O
extern fn SSL_read(ssl: *SSL, buf: [*]u8, num: c_int) c_int;
extern fn SSL_write(ssl: *SSL, buf: [*]const u8, num: c_int) c_int;

// Shutdown
extern fn SSL_shutdown(ssl: *SSL) c_int;
extern fn SSL_free(ssl: *SSL) void;

// SNI : SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, hostname)
pub const SSL_CTRL_SET_TLSEXT_HOSTNAME: c_int = 55;
pub const TLSEXT_NAMETYPE_host_name: c_long = 0;

pub fn setSni(ssl: *SSL, hostname: [*:0]const u8) void {
    _ = SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, @constCast(@ptrCast(hostname)));
}

// Test : TLS_client_method doit etre non-null. Linkage = OK.
test "openssl: TLS_client_method disponible" {
    const m = TLS_client_method();
    try std.testing.expect(@intFromPtr(m) != 0);
}

test "openssl: SSL_CTX_new + free" {
    const m = TLS_client_method();
    const ctx = SSL_CTX_new(m);
    try std.testing.expect(ctx != null);
    SSL_CTX_free(ctx);
}

// ═══ API haut niveau ═══

pub const TlsError = error{
    InitFailed,
    ConnectFailed,
    ReadFailed,
    WriteFailed,
};

pub const TlsConn = struct {
    ssl: *SSL,
    ctx: *SSL_CTX,
};

// Ouvre une connexion TLS sur un fd TCP deja connecte.
// hostname : pour SNI (obligatoire pour les vhosts modernes).
pub fn connect(fd: i64, hostname: [*:0]const u8) TlsError!TlsConn {
    const method = TLS_client_method();
    const ctx = SSL_CTX_new(method) orelse return error.InitFailed;
    errdefer SSL_CTX_free(ctx);

    const ssl = SSL_new(ctx) orelse return error.InitFailed;
    errdefer SSL_free(ssl);

    setSni(ssl, hostname);

    if (SSL_set_fd(ssl, @intCast(fd)) != 1) return error.ConnectFailed;
    if (SSL_connect(ssl) != 1) return error.ConnectFailed;

    return .{ .ssl = ssl, .ctx = ctx };
}

pub fn write(conn: *TlsConn, data: []const u8) TlsError!usize {
    if (data.len == 0) return 0;
    const n = SSL_write(conn.ssl, data.ptr, @intCast(@min(data.len, std.math.maxInt(c_int))));
    if (n <= 0) return error.WriteFailed;
    return @intCast(n);
}

pub fn read(conn: *TlsConn, buf: []u8) TlsError!usize {
    if (buf.len == 0) return 0;
    const n = SSL_read(conn.ssl, buf.ptr, @intCast(@min(buf.len, std.math.maxInt(c_int))));
    if (n <= 0) return error.ReadFailed;
    return @intCast(n);
}

pub fn close(conn: *TlsConn) void {
    _ = SSL_shutdown(conn.ssl);
    SSL_free(conn.ssl);
    SSL_CTX_free(conn.ctx);
}

