const std = @import("std");

pub const Candidate = struct {
    id: u32,
    weight: f32,
};

pub const SRG = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u32, std.ArrayList(Candidate)),
    seed: u64,

    pub fn init(alloc: std.mem.Allocator) SRG {
        return .{
            .allocator = alloc,
            .map = std.AutoHashMap(u32, std.ArrayList(Candidate)).init(alloc),
            .seed = 1337,
        };
    }

    pub fn addCandidate(self: *SRG, symbol: u32, id: u32, weight: f32) !void {
        var entry = try self.map.getOrPut(symbol);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayList(Candidate).init(self.allocator);
        }
        try entry.value_ptr.append(.{ .id = id, .weight = weight });
    }

    pub fn candidates(self: *SRG, symbol: u32) []Candidate {
        if (self.map.get(symbol)) |list| return list.items;
        return &[_]Candidate{};
    }

    pub fn select(self: *SRG, symbol: u32) u32 {
        const cands = self.candidates(symbol);
        if (cands.len == 0) return 0;

        const epsilon: f32 = 0.1;
        const rand = (symbol ^ self.seed) % 100;

        if (rand < @as(u64, @intFromFloat(epsilon * 100))) {
            return cands[rand % cands.len].id;
        }

        var best = cands[0].id;
        var best_score: f32 = -1e9;

        for (cands) |c| {
            const noise = @as(f32, @floatFromInt((c.id ^ self.seed) % 100)) / 100.0;
            const score = c.weight + noise * 0.01;

            if (score > best_score) {
                best_score = score;
                best = c.id;
            }
        }

        return best;
    }

    pub fn updateSuccess(self: *SRG, symbol: u32, impl: u32, reward: f32) void {
        if (self.map.getPtr(symbol)) |list| {
            for (list.items) |*c| {
                if (c.id == impl) {
                    c.weight += reward;
                    return;
                }
            }
        }
    }

    pub fn updateFailure(self: *SRG, symbol: u32, impl: u32, penalty: f32) void {
        if (self.map.getPtr(symbol)) |list| {
            for (list.items) |*c| {
                if (c.id == impl) {
                    c.weight -= penalty;
                    return;
                }
            }
        }
    }
};
