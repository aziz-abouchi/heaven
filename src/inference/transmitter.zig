const std = @import("std");
const autofab_lib = @import("../runtime/autofab.zig");

pub const Transmitter = struct {
    pub fn transmit(code: []const u8) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();

        // Taille totale : Header (8 octets supposés) + code
        const header_size = 8;
        const packet = try allocator.alloc(u8, header_size + code.len);
        defer allocator.free(packet);

        var fbs = std.io.fixedBufferStream(packet);
        const writer = fbs.writer();

        // Écriture séquentielle forcée en .big (pour éviter le problème d'Endianness)
        try writer.writeInt(u32, 0xDEADC0DE, .big);
        try writer.writeInt(u32, @intCast(code.len), .big);
        try writer.writeAll(code);

        // Maintenant vous pouvez envoyer 'packet' via le réseau
        // _ = try platform.posix.sendto(socket, packet, ...);
    }
};
