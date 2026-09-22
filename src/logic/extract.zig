const std = @import("std");
const kanren = @import("kanren.zig");
const egraph = @import("egraph.zig");

const Allocator = std.mem.Allocator;
const Term = kanren.Term;
const EGraph = egraph.EGraph;
const Id = egraph.Id;

pub const CostFn = *const fn (term: Term, child_costs: []const usize) usize;

pub fn defaultAstSizeCost(term: Term, child_costs: []const usize) usize {
    _ = term;
    var total: usize = 1;
    for (child_costs) |c| total += c;
    return total;
}

pub const Extractor = struct {
    allocator: Allocator,
    costs: std.AutoHashMap(Id, usize),
    best_terms: std.AutoHashMap(Id, Term),

    pub fn init(allocator: Allocator) Extractor {
        return .{
            .allocator = allocator,
            .costs = std.AutoHashMap(Id, usize).init(allocator),
            .best_terms = std.AutoHashMap(Id, Term).init(allocator),
        };
    }

    pub fn deinit(self: *Extractor) void {
        self.costs.deinit();
        self.best_terms.deinit();
    }

    /// Extrait le terme de coût minimal pour une E-classe donnée.
    pub fn extractBest(self: *Extractor, eg: *EGraph, root_id: Id, cost_fn: CostFn) !Term {
        const canonical_root = eg.find(root_id);

        // Analyse ascendante de calcul de coûts (bottom-up cost analysis)
        var changed = true;
        while (changed) {
            changed = false;
            for (eg.classes.keys()) |eclass_id| {
                const canon_id = eg.find(eclass_id);
                const class_nodes = eg.classes.get(canon_id) orelse continue;

                for (class_nodes.items) |node| {
                    var node_cost: usize = 1;
                    var children_valid = true;

                    var child_costs = std.ArrayList(usize).init(self.allocator);
                    defer child_costs.deinit();

                    for (node.children) |child_id| {
                        const canon_child = eg.find(child_id);
                        if (self.costs.get(canon_child)) |c| {
                            try child_costs.append(c);
                        } else {
                            children_valid = false;
                            break;
                        }
                    }

                    if (!children_valid) continue;

                    node_cost = cost_fn(node.term, child_costs.items);

                    const current_best_cost = self.costs.get(canon_id) orelse std.math.maxInt(usize);
                    if (node_cost < current_best_cost) {
                        try self.costs.put(canon_id, node_cost);
                        try self.best_terms.put(canon_id, node.term);
                        changed = true;
                    }
                }
            }
        }

        return self.best_terms.get(canonical_root) orelse error.ExtractionFailed;
    }
};
