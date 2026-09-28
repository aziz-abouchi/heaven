const std = @import("std");
const Matrix = @import("../core/matrix.zig").Matrix;
const SRG = @import("symbolResolutionGraph.zig").SRG;
const EQSAT = @import("eQSATPlanner.zig").EQSATPlanner;
const AutoFab = @import("autofab.zig").AutoFab;

pub const Engine = struct {
    allocator: std.mem.Allocator,
    matrix: *Matrix,
    srg: *SRG,
    planner: *EQSAT,
    autofab: ?*AutoFab,
    learner: *LearningEngine,

    pub fn init(
        alloc: std.mem.Allocator,
        matrix: *Matrix,
        srg: *SRG,
        planner: *EQSAT,
    ) Engine {
        return .{
            .allocator = alloc,
            .matrix = matrix,
            .srg = srg,
            .planner = planner,
            .autofab = null,
        };
    }

    pub fn bindAutoFab(self: *Engine, fab: *AutoFab) void {
        self.autofab = fab;
    }

    pub fn run(self: *Engine, root: u32) !void {
        const plan = try self.planner.plan(root, self.srg);

        for (plan.steps) |step| {
            const impl = self.srg.select(step.symbol_id);

            const start = std.time.nanoTimestamp();

            if (self.autofab) |fab| {
                if (fab.executeDeterministic(impl, step.code)) |_| {
                    const duration = std.time.nanoTimestamp() - start;
                    self.learner.recordSuccess(step.symbol_id, impl, @intCast(duration));
                } else |err| {
                    self.learner.recordFailure(step.symbol_id, impl);
                    return err;
                }
            }
        }
    }
};
