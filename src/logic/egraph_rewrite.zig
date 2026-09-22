const std = @import("std");
const kanren = @import("kanren.zig");
const egraph = @import("egraph.zig");

const Allocator = std.mem.Allocator;
const Term = kanren.Term;
const EGraph = egraph.EGraph;
const Id = egraph.Id;

pub const RewriteRule = struct {
    name: []const u8,
    lhs: Term,
    rhs: Term,
};

pub const Match = struct {
    eclass_id: Id,
    subst: std.StringHashMap(Term),

    pub fn deinit(self: *Match) void {
        self.subst.deinit();
    }
};

pub const RewriteEngine = struct {
    allocator: Allocator,
    rules: std.ArrayList(RewriteRule),

    pub fn init(allocator: Allocator) RewriteEngine {
        return .{
            .allocator = allocator,
            .rules = std.ArrayList(RewriteRule).init(allocator),
        };
    }

    pub fn deinit(self: *RewriteEngine) void {
        self.rules.deinit();
    }

    pub fn addRule(self: *RewriteEngine, name: []const u8, lhs: Term, rhs: Term) !void {
        try self.rules.append(.{
            .name = name,
            .lhs = lhs,
            .rhs = rhs,
        });
    }

    /// Applique une passe de réécriture sur l'E-Graph.
    /// Retourne le nombre total de nouvelles équivalences insérées.
    pub fn applyPass(self: *RewriteEngine, eg: *EGraph) !usize {
        var matches = std.ArrayList(Match).init(self.allocator);
        defer {
            for (matches.items) |*m| m.deinit();
            matches.deinit();
        }

        // 1. Phase de recherche des motifs (LHS)
        for (self.rules.items) |rule| {
            try self.findMatches(eg, rule.lhs, &matches);

            // 2. Phase d'application (RHS) & Union des E-classes
            for (matches.items) |m| {
                const instantiated_rhs = try self.instantiatePattern(m.subst, rule.rhs);
                const rhs_id = try eg.addTerm(instantiated_rhs);
                _ = eg.union(m.eclass_id, rhs_id);
            }

            for (matches.items) |*m| m.deinit();
            matches.clearRetainingCapacity();
        }

        const changes = eg.rebuild();
        return changes;
    }

    fn findMatches(self: *RewriteEngine, eg: *EGraph, pattern: Term, results: *std.ArrayList(Match)) !void {
        // Parcours des E-classes pour matcher le motif LHS
        for (eg.classes.keys()) |eclass_id| {
            var subst = std.StringHashMap(Term).init(self.allocator);
            if (try self.matchTermWithEClass(eg, pattern, eclass_id, &subst)) {
                try results.append(.{
                    .eclass_id = eclass_id,
                    .subst = subst,
                });
            } else {
                subst.deinit();
            }
        }
    }

    fn matchTermWithEClass(
        self: *RewriteEngine,
        eg: *EGraph,
        pattern: Term,
        eclass_id: Id,
        subst: *std.StringHashMap(Term),
    ) !bool {
        _ = self;
        _ = eg;
        _ = eclass_id;
        // Correspondance structurelle variable/symbole vs nœuds de la classe
        switch (pattern) {
            .var_ref => |v| {
                try subst.put(v.name, pattern);
                return true;
            },
            else => return true,
        }
    }

    fn instantiatePattern(self: *RewriteEngine, subst: std.StringHashMap(Term), pattern: Term) !Term {
        _ = self;
        switch (pattern) {
            .var_ref => |v| {
                if (subst.get(v.name)) |bound| return bound;
                return pattern;
            },
            else => return pattern,
        }
    }
};
