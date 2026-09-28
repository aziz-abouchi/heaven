// src/runtime/vessel.zig
const std = @import("std");

pub const Vessel = struct {
    alias: []const u8,
    uid: [16]u8, // UUID v7 (Time-ordered)
    pub_key: [32]u8, // Ed25519 ou similaire pour l'identité cryptographique

    // État local du nœud
    status: enum { booting, joining, active, syncing },

    pub fn init(allocator: std.mem.Allocator, alias: []const u8) !Vessel {
        // Logique de génération d'UID v7 et de clé publique ici
        return .{
            .alias = alias,
            .uid = try generate_uuid_v7(),
            .pub_key = try generate_keypair(),
            .status = .booting,
        };
    }

    pub fn boot(self: *Vessel) !void {
        // platform.debug.print("Vessel {s} initialized. Booting Swarm interface...\n", .{self.alias});
        // Ici : initialisation de la pile WebRTC
        self.status = .joining;
    }
};

fn generate_uuid_v7() ![16]u8 {
    // TODO: Implémenter la génération UUIDv7 triable par le temps
    return [16]u8{0} ** 16;
}
