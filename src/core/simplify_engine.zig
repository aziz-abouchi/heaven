//! Moteur de simplification pour Heaven
//! Extrait de commands.zig pour modularité
const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
const transform_mod = @import("transform");
const pattern_mod = @import("pattern");
const egraph_mod = @import("egraph");
const egraph_rewriter_mod = @import("egraph_rewriter");
const canon_mod = @import("canon");
const platform = @import("platform");
const types = @import("types");

pub const SimplifyEngine = struct {
    store: *Store,
    engine: *engine_expr.Engine,
    env: *engine_expr.Env,
    kb: *transform_mod.KnowledgeBase,
    allocator: Allocator,

    pub fn init(
        store: *Store,
        engine: *engine_expr.Engine,
        env: *engine_expr.Env,
        kb: *transform_mod.KnowledgeBase,
        allocator: Allocator,
    ) SimplifyEngine {
        return .{
            .store = store,
            .engine = engine,
            .env = env,
            .kb = kb,
            .allocator = allocator,
        };
    }

    pub fn isFullyNumeric(self: *SimplifyEngine, id: Id) bool {
        if (id >= self.store.len()) return false;
        const node = self.store.get(id);
        return switch (node.tag) {
            .lit => true,
            .sym => false,
            .apply => {
                const args = node.span_a.slice(self.store.pool.items);
                for (args) |a| {
                    if (!self.isFullyNumeric(a)) return false;
                }
                return true;
            },
            else => false,
        };
    }

    pub fn simplifyOnePass(self: *SimplifyEngine, id: Id, buf: *std.ArrayListUnmanaged(u8), step: *u32) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        var current = id;
        if (node.tag == .apply) {
            const func_id = node.payload;
            const args_span = node.span_a;
            const old_args = args_span.slice(self.store.pool.items);
            if (old_args.len == 2) {
                const arg0 = old_args[0];
                const arg1 = old_args[1];
                const new_l = try self.simplifyOnePass(arg0, buf, step);
                const new_r = try self.simplifyOnePass(arg1, buf, step);
                if (new_l != arg0 or new_r != arg1) {
                    if (func_id < self.store.len()) {
                        const func_node = self.store.get(func_id);
                        if (func_node.tag == .sym) {
                            const op_name = self.store.interner.resolve(func_node.payload);
                            current = try self.store.binop(op_name, new_l, new_r);
                        }
                    }
                }
            }
        }
        if (current >= self.store.len()) return current;
        for (self.kb.rules.items) |rule_id| {
            if (rule_id >= self.store.len()) continue;
            const rule_node = self.store.get(rule_id);
            if (rule_node.tag != .relation) continue;
            const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
            if (lhs_rhs.len != 2) continue;
            const lhs_id = lhs_rhs[0];
            const rhs_id = lhs_rhs[1];
            var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
            defer bindings.deinit(self.allocator);
            if (pattern_mod.exprPatternMatch(self.store, lhs_id, current, &bindings, self.allocator)) {
                const new_id = pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator) catch continue;
                if (new_id < self.store.len() and new_id != current) {
                    const lhs_str = expr.toString(self.store, lhs_id, self.allocator) catch continue;
                    defer self.allocator.free(lhs_str);
                    const rhs_str = expr.toString(self.store, rhs_id, self.allocator) catch continue;
                    defer self.allocator.free(rhs_str);
                    const new_str = expr.toString(self.store, new_id, self.allocator) catch continue;
                    defer self.allocator.free(new_str);
                    var tmp: [16]u8 = undefined;
                    const sn = std.fmt.bufPrint(&tmp, "  step {d}: ", .{step.*}) catch "  step ?: ";
                    buf.appendSlice(self.allocator, sn) catch continue;
                    buf.appendSlice(self.allocator, new_str) catch continue;
                    buf.appendSlice(self.allocator, "  [") catch continue;
                    buf.appendSlice(self.allocator, lhs_str) catch continue;
                    buf.appendSlice(self.allocator, " → ") catch continue;
                    buf.appendSlice(self.allocator, rhs_str) catch continue;
                    buf.appendSlice(self.allocator, "]\n") catch continue;
                    step.* += 1;
                    return new_id;
                }
            }
        }
        if (current < self.store.len()) {
            self.engine.fuel = 100;
            const folded = engine_expr.evaluate(self.store, self.env, self.engine, current, 0) catch current;
            if (folded != current and folded < self.store.len()) {
                const folded_node = self.store.get(folded);
                if (folded_node.tag == .lit) {
                    const old_str = expr.toString(self.store, current, self.allocator) catch return current;
                    defer self.allocator.free(old_str);
                    const new_str = expr.toString(self.store, folded, self.allocator) catch return current;
                    defer self.allocator.free(new_str);
                    var tmp: [16]u8 = undefined;
                    const sn = std.fmt.bufPrint(&tmp, " step {d}: ", .{step.*}) catch " step ?: ";
                    buf.appendSlice(self.allocator, sn) catch {};
                    buf.appendSlice(self.allocator, new_str) catch {};
                    buf.appendSlice(self.allocator, " [eval ") catch {};
                    buf.appendSlice(self.allocator, old_str) catch {};
                    buf.appendSlice(self.allocator, "]\n") catch {};
                    step.* += 1;
                    return folded;
                }
            }
        }
        return current;
    }

    pub fn simplifyRec(self: *SimplifyEngine, id: Id, depth: u32) !Id {
        platform.dbg("[src/core/simplify_engine.zig simplifyRec] called with id={d}, depth={d}\n", .{ id, depth });
        if (depth > 50) return id;
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        var current = id;
        if (node.tag == .apply) {
            const pool = self.store.pool.items;
            const old_children = node.span_a.slice(pool);
            if (old_children.len >= 2) {
                const func_id = old_children[0];
                const new_func = try self.simplifyRec(func_id, depth + 1);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                var changed = false;
                for (old_children[1..]) |child| {
                    const new_child = try self.simplifyRec(child, depth + 1);
                    try new_args.append(self.allocator, new_child);
                    if (new_child != child) changed = true;
                }
                if (changed or new_func != func_id) {
                    current = try self.store.apply(new_func, new_args.items);
                }
            }
        }
        // Appliquer les règles jusqu'à saturation
        var changed = true;
        var iterations: u32 = 0;
        while (changed and iterations < 10) : (iterations += 1) {
            changed = false;
            if (current >= self.store.len()) break;
            for (self.kb.rules.items) |rule_id| {
                if (rule_id >= self.store.len()) continue;
                const rule_node = self.store.get(rule_id);
                if (rule_node.tag != .relation) continue;
                const lhs_span = rule_node.span_a.slice(self.store.pool.items);
                const rhs_span = rule_node.span_b.slice(self.store.pool.items);
                if (lhs_span.len != 1 or rhs_span.len != 1) continue;
                const lhs_id = lhs_span[0];
                const rhs_id = rhs_span[0];
                var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
                defer bindings.deinit(self.allocator);
                //platform.dbg("[simplifyRec] trying rule {d}: lhs={d}, rhs={d} on current={d}\n", .{ rule_id, lhs_id, rhs_id, current });
                if (pattern_mod.exprPatternMatch(self.store, lhs_id, current, &bindings, self.allocator)) {
                    const new_id = try pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator);
                    if (new_id < self.store.len() and new_id != current) {
                        platform.dbg("[simplifyRec] applying rule, new_id={d}\n", .{new_id});
                        current = new_id;
                        changed = true;
                        break;
                    }
                }
            }
        }
        return current;
    }

    pub fn evaluateLiteral(self: *SimplifyEngine, id: Id) ?Id {
        if (id >= self.store.len()) return null;
        const node = self.store.get(id);

        switch (node.tag) {
            .lit => return id,
            .sym => return null,
            .apply => {
                const args = node.span_a.slice(self.store.pool.items);
                if (args.len < 3) return null;

                const func_id = args[0];
                if (func_id >= self.store.len()) return null;
                const func_node = self.store.get(func_id);
                if (func_node.tag != .sym) return null;

                const op_name = self.store.interner.resolve(func_node.payload);

                const left_lit = self.evaluateLiteral(args[1]) orelse return null;
                const right_lit = self.evaluateLiteral(args[2]) orelse return null;

                const left_node = self.store.get(left_lit);
                const right_node = self.store.get(right_lit);

                if (left_node.tag != .lit or right_node.tag != .lit) return null;

                const left_val = self.store.lits.items[left_node.aux];
                const right_val = self.store.lits.items[right_node.aux];

                if (left_val != .int or right_val != .int) return null;

                var result: i64 = 0;
                if (std.mem.eql(u8, op_name, "+")) {
                    result = left_val.int + right_val.int;
                } else if (std.mem.eql(u8, op_name, "*")) {
                    result = left_val.int * right_val.int;
                } else if (std.mem.eql(u8, op_name, "-")) {
                    result = left_val.int - right_val.int;
                } else if (std.mem.eql(u8, op_name, "/")) {
                    if (right_val.int == 0) return null;
                    result = @divTrunc(left_val.int, right_val.int);
                } else {
                    return null;
                }

                return self.store.lit(.{ .int = result }) catch null;
            },
            else => return null,
        }
    }

    pub fn simplifyWithEGraph(self: *SimplifyEngine, id: Id, qtt: ?*egraph_mod.QttCost, type_env: ?*types.TypeEnv) !Id {
        platform.dbg("[SimplifyEngine] kb.rules.len = {d}\n", .{self.kb.rules.items.len});
        if (id >= self.store.len()) {
            platform.dbg("[EGraph] ID invalide: {} >= store.len() = {}\n", .{ id, self.store.len() });
            return id;
        }

        const node = self.store.get(id);
        const tag_int = @intFromEnum(node.tag);
        platform.dbg("[EGraph] node tag int = {d}\n", .{tag_int});
        if (tag_int < @intFromEnum(expr.Tag.relation) + 1) {
            const tag = @as(expr.Tag, @enumFromInt(tag_int));
            platform.dbg("[EGraph] node tag = {s}\n", .{@tagName(tag)});
        } else {
            return id;
        }

        if (!node.tag.isPrimitive()) {
            const lowered = try self.store.lowerRec(id);
            if (!self.store.get(lowered).tag.isPrimitive()) return id;
            return self.simplifyWithEGraph(lowered, qtt, null);
        }

        var egraph = egraph_mod.EGraph.init(self.store, self.allocator);
        defer egraph.deinit();

        const root_class = try egraph.addExpr(id);

        var rewriter = egraph_rewriter_mod.Rewriter.init(&egraph, self.store, self.allocator);
        defer rewriter.deinit();

        const merges = try rewriter.saturate(10000);
        platform.dbg("[EGraph] saturation: {} merges\n", .{merges});

        const extracted = if (type_env) |tenv| blk: {
            var mem_cost = egraph_mod.MemoryCost{
                .type_env = tenv,
                .allocator = self.allocator,
                .cache = std.AutoHashMap(Id, types.Type).init(self.allocator),
            };
            defer mem_cost.cache.deinit();
            defer mem_cost.cache.deinit();
            const cost_fn = struct {
                fn cost(store: *const expr.Store, node_id: expr.Id, ctx: ?*anyopaque) u32 {
                    const mc = @as(*egraph_mod.MemoryCost, @ptrCast(@alignCast(ctx orelse unreachable)));
                    return mc.total(store, node_id);
                }
            }.cost;
            break :blk egraph.extractWithContext(root_class, cost_fn, &mem_cost) orelse id;
        } else blk: {
            // Utiliser la fonction de coût par nombre de nœuds (définie plus bas)
            break :blk egraph.extractWithContext(root_class, nodeCountCost, null) orelse id;
        };

        // --- NOUVEAU : Évaluer avec l'évaluateur de littéraux ---
        const root_canonical = egraph.uf.find(root_class);
        if (root_canonical < egraph.classes.items.len) {
            const eclass = &egraph.classes.items[root_canonical];
            for (eclass.nodes.items) |node_id| {
                if (self.evaluateLiteral(node_id)) |lit_id| {
                    return lit_id;
                }
            }
        }

        return extracted;
    }
};

fn nodeCountCost(store: *const expr.Store, id: expr.Id, ctx: ?*anyopaque) u32 {
    _ = ctx;
    const node = store.get(id);
    var count: u32 = 1;
    switch (node.tag) {
        .apply => {
            count += nodeCountCost(store, node.payload, null);
            for (node.span_a.slice(store.pool.items)) |child| {
                count += nodeCountCost(store, child, null);
            }
        },
        .bind, .lambda, .relation => {
            for (node.span_a.slice(store.pool.items)) |child| {
                count += nodeCountCost(store, child, null);
            }
        },
        else => {},
    }
    return count;
}
