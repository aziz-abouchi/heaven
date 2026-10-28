// HEAVEN:net_sockets — sockets cross-platform (Linux/macOS/Windows).
// 2026-10-28 : refactor Windows. std.posix.socket_t est i32 sur POSIX
// mais *SOCKET__opaque sur Windows -> helpers handleFromI64/handleToI64.
// read/write utilisent ws2_32.recv/send sur Windows (posix.read/write
// utilisent ReadFile/WriteFile, incompatibles avec les sockets).
// close utilise closesocket sur Windows (posix.close utilise CloseHandle).
const std = @import("std");
const builtin = @import("builtin");
const target = @import("target.zig");

// WSAStartup one-time (Windows, obligatoire avant tout appel socket).
var wsa_initialized = std.atomic.Value(bool).init(false);

fn ensureWsaInit() void {
    if (comptime !target.is_windows) return;
    if (wsa_initialized.load(.acquire)) return;
    const ws2_32 = std.os.windows.ws2_32;
    var wsadata: ws2_32.WSADATA = undefined;
    if (ws2_32.WSAStartup(0x0202, &wsadata) == 0) {
        wsa_initialized.store(true, .release);
    }
}

inline fn handleFromI64(h: i64) std.posix.socket_t {
    if (comptime target.is_windows) {
        return @ptrFromInt(@as(usize, @intCast(h)));
    } else {
        return @intCast(h);
    }
}

inline fn handleToI64(h: std.posix.socket_t) i64 {
    if (comptime target.is_windows) {
        return @intCast(@intFromPtr(h));
    } else {
        return @intCast(h);
    }
}

inline fn closeHandle(fd: std.posix.socket_t) void {
    if (comptime target.is_windows) {
        _ = std.os.windows.ws2_32.closesocket(fd);
    } else {
        std.posix.close(fd);
    }
}

pub fn setNonBlocking(socket: std.posix.socket_t) !void {
    if (target.is_windows) {
        var mode: c_ulong = 1;
        _ = std.os.windows.ws2_32.ioctlsocket(socket, std.os.windows.ws2_32.FIONBIO, &mode);
    } else {
        const flags = try std.posix.fcntl(socket, std.posix.F.GETFL, 0);
        const O_NONBLOCK = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos => @as(u32, 0x0004),
            .linux => @as(u32, 0o4000),
            else => @as(u32, 0x0004),
        };
        _ = try std.posix.fcntl(socket, std.posix.F.SETFL, flags | O_NONBLOCK);
    }
}

pub const net = struct {
    pub fn listenTcp(port: u16) !i64 {
        ensureWsaInit();
        const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch return error.InvalidInput;
        errdefer closeHandle(fd);

        if (comptime !target.is_windows) {
            const one: c_int = 1;
            std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&one)) catch {};
        }

        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
        std.posix.bind(fd, &addr.any, addr.getOsSockLen()) catch {
            closeHandle(fd);
            return error.InvalidInput;
        };
        std.posix.listen(fd, 128) catch {
            closeHandle(fd);
            return error.InvalidInput;
        };
        return handleToI64(fd);
    }

    pub fn accept(fd_i: i64) !i64 {
        ensureWsaInit();
        const fd = handleFromI64(fd_i);
        const client = std.posix.accept(fd, null, null, 0) catch return error.InvalidInput;
        return handleToI64(client);
    }

    pub fn read(fd_i: i64, buf: []u8) !usize {
        const fd = handleFromI64(fd_i);
        if (comptime target.is_windows) {
            const r = std.os.windows.ws2_32.recv(fd, buf.ptr, @intCast(buf.len), 0);
            if (r == std.os.windows.ws2_32.SOCKET_ERROR) return error.InvalidInput;
            return @intCast(r);
        } else {
            return std.posix.read(fd, buf) catch return error.InvalidInput;
        }
    }

    pub fn write(fd_i: i64, data: []const u8) !usize {
        const fd = handleFromI64(fd_i);
        if (comptime target.is_windows) {
            const r = std.os.windows.ws2_32.send(fd, data.ptr, @intCast(data.len), 0);
            if (r == std.os.windows.ws2_32.SOCKET_ERROR) return error.InvalidInput;
            return @intCast(r);
        } else {
            return std.posix.write(fd, data) catch return error.InvalidInput;
        }
    }

    pub fn close(fd_i: i64) void {
        closeHandle(handleFromI64(fd_i));
    }

    pub fn socketTcp() i64 {
        ensureWsaInit();
        const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch return -1;
        return handleToI64(fd);
    }

    pub fn socketUdp() i64 {
        ensureWsaInit();
        const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch return -1;
        return handleToI64(fd);
    }

    pub fn sendtoUdp(fd_i: i64, ip: []const u8, port: u16, data: []const u8) i64 {
        const fd = handleFromI64(fd_i);
        const addr = std.net.Address.parseIp4(ip, port) catch return -1;
        const n = std.posix.sendto(fd, data, 0, &addr.any, addr.getOsSockLen()) catch return -1;
        return @intCast(n);
    }

    pub fn setRecvTimeout(fd_i: i64, timeout_ns: u64) void {
        if (comptime target.is_windows) return;
        const sec: i64 = @intCast(timeout_ns / 1_000_000_000);
        const usec: i64 = @intCast((timeout_ns % 1_000_000_000) / 1000);
        var tv: [16]u8 = [_]u8{0} ** 16;
        @memcpy(tv[0..8], std.mem.asBytes(&sec));
        @memcpy(tv[8..16], std.mem.asBytes(&usec));
        const fd = handleFromI64(fd_i);
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &tv) catch {};
    }

    pub fn recvfromUdp(fd_i: i64, buf: []u8) i64 {
        const fd = handleFromI64(fd_i);
        const n = std.posix.recvfrom(fd, buf, 0, null, null) catch return -1;
        return @intCast(n);
    }

    pub fn connectTcp(ip: []const u8, port: u16) !i64 {
        ensureWsaInit();
        const addr = std.net.Address.parseIp4(ip, port) catch return error.InvalidInput;
        const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch return error.InvalidInput;
        errdefer closeHandle(fd);
        std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
            closeHandle(fd);
            return error.ConnectFailed;
        };
        return handleToI64(fd);
    }
};
