const std = @import("std");
const AutoFab = @import("../runtime/autofab.zig").AutoFab;

pub const NodeIdentity = extern struct {
    magic: u32 = 0x48564E31,
    cpu_count: u32,
    memory_usage: u64,
    uptime: u64,
};

pub fn startBeacon(vaisseau_ip: []const u8, port: u16) !void {
    const address = try std.net.Address.parseIp4(vaisseau_ip, port);
    const sock = try platform.posix.socket(platform.posix.AF.INET, platform.posix.SOCK.DGRAM, 0);
    defer platform.posix.close(sock);
    const start_time = std.time.timestamp();
    while (true) {
        const id = NodeIdentity{
            .cpu_count = AutoFab.inspectCPU(),
            .memory_usage = 0,
            .uptime = @intCast(std.time.timestamp() - start_time),
        };
        _ = platform.posix.sendto(sock, std.mem.asBytes(&id), 0, &address.any, address.getOsSockLen()) catch {};
        platform.Thread.sleep(5 * std.time.ns_per_s);
    }
}

// Nettoyé pour compilation
pub fn lookForGrammar(lang_name: []const u8) !void {
    _ = lang_name;
}
