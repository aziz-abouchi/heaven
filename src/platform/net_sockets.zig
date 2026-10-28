// HEAVEN:net_sockets — extraction sockets (refactor plateforme)
// 2026-10-28 (Phase 6) : refactor cross-platform via std.posix
// + std.net.Address. Plus de std.os.linux.syscall* : ces syscalls
// sont Linux-only et SIGSYS sur macOS. std.posix dispatch par OS.
// Windows garde son stub dans x86_64_windows.zig (WSAStartup +
// ws2_32 à implémenter en Phase 6).
const std = @import("std");
const builtin = @import("builtin");
const target = @import("target.zig");

pub fn setNonBlocking(socket: std.posix.socket_t) !void {
    if (target.is_windows) {
        var mode: c_ulong = 1;
        _ = std.os.windows.ws2_32.ioctlsocket(socket, std.os.windows.ws2_32.FIONBIO, &mode);
    } else {
        const fd = socket;
        const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        const O_NONBLOCK = switch (builtin.os.tag) {
            .macos, .ios, .tvos, .watchos, .visionos => @as(u32, 0x0004),
            .linux => @as(u32, 0o4000),
            else => @as(u32, 0x0004),
        };
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | O_NONBLOCK);
    }
}

pub const net = struct {
    fn socketTcpImpl() !std.posix.socket_t {
        return std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
    }

    pub fn listenTcp(port: u16) !i64 {
        const fd = socketTcpImpl() catch return error.InvalidInput;

        const one: c_int = 1;
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&one)) catch {};

        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
        std.posix.bind(fd, &addr.any, addr.getOsSockLen()) catch {
            std.posix.close(fd);
            return error.InvalidInput;
        };

        std.posix.listen(fd, 128) catch {
            std.posix.close(fd);
            return error.InvalidInput;
        };

        return @intCast(fd);
    }

    pub fn accept(fd_i: i64) !i64 {
        const fd: std.posix.socket_t = @intCast(fd_i);
        const client = std.posix.accept(fd, null, null, 0) catch return error.InvalidInput;
        return @intCast(client);
    }

    pub fn read(fd_i: i64, buf: []u8) !usize {
        const fd: std.posix.socket_t = @intCast(fd_i);
        return std.posix.read(fd, buf) catch return error.InvalidInput;
    }

    pub fn write(fd_i: i64, data: []const u8) !usize {
        const fd: std.posix.socket_t = @intCast(fd_i);
        return std.posix.write(fd, data) catch return error.InvalidInput;
    }

    pub fn close(fd_i: i64) void {
        const fd: std.posix.socket_t = @intCast(fd_i);
        std.posix.close(fd);
    }

    pub fn socketTcp() i64 {
        const fd = socketTcpImpl() catch return -1;
        return @intCast(fd);
    }

    pub fn socketUdp() i64 {
        const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0) catch return -1;
        return @intCast(fd);
    }

    pub fn sendtoUdp(fd_i: i64, ip: []const u8, port: u16, data: []const u8) i64 {
        const fd: std.posix.socket_t = @intCast(fd_i);
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
        const fd: std.posix.socket_t = @intCast(fd_i);
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &tv) catch {};
    }

    pub fn recvfromUdp(fd_i: i64, buf: []u8) i64 {
        const fd: std.posix.socket_t = @intCast(fd_i);
        const n = std.posix.recvfrom(fd, buf, 0, null, null) catch return -1;
        return @intCast(n);
    }

    pub fn connectTcp(ip: []const u8, port: u16) !i64 {
        const addr = std.net.Address.parseIp4(ip, port) catch return error.InvalidInput;
        const fd = socketTcpImpl() catch return error.InvalidInput;
        std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
            std.posix.close(fd);
            return error.ConnectFailed;
        };
        return @intCast(fd);
    }
};
