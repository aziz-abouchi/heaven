const std = @import("std");
const SemanticObject = @import("semantic.zig").SemanticObject;

pub const Relation = enum {
    proves,
    rewrites,
    depends_on,
    computes,
    spawns,
};

pub const SemanticEdge = struct {
    from: usize,
    to: usize,
    relation: Relation,
};

pub const SemanticGraph = struct {
    allocator: std.mem.Allocator,

    nodes: std.ArrayList(SemanticObject),
    edges: std.ArrayList(SemanticEdge),

    pub fn init(
        allocator: std.mem.Allocator,
    ) SemanticGraph {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(SemanticObject).init(allocator),
            .edges = std.ArrayList(SemanticEdge).init(allocator),
        };
    }

    pub fn deinit(self: *SemanticGraph) void {
        self.nodes.deinit();
        self.edges.deinit();
    }

    pub fn addNode(
        self: *SemanticGraph,
        node: SemanticObject,
    ) !usize {
        try self.nodes.append(node);
        return self.nodes.items.len - 1;
    }

    pub fn addEdge(
        self: *SemanticGraph,
        from: usize,
        to: usize,
        relation: Relation,
    ) !void {
        try self.edges.append(.{
            .from = from,
            .to = to,
            .relation = relation,
        });
    }
};