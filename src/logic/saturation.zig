const std = @import("std");
const egraph = @import("egraph.zig");
const egraph_rewrite = @import("egraph_rewrite.zig");

const Allocator = std.mem.Allocator;
const EGraph = egraph.EGraph;
const RewriteEngine = egraph_rewrite.RewriteEngine;

pub const SaturationOptions = struct {
    max_iterations: usize = 30,
    max_nodes: usize = 10000,
};

pub const SaturationResult = enum {
    Saturated,
    NodeLimitReached,
    IterationLimitReached,
};

pub const SaturationEngine = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) SaturationEngine {
        return .{ .allocator = allocator };
    }

    /// Exécute la boucle de saturation d'égalité sur l'E-Graph.
    pub fn saturate(
        self: *SaturationEngine,
        eg: *EGraph,
        rewriter: *RewriteEngine,
        options: SaturationOptions,
    ) !SaturationResult {
        _ = self;
        var iter: usize = 0;

        while (iter < options.max_iterations) : (iter += 1) {
            if (eg.nodeCount() >= options.max_nodes) {
                return .NodeLimitReached;
            }

            const changes = try rewriter.applyPass(eg);

            if (changes == 0) {
                return .Saturated; // Point fixe atteint
            }
        }

        return .IterationLimitReached;
    }
};
