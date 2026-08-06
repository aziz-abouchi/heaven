const std = @import("std");

pub const Identity = struct {
    pubkey: [32]u8,
    privkey: [64]u8,

    pub fn generate() Identity {
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);

        var kp: std.crypto.sign.Ed25519.KeyPair = undefined;
        std.crypto.sign.Ed25519.keyPairFromSeed(&kp, seed);

        return .{
            .pubkey = kp.public_key,
            .privkey = kp.secret_key,
        };
    }

    pub fn peerId(self: Identity) u64 {
        var hash: [32]u8 = undefined;
        std.crypto.hash.blake3.hash(&self.pubkey, &hash, .{});
        return std.mem.readInt(u64, hash[0..8], .little);
    }
};
