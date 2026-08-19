const std = @import("std");
const egraph_mod = @import("egraph");
const pattern = @import("pattern");
const expr = @import("expr");
const platform = @import("platform");
const Store = expr.Store;
const Id = expr.Id;
const EGraph = egraph_mod.EGraph;
const ClassId = egraph_mod.ClassId;
const ProofStep = egraph_mod.ProofStep;

pub const Rewriter = struct {
    egraph: *EGraph,
    store: *Store,
    allocator: std.mem.Allocator,
    match_cache: std.AutoHashMapUnmanaged(u64, Id) = .{},

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
        var iterations: u32 = 0;

        var worklist = try std.ArrayList(u32).initCapacity(self.allocator, 0);
        defer worklist.deinit(self.allocator);

        for (0..self.egraph.classes.items.len) |i| {
            try worklist.append(self.allocator, @intCast(i));
        }

        while (worklist.items.len > 0) : (iterations += 1) {
            if (platform.time.milliTimestamp() - start > budget_ms) break;

            var new_worklist = try std.ArrayList(u32).initCapacity(self.allocator, 0);
            defer new_worklist.deinit(self.allocator);

            for (worklist.items) |class_idx| {
                if (class_idx >= self.egraph.classes.items.len) continue;
                const canonical = self.egraph.uf.find(class_idx);
                if (canonical != class_idx) continue;

                if (try self.applyBetaReduction(canonical)) {
                    merge_count += 1;
                    try new_worklist.append(self.allocator, canonical);
                }

                var rule_idx: u32 = 0;
                while (rule_idx < self.store.len()) : (rule_idx += 1) {
                    const rule_node = self.store.get(rule_idx);
                    if (rule_node.tag != .relation) continue;
                    const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
                    if (lhs_rhs.len != 2) continue;
                    const lhs_id = lhs_rhs[0];
                    const rhs_id = lhs_rhs[1];

                    var bindings = std.AutoHashMapUnmanaged(u32, Id){};
                    defer bindings.deinit(self.allocator);

                    if (try self.matchPatternOnClass(lhs_id, canonical, &bindings)) {
                        const cache_key = (@as(u64, @intCast(rule_idx)) << 32) | @as(u64, @intCast(canonical));
                        if (self.match_cache.get(cache_key)) |cached| {
                            if (cached != 0) {
                                const new_class = try self.egraph.addExpr(cached);
                                const merged = try self.egraph.merge(canonical, new_class);
                                if (merged != canonical) {
                                    merge_count += 1;
                                    try new_worklist.append(self.allocator, merged);
                                    try new_worklist.append(self.allocator, canonical);
                                    try self.egraph.addProof(.{
                                        .rule_id = rule_idx,
                                        .lhs = lhs_id,
                                        .rhs = cached,
                                        .timestamp = @intCast(platform.time.milliTimestamp()),
                                    });
                                }
                            }
                            continue;
                        }

                        const new_id = try pattern.substitutePattern(self.store, rhs_id, &bindings, self.allocator);
                        try self.match_cache.put(self.allocator, cache_key, new_id);
                        const new_class = try self.egraph.addExpr(new_id);
                        const merged = try self.egraph.merge(canonical, new_class);
                        if (merged != canonical) {
                            merge_count += 1;
                            try new_worklist.append(self.allocator, merged);
                            try new_worklist.append(self.allocator, canonical);
                            try self.egraph.addProof(.{
                                .rule_id = rule_idx,
                                .lhs = lhs_id,
                                .rhs = new_id,
                                .timestamp = @intCast(platform.time.milliTimestamp()),
                            });
                        }
                    } else {
                        const cache_key = (@as(u64, @intCast(rule_idx)) << 32) | @as(u64, @intCast(canonical));
                        try self.match_cache.put(self.allocator, cache_key, 0);
                    }
                }
            }

            worklist.clearRetainingCapacity();
            for (new_worklist.items) |item| {
                try worklist.append(self.allocator, item);
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

    fn matchPatternOnClass(
        self: *Rewriter,
        pattern_id: Id,
        class: ClassId,
        bindings: *std.AutoHashMapUnmanaged(u32, Id),
    ) !bool {
        const eclass = &self.egraph.classes.items[class];
        for (eclass.nodes.items) |node_id| {
            if (pattern.exprPatternMatch(self.store, pattern_id, node_id, bindings, self.allocator)) {
                return true;
            }
        }
        return false;
    }

    fn applyBetaReduction(self: *Rewriter, class: ClassId) !bool {
        const eclass = &self.egraph.classes.items[class];
        for (eclass.nodes.items) |node_id| {
            const node = self.store.get(node_id);
            if (node.tag == .apply) {
                const func_id = node.payload;
                const func_node = self.store.get(func_id);
                if (func_node.tag == .lambda) {
                    const params = func_node.span_a.slice(self.store.pool.items);
                    const body = func_node.aux;
                    const args = node.span_a.slice(self.store.pool.items);
                    if (params.len == args.len) {
                        var subst = std.AutoHashMap(u32, Id).init(self.allocator);
                        defer subst.deinit();
                        for (params, args) |p, a| {
                            try subst.put(p, a);
                        }
                        const new_body = try self.substitute(body, &subst);
                        const new_class = try self.egraph.addExpr(new_body);
                        const merged = try self.egraph.merge(class, new_class);
                        if (merged != class) {
                            try self.egraph.addProof(.{
                                .rule_id = 0,
                                .lhs = node_id,
                                .rhs = new_body,
                                .timestamp = @intCast(platform.time.milliTimestamp()),
                            });
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    fn substitute(self: *Rewriter, id: Id, subst: *const std.AutoHashMap(u32, Id)) !Id {
        const node = self.store.get(id);
        switch (node.tag) {
            .sym => {
                if (subst.get(id)) |val| return val;
                if (subst.get(node.payload)) |val| return val;
                return id;
            },
            .lit => return id,
            .apply => {
                const new_func = try self.substitute(node.payload, subst);
                const old_args = node.span_a.slice(self.store.pool.items);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                for (old_args) |arg| {
                    try new_args.append(self.allocator, try self.substitute(arg, subst));
                }
                return self.store.apply(new_func, new_args.items);
            },
            .lambda => {
                const bound_name = self.store.interner.resolve(node.payload);
                var it = subst.iterator();
                while (it.next()) |entry| {
                    if (entry.key_ptr.* < self.store.len()) {
                        const k_node = self.store.get(entry.key_ptr.*);
                        if (k_node.tag == .sym) {
                            const k_name = self.store.interner.resolve(k_node.payload);
                            if (std.mem.eql(u8, k_name, bound_name)) {
                                return id;
                            }
                        }
                    }
                }
                const old_body = node.span_a.slice(self.store.pool.items);
                var new_body = std.ArrayListUnmanaged(Id){};
                defer new_body.deinit(self.allocator);
                for (old_body) |child| {
                    try new_body.append(self.allocator, try self.substitute(child, subst));
                }
                const body_span = try self.store.pushSpan(new_body.items);
                return self.store.addNode(.{
                    .tag = .lambda,
                    .payload = node.payload,
                    .aux = 0,
                    .span_a = body_span,
                    .span_b = expr.Span.EMPTY,
                });
            },
            else => return id,
        }
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
