const std = @import("std");
const platform = @import("platform");

const Registry = std.AutoHashMap([16]u8, std.net.Stream);

pub const Coordinator = struct {
    registry: Registry,
    mutex: platform.Thread.Mutex,

    pub fn handleClient(self: *Coordinator, conn: std.net.Stream) !void {
        while (true) {
            // 1. Lire le Header
            var header: Header = undefined;
            try conn.readNoEof(std.mem.asBytes(&header));

            // 2. Gestion de l'enregistrement (HELLO)
            if (header.msg_type == .hello) {
                self.mutex.lock();
                defer self.mutex.unlock();
                try self.registry.put(header.sender_id, conn);
                continue;
            }

            // 3. Routage (OFFER, ANSWER, CANDIDATE)
            self.mutex.lock();
            const target_conn = self.registry.get(header.target_id);
            self.mutex.unlock();

            if (target_conn) |dest| {
                // Transférer le header + le payload
                try dest.writeAll(std.mem.asBytes(&header));
                // Lire le reste du payload et le transférer
                var buffer = try self.allocator.alloc(u8, header.length);
                defer self.allocator.free(buffer);
                try conn.readNoEof(buffer);
                try dest.writeAll(buffer);
            }
        }
    }
};
