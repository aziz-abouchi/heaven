const std = @import("std");
const SRG = @import("symbolResolutionGraph.zig").SRG;

pub const Step = struct {
    symbol_id: u32,
    code: []const u8,
};

pub const Plan = struct {
    steps: []Step,
};

pub const EQSATPlanner = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) EQSATPlanner {
        return .{ .allocator = alloc };
    }

    pub fn plan(self: *EQSATPlanner, root: u32, srg: *SRG) !Plan {
        _ = srg;
        var steps = std.ArrayList(Step).init(self.allocator);

        // version minimale : 1 étape
        try steps.append(.{
            .symbol_id = root,
            .code = "main",
        });

        return .{
            .steps = try steps.toOwnedSlice(),
        };
    }
};
