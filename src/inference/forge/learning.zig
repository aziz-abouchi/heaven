const std = @import("std");
const SRG = @import("../../runtime/symbolResolutionGraph.zig").SRG;

pub const LearningEngine = struct {
    allocator: std.mem.Allocator,
    srg: *SRG,

    pub fn init(alloc: std.mem.Allocator, srg: *SRG) LearningEngine {
        return .{
            .allocator = alloc,
            .srg = srg,
        };
    }

    pub fn recordSuccess(self: *LearningEngine, symbol: u32, impl: u32, duration_ns: u64) void {
        const time = @as(f32, @floatFromInt(duration_ns));
        const reward = 1000.0 / @max(1.0, time);

        self.srg.updateSuccess(symbol, impl, reward);
    }

    pub fn recordFailure(self: *LearningEngine, symbol: u32, impl: u32) void {
        self.srg.updateFailure(symbol, impl, 5.0);
    }
};
