const std = @import("std");

pub const Id = u32;

/// Représentation d’un noeud e-graph
pub const ENode = struct {
    op: []const u8,
    children: []Id,
};

/// Classe d'équivalence
pub const EClass = struct {
    id: Id,
    nodes: std.ArrayList(ENode),
};

/// E-Graph minimal (EQSAT-ready)
pub const EGraph = struct {
    allocator: std.mem.Allocator,
    classes: std.AutoHashMap(Id, EClass),
    parents: std.AutoHashMap(Id, Id),

    pub fn init(allocator: std.mem.Allocator) EGraph {
        return .{
            .allocator = allocator,
            .classes = std.AutoHashMap(Id, EClass).init(allocator),
            .parents = std.AutoHashMap(Id, Id).init(allocator),
        };
    }

    /// Find avec path compression
    pub fn find(self: *EGraph, id: Id) Id {
        if (self.parents.get(id)) |p| {
            if (p == id) return id;
            const root = self.find(p);
            self.parents.put(id, root) catch {};
            return root;
        }
        return id;
    }

    /// 🔥 FIX: anciennement `union`
    pub fn merge(self: *EGraph, a: Id, b: Id) !void {
        const ra = self.find(a);
        const rb = self.find(b);

        if (ra == rb) return;

        try self.parents.put(ra, rb);

        // fusion des classes
        if (self.classes.getPtr(rb)) |class_b| {
            if (self.classes.getPtr(ra)) |class_a| {
                for (class_a.nodes.items) |n| {
                    try class_b.nodes.append(n);
                }
            }
        }
    }

    /// Ajout d’un enode
    pub fn add(self: *EGraph, node: ENode) !Id {
        const id: Id = @intCast(self.classes.count() + 1);

        var list = std.ArrayList(ENode).init(self.allocator);
        try list.append(node);

        try self.classes.put(id, .{
            .id = id,
            .nodes = list,
        });

        try self.parents.put(id, id);

        return id;
    }

    /// Saturation naïve (placeholder EQSAT)
    pub fn rebuild(self: *EGraph) void {
        _ = self;
        // ici tu brancheras tes rewrites
    }
};
