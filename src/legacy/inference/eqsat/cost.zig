const std = @import("std");

pub const CostProfile = struct {
    cpu_ns: u64 = 0,
    energy_pj: u64 = 0,
    memory_bytes: u64 = 0,
    latency_ns: u64 = 0,
    allocations: u64 = 0,
    network_bytes: u64 = 0,
};

pub const CostWeights = struct {
    cpu: u32 = 1,
    energy: u32 = 1,
    memory: u32 = 1,
    latency: u32 = 1,
    allocations: u32 = 1,
    network: u32 = 1,

    pub fn score(self: CostWeights, p: CostProfile) u64 {
        return
            @as(u64, self.cpu) * p.cpu_ns +
            @as(u64, self.energy) * p.energy_pj +
            @as(u64, self.memory) * p.memory_bytes +
            @as(u64, self.latency) * p.latency_ns +
            @as(u64, self.allocations) * p.allocations +
            @as(u64, self.network) * p.network_bytes;
    }
};
