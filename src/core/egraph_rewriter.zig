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
    beta_reduced: std.AutoHashMapUnmanaged(Id, void) = .{},

    pub fn init(egraph: *EGraph, store: *Store, allocator: std.mem.Allocator) Rewriter {
        return .{
            .egraph = egraph,
            .store = store,
            .allocator = allocator,
            .match_cache = .{},
            .beta_reduced = .{},
        };
    }

    pub fn deinit(self: *Rewriter) void {
        self.match_cache.deinit(self.allocator);
        self.beta_reduced.deinit(self.allocator);
    }

    pub fn saturate(self: *Rewriter, budget_ms: u64) !u32 {
        //platform.debug.print("[Rewriter] saturate called\n", .{});
        const start = platform.time.milliTimestamp();
        var merge_count: u32 = 0;
        var iterations: u32 = 0;

        var rel_count: u32 = 0;
        for (0..self.store.len()) |i| {
            const node = self.store.get(@intCast(i));
            if (node.tag == .relation) rel_count += 1;
        }
        //platform.debug.print("[Rewriter] relations in store: {d}\n", .{rel_count});

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

                const eclass = &self.egraph.classes.items[canonical];

                //platform.debug.print("[Rewriter] class {d} nodes: ", .{canonical});
                for (eclass.nodes.items) |node_id| {
                    const node = self.store.get(node_id);
                    _ = node;
                    //platform.debug.print("{s} ", .{@tagName(node.tag)});
                }
                //platform.debug.print("\n", .{});

                // β‑réduction
                if (try self.applyBetaReduction(canonical)) |new_class| {
                    //platform.debug.print("[Rewriter] β‑réduction: new_class = {d}\n", .{new_class});
                    merge_count += 1;
                    try new_worklist.append(self.allocator, canonical);
                    try new_worklist.append(self.allocator, new_class);
                }

                // Règles utilisateur
                var rule_idx: u32 = 0;
                while (rule_idx < self.store.len()) : (rule_idx += 1) {
                    const rule_node = self.store.get(rule_idx);
                    if (rule_node.tag != .relation) continue;
                    // Le LHS est dans span_a, le RHS dans span_b
                    const lhs_span = rule_node.span_a.slice(self.store.pool.items);
                    const rhs_span = rule_node.span_b.slice(self.store.pool.items);
                    if (lhs_span.len != 1 or rhs_span.len != 1) continue;
                    const lhs_id = lhs_span[0];
                    const rhs_id = rhs_span[0];

                    const lhs_str = expr.toString(self.store, lhs_id, self.allocator) catch "?";
                    const rhs_str = expr.toString(self.store, rhs_id, self.allocator) catch "?";
                    //platform.debug.print("[Rewriter] rule {d}: {s} => {s}\n", .{ rule_idx, lhs_str, rhs_str });
                    defer self.allocator.free(lhs_str);
                    defer self.allocator.free(rhs_str);

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

                        // Vérifier si les classes sont déjà unifiées
                        const old_canonical = self.egraph.uf.find(canonical);
                        const old_new_class = self.egraph.uf.find(new_class);
                        if (old_canonical != old_new_class) {
                            const merged = try self.egraph.merge(canonical, new_class);
                            merge_count += 1;
                            try new_worklist.append(self.allocator, merged);
                            try new_worklist.append(self.allocator, canonical);
                            try new_worklist.append(self.allocator, new_class);
                            try self.egraph.addProof(.{
                                .rule_id = rule_idx,
                                .lhs = lhs_id,
                                .rhs = new_id,
                                .timestamp = @intCast(platform.time.milliTimestamp()),
                            });
                        } else {
                            // déjà fusionné, rien à faire
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
            const pattern_str = expr.toString(self.store, pattern_id, self.allocator) catch "?";
            const target_str = expr.toString(self.store, node_id, self.allocator) catch "?";
            //platform.debug.print("[matchPattern] comparing pattern: {s}  with target: {s}\n", .{ pattern_str, target_str });
            defer self.allocator.free(pattern_str);
            defer self.allocator.free(target_str);

            if (pattern.exprPatternMatch(self.store, pattern_id, node_id, bindings, self.allocator)) {
                //platform.debug.print("[matchPattern] MATCH SUCCESS\n", .{});
                return true;
            } else {
                //platform.debug.print("[matchPattern] MATCH FAILED\n", .{});
            }
        }
        return false;
    }

    fn applyBetaReduction(self: *Rewriter, class: ClassId) !?ClassId {
        //platform.debug.print("[applyBetaReduction] class {d}\n", .{class});
        const eclass = &self.egraph.classes.items[class];
        const pool = self.store.pool.items;
        for (eclass.nodes.items) |node_id| {
            // --- NOUVEAU : Ne pas réduire deux fois le même nœud ---
            if (self.beta_reduced.contains(node_id)) continue;
            // --------------------------------------------------------

            const node = self.store.get(node_id);
            //platform.debug.print("[applyBetaReduction] checking node {d} tag={s}\n", .{ node_id, @tagName(node.tag) });
            if (node.tag == .apply) {
                const func_id = node.payload;
                const func_node = self.store.get(func_id);
                //platform.debug.print("[applyBetaReduction] apply func {d} tag={s}\n", .{ func_id, @tagName(func_node.tag) });
                if (func_node.tag == .lambda) {
                    //platform.debug.print("[applyBetaReduction] found lambda application\n", .{});

                    // --- NOUVEAU : Marquer comme réduit AVANT de faire le travail ---
                    try self.beta_reduced.put(self.allocator, node_id, {});
                    // ----------------------------------------------------------------

                    const param_sym = func_node.payload;
                    const body_slice = func_node.span_a.slice(pool);
                    if (body_slice.len == 0) {
                        //platform.debug.print("[applyBetaReduction] body empty\n", .{});
                        continue;
                    }
                    const body = body_slice[0];
                    const args = node.span_a.slice(pool);
                    if (args.len < 2) {
                        //platform.debug.print("[applyBetaReduction] args len < 2\n", .{});
                        continue;
                    }
                    const actual_arg = args[1];
                    //platform.debug.print("[applyBetaReduction] param_sym={d}, body={d}, arg={d}\n", .{ param_sym, body, actual_arg });

                    // Construction manuelle du corps réduit
                    const body_node = self.store.get(body);
                    var new_body_id: ?Id = null;

                    if (body_node.tag == .apply) {
                        const body_func = self.store.get(body_node.payload);
                        if (body_func.tag == .sym) {
                            const op_name = self.store.interner.resolve(body_func.payload);
                            if (std.mem.eql(u8, op_name, "+") or std.mem.eql(u8, op_name, "*")) {
                                const args_body = body_node.span_a.slice(pool);
                                if (args_body.len == 2) {
                                    const a = args_body[0];
                                    const b = args_body[1];
                                    const a_node = self.store.get(a);
                                    const b_node = self.store.get(b);
                                    var new_a = a;
                                    var new_b = b;
                                    if (a_node.tag == .sym and a_node.payload == param_sym) {
                                        new_a = actual_arg;
                                    }
                                    if (b_node.tag == .sym and b_node.payload == param_sym) {
                                        new_b = actual_arg;
                                    }
                                    const op_sym = try self.store.sym(op_name);
                                    new_body_id = try self.store.apply(op_sym, &.{ new_a, new_b });
                                    //platform.debug.print("[applyBetaReduction] manual new_body={d}\n", .{new_body_id.?});
                                }
                            }
                        }
                    }

                    if (new_body_id == null) {
                        var subst = std.AutoHashMap(u32, Id).init(self.allocator);
                        defer subst.deinit();
                        try subst.put(param_sym, actual_arg);
                        new_body_id = try self.substitute(body, &subst);
                        //platform.debug.print("[applyBetaReduction] substitute new_body={d}\n", .{new_body_id.?});
                    }

                    const new_body = new_body_id.?;
                    const new_class = try self.egraph.addExpr(new_body);
                    const merged = try self.egraph.merge(class, new_class);

                    try self.egraph.addProof(.{
                        .rule_id = 0,
                        .lhs = node_id,
                        .rhs = new_body,
                        .timestamp = @intCast(platform.time.milliTimestamp()),
                    });

                    if (merged != class) {
                        //platform.debug.print("[applyBetaReduction] fusion réussie, retourne new_class={d}\n", .{new_class});
                    } else {
                        //platform.debug.print("[applyBetaReduction] classes déjà équivalentes, utilise new_class={d}\n", .{new_class});
                    }
                    return new_class;
                }
            }
        }
        return null;
    }

    fn substitute(self: *Rewriter, id: Id, subst: *const std.AutoHashMap(u32, Id)) !Id {
        const node = self.store.get(id);
        switch (node.tag) {
            .sym => {
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
                const bound_sym = node.payload;
                var new_subst = std.AutoHashMap(u32, Id).init(self.allocator);
                defer new_subst.deinit();
                var it = subst.iterator();
                while (it.next()) |entry| {
                    if (entry.key_ptr.* != bound_sym) {
                        try new_subst.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
                const old_body = node.span_a.slice(self.store.pool.items);
                var new_body = std.ArrayListUnmanaged(Id){};
                defer new_body.deinit(self.allocator);
                for (old_body) |child| {
                    try new_body.append(self.allocator, try self.substitute(child, &new_subst));
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
