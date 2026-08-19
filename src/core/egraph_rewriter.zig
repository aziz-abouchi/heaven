const std = @import("std");
const egraph_mod = @import("egraph");
const pattern = @import("pattern");
const expr = @import("expr");
const platform = @import("platform");
const Store = expr.Store;
const Id = expr.Id;
const EGraph = egraph_mod.EGraph;

pub const Rewriter = struct {
    egraph: *EGraph,
    store: *Store,
    allocator: std.mem.Allocator,
    match_cache: std.AutoHashMapUnmanaged(u64, Id) = .{}, // clé = (rule_id << 32) | class_id

    pub fn init(egraph: *EGraph, store: *Store, allocator: std.mem.Allocator) Rewriter {
        return .{
            .egraph = egraph,
            .store = store,
            .allocator = allocator,
            .match_cache = .{},
        };
    }

    pub fn deinit(self: *Rewriter) void {
        self.match_cache.deinit(self.allocator);
    }

    pub fn saturate(self: *Rewriter, budget_ms: u64) !u32 {
        const start = platform.time.milliTimestamp();
        var merge_count: u32 = 0;
        var changed = true;
        var iterations: u32 = 0;

        while (changed and iterations < 5) : (iterations += 1) {
            if (platform.time.milliTimestamp() - start > budget_ms) break;
            self.match_cache.clearRetainingCapacity();

            // Pré-allouer le cache pour éviter les réallocations
            const estimated_capacity = self.egraph.classes.items.len * self.store.len();
            try self.match_cache.ensureTotalCapacity(self.allocator, estimated_capacity);

            changed = false;

            var rule_idx: u32 = 0;
            while (rule_idx < self.store.len()) : (rule_idx += 1) {
                const rule_node = self.store.get(rule_idx);
                if (rule_node.tag != .relation) continue;

                const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
                if (lhs_rhs.len != 2) continue;
                const lhs_id = lhs_rhs[0];
                const rhs_id = lhs_rhs[1];

                var class_idx: u32 = 0;
                while (class_idx < self.egraph.classes.items.len) : (class_idx += 1) {
                    if (platform.time.milliTimestamp() - start > budget_ms) break;
                    const eclass = &self.egraph.classes.items[class_idx];

                    for (eclass.nodes.items) |node_id| {
                        // Clé de cache : (rule_id << 32) | class_id
                        const cache_key = (@as(u64, @intCast(rule_idx)) << 32) | @as(u64, @intCast(class_idx));

                        // Vérifier le cache
                        if (self.match_cache.get(cache_key)) |cached_result| {
                            if (cached_result != 0) {
                                const new_class = try self.egraph.addExpr(cached_result);
                                const merged = try self.egraph.merge(class_idx, new_class);
                                if (merged != class_idx) {
                                    changed = true;
                                    merge_count += 1;
                                }
                            }
                            continue;
                        }

                        // Pas dans le cache : essayer de matcher
                        var bindings = std.AutoHashMapUnmanaged(u32, Id){};
                        defer bindings.deinit(self.allocator);

                        if (pattern.exprPatternMatch(self.store, lhs_id, node_id, &bindings, self.allocator)) {
                            const new_id = pattern.substitutePattern(self.store, rhs_id, &bindings, self.allocator) catch continue;
                            // Stocker dans le cache
                            try self.match_cache.put(self.allocator, cache_key, new_id);
                            const new_class = try self.egraph.addExpr(new_id);
                            const merged = try self.egraph.merge(class_idx, new_class);
                            if (merged != class_idx) {
                                changed = true;
                                merge_count += 1;
                            }
                        } else {
                            // Aucun match : stocker 0
                            try self.match_cache.put(self.allocator, cache_key, 0);
                        }
                    }
                }
            }
        }

        const elapsed = platform.time.milliTimestamp() - start;
        platform.debug.print("EGraph saturation: {} ms, {} merges, {} iterations\n", .{
            elapsed,
            merge_count,
            iterations,
        });

        return merge_count;
    }
};

test "rewriter — simple rule x+0 => x" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const lhs = try store.binop("+", x, zero);
    const rhs = x;
    _ = try store.relation("=>", &.{ lhs, rhs }, &.{});

    const a = try store.sym("a");
    const expr_id = try store.binop("+", a, zero);
    _ = try egraph.addExpr(expr_id);

    var rewriter = Rewriter.init(&egraph, &store, allocator);
    const merges = try rewriter.saturate(1000);

    try std.testing.expect(merges > 0);
    try std.testing.expect(egraph.areEqual(expr_id, a));
}
