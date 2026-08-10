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
        if (depth > 50) return id;
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
                const new_func = try self.simplifyRec(func_id, depth + 1);
                const new_l = try self.simplifyRec(arg0, depth + 1);
                const new_r = try self.simplifyRec(arg1, depth + 1);
                if (new_func < self.store.len()) {
                    const func_node = self.store.get(new_func);
                    if (func_node.tag == .sym) {
                        const op_name = self.store.interner.resolve(func_node.payload);
                        current = try self.store.binop(op_name, new_l, new_r);
                    }
                }
            }
        }
        var changed = true;
        var iterations: u32 = 0;
        while (changed and iterations < 10) : (iterations += 1) {
            changed = false;
            if (current >= self.store.len()) break;
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
                if (pattern_mod.exprPatternMatch(self.store, lhs_id, id, &bindings, self.allocator)) {
                    const new_id = try pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator);
                    if (new_id < self.store.len()) {
                        current = new_id;
                        changed = true;
                        break;
                    }
                }
            }
        }
        if (current < self.store.len()) {
            self.engine.fuel = 100;
            const folded = engine_expr.evaluate(self.store, self.env, self.engine, current, 0) catch current;
            if (folded != current and folded < self.store.len()) {
                const folded_node = self.store.get(folded);
                if (folded_node.tag == .lit and self.isFullyNumeric(current)) return folded;
            }
        }
        return current;
    }

    pub fn simplifyWithEGraph(self: *SimplifyEngine, id: Id, qtt: ?*egraph_mod.QttCost) !Id {
        if (self.kb.rules.items.len == 0) return id;
        var egraph = egraph_mod.EGraph.init(self.store, self.allocator);
        defer egraph.deinit();
        const root_class = try egraph.addExpr(id);
        var changed = true;
        var iters: u32 = 0;
        while (changed and iters < 8) : (iters += 1) {
            changed = false;
            for (self.kb.rules.items) |rule_id| {
                if (rule_id >= self.store.len()) continue;
                const rule_node = self.store.get(rule_id);
                if (rule_node.tag != .relation) continue;
                const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
                if (lhs_rhs.len != 2) continue;
                const lhs_id = lhs_rhs[0];
                const rhs_id = lhs_rhs[1];
                var i: u32 = 0;
                while (i < egraph.classes.items.len) : (i += 1) {
                    const eclass = &egraph.classes.items[i];
                    for (eclass.nodes.items) |node_id| {
                        var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
                        defer bindings.deinit(self.allocator);
                        if (pattern_mod.exprPatternMatch(self.store, lhs_id, node_id, &bindings, self.allocator)) {
                            const new_id = pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator) catch continue;
                            const new_class = try egraph.addExpr(new_id);
                            const merged = try egraph.merge(i, new_class);
                            if (merged != i) changed = true;
                        }
                    }
                }
            }
        }
        return egraph.extract(root_class, qtt) orelse id;
    }
};
