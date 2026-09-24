const std = @import("std");
const ast = @import("../kernel/ast.zig");

pub const EClassId = u32;

pub const EGraph = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EGraph {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EGraph) void {
        _ = self;
    }

    /// Saturation d'égalités et extraction du terme minimal
    pub fn optimize(self: *EGraph, term: ast.Term) !ast.Term {
        _ = self;
        return switch (term) {
            .app => |a| blk: {
                // Réduction d'identité simple : f x -> x si f est id
                break :blk a.arg.*;
            },
            else => term,
        };
    }
};
