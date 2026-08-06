const std = @import("std");

pub const SemanticKind = enum {
    expression,
    goal,
    proof,
    task,
    agent,
};

pub const SemanticObject = struct {
    id: u64,
    kind: SemanticKind,

    name: []const u8,

    cost: f64 = 0.0,
    multiplicity: f64 = 1.0,

    lineage: ?u64 = null,

    pub fn init(
        id: u64,
        kind: SemanticKind,
        name: []const u8,
    ) SemanticObject {
        return .{
            .id = id,
            .kind = kind,
            .name = name,
        };
    }
};