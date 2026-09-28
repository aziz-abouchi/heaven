//! cas.zig — Opérations CAS (simplify, egraph) de Commands (D4 batch 3).
//! Extraites de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const canon_mod = @import("canon");
const egraph_mod = @import("egraph");
const transform_mod = @import("transform");
const pattern_mod = @import("pattern");
const math_mod = @import("math");
const rules_mod = @import("rules");
const simplify_engine_mod = @import("simplify_engine");
const platform = @import("platform");

// Réexport local de HeavenError (défini dans commands.zig).
// On utilise anyerror pour les retours qui étaient HeavenError![]u8,
// le wrapper côté commands.zig fait la conversion.
pub const HeavenError = error{
    ExtensionNotLowered, EvaluationFailed, OutOfMemory, InvalidInput,
    UnsupportedExpr, UnknownVariable, TypeMismatch, InvalidSyntax, TypeError,
    ArityMismatch, StackOverflow, NotSupported, InputOutput, Unexpected,
};

const Store = expr.Store;
const Id = expr.Id;

pub fn simplifyToId(cmds: anytype, input: []const u8) !Id {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return error.InvalidInput;
    const raw_id = try cmds.parseExpression(trimmed);
    const id = try cmds.ensureLowered(raw_id);
    const after_basic = try cmds.math.simplifyBasic(id);
    const after_egraph = try cmds.simplify_eng.simplifyWithEGraph(after_basic, null, null);
    return try cmds.math.simplifyBasic(after_egraph);
}

// ─── Eval dispatcher ───

pub fn evalSimplify(cmds: anytype, input: []const u8) anyerror![]u8 {
    const trimmed = std.mem.trim(u8, input, " \t");
    if (trimmed.len == 0) return cmds.allocator.dupe(u8, "usage: simplify <expr>");

    const raw_id = cmds.parseExpression(trimmed) catch try cmds.bridge.importExpr(trimmed);
    const id = try cmds.store.lowerRec(raw_id);

    // Aligné sur Heaven.simplify : TOUJOURS passer par l'EGraph
    const after_basic = try cmds.math.simplifyBasic(id);
    const after_egraph = try cmds.simplify_eng.simplifyWithEGraph(after_basic, null, null);
    const final = try cmds.math.simplifyBasic(after_egraph);
    return expr.toStringInfix(cmds.store, final, cmds.allocator);
}

pub fn simplify(cmds: anytype, input: []const u8) ![]u8 {
    // Normalise l'infixe en S-expr avant parse.
    // Sans ça, "(x + 0) + 0" est mal parsé par parseExpression,
    // qui ne route vers nativeToSExpr que si la chaîne ne commence
    // PAS par '('.
    var arena = std.heap.ArenaAllocator.init(cmds.allocator);
    defer arena.deinit();
    const to_parse = expr.nativeToSExpr(input, arena.allocator()) catch input;

    const id = try cmds.parseExpression(to_parse);
    const debug_str = try expr.toStringInfix(cmds.store, id, cmds.allocator);
    defer cmds.allocator.free(debug_str);
    platform.dbg("[core.commands.simplify] input: {s}\n", .{debug_str});

    // Pipeline : réécriture directe (rules.zig) → E-Graph → nettoyage
    var current = id;

    // 1. Réécriture directe à point fixe via le module rules
    var changed = true;
    var iterations: u32 = 0;
    while (changed and iterations < 50) : (iterations += 1) {
        changed = false;
        if (try rules_mod.applyFirstRule(cmds.store, cmds.kb.rules.items, current, cmds.allocator)) |match| {
            current = match.new_id;
            changed = true;
        }
    }

    // 2. E-Graph pour les cas complexes (distributivité/factorisation croisées)
    const after_egraph = try cmds.simplify_eng.simplifyWithEGraph(current, null, null);

    // 3. Nettoyage final (identités 0/1, constant folding)
    const simplified = try cmds.math.simplifyBasic(after_egraph);

    return expr.toStringInfix(cmds.store, simplified, cmds.allocator);
}

pub fn simplifyWithEGraph(cmds: anytype, id: Id, qtt: ?*egraph_mod.QttCost) !Id {
    if (cmds.kb.rules.items.len == 0) return id;
    var egraph = egraph_mod.EGraph.init(cmds.store, cmds.allocator);
    defer egraph.deinit();
    const root_class = try egraph.addExpr(id);
    var changed = true;
    var iters: u32 = 0;
    while (changed and iters < 8) : (iters += 1) {
        changed = false;
        for (cmds.kb.rules.items) |rule_id| {
            if (rule_id >= cmds.store.len()) continue;
            const rule_node = cmds.store.get(rule_id);
            if (rule_node.tag != .relation) continue;
            const lhs_rhs = rule_node.span_a.slice(cmds.store.pool.items);
            if (lhs_rhs.len != 2) continue;
            const lhs_id = lhs_rhs[0];
            const rhs_id = lhs_rhs[1];
            var i: u32 = 0;
            while (i < egraph.classes.items.len) : (i += 1) {
                const eclass = &egraph.classes.items[i];
                for (eclass.nodes.items) |node_id| {
                    var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
                    defer bindings.deinit(cmds.allocator);
                    if (pattern_mod.exprPatternMatch(cmds.store, lhs_id, node_id, &bindings, cmds.allocator)) {
                        const new_id = pattern_mod.substitutePattern(cmds.store, rhs_id, &bindings, cmds.allocator) catch continue;
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

pub fn simplifyRec(cmds: anytype, id: Id, depth: u32) !Id {
    if (depth > 50) return id;
    if (id >= cmds.store.len()) return id;
    const node = cmds.store.get(id);
    var current = id;

    if (node.tag == .apply) {
        const func_id = node.payload;
        const args_span = node.span_a;
        // span_a = [func, arg0, arg1, ...] — on saute [0] (= func).
        const all_args = args_span.slice(cmds.store.pool.items);
        const old_args = if (all_args.len >= 1 and all_args[0] == node.payload)
            all_args[1..]
        else
            all_args;
        if (old_args.len == 2) {
            const arg0 = old_args[0];
            const arg1 = old_args[1];

            const new_func = try simplifyRec(cmds, func_id, depth + 1);
            const new_l = try simplifyRec(cmds, arg0, depth + 1);
            const new_r = try simplifyRec(cmds, arg1, depth + 1);

            if (new_func < cmds.store.len()) {
                const func_node = cmds.store.get(new_func);
                if (func_node.tag == .sym) {
                    const op_name = cmds.store.interner.resolve(func_node.payload);
                    current = try cmds.store.binop(op_name, new_l, new_r);
                }
            }
        }
    }

    var changed = true;
    var iterations: u32 = 0;
    while (changed and iterations < 10) : (iterations += 1) {
        changed = false;
        if (current >= cmds.store.len()) break;

        const canon_current = try canon_mod.canonicalize(cmds.store, cmds.allocator, current);

        for (cmds.kb.rules.items) |rule_id| {
            if (rule_id >= cmds.store.len()) continue;
            const rule_node = cmds.store.get(rule_id);
            if (rule_node.tag != .relation) continue;
            const lhs_rhs = rule_node.span_a.slice(cmds.store.pool.items);
            if (lhs_rhs.len != 2) continue;
            const lhs_id = lhs_rhs[0];
            const rhs_id = lhs_rhs[1];

            var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
            defer bindings.deinit(cmds.allocator);

            if (pattern_mod.exprPatternMatch(cmds.store, lhs_id, canon_current, &bindings, cmds.allocator)) {
                const new_id = try pattern_mod.substitutePattern(cmds.store, rhs_id, &bindings, cmds.allocator);
                if (new_id < cmds.store.len()) {
                    current = new_id;
                    changed = true;
                    break;
                }
            }
        }
    }

    if (current < cmds.store.len()) {
        cmds.engine.fuel = 100;
        const folded = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, current, 0) catch current;
        if (folded != current and folded < cmds.store.len()) {
            const folded_node = cmds.store.get(folded);
            if (folded_node.tag == .lit and cmds.simplify_eng.isFullyNumeric(current)) return folded;
        }
    }
    return current;
}

pub fn isFullyNumeric(cmds: anytype, id: Id) bool {
    if (id >= cmds.store.len()) return false;
    const node = cmds.store.get(id);
    return switch (node.tag) {
        .lit => true,
        .sym => false,
        .apply => {
            const args = node.span_a.slice(cmds.store.pool.items);
            for (args) |a| {
                if (!cmds.simplify_eng.isFullyNumeric(a)) return false;
            }
            return true;
        },
        else => false,
    };
}

pub fn simplifyOnePass(cmds: anytype, id: Id, buf: *std.ArrayListUnmanaged(u8), step: *u32) !Id {
    if (id >= cmds.store.len()) return id;
    const node = cmds.store.get(id);
    var current = id;
    if (node.tag == .apply) {
        const func_id = node.payload;
        const args_span = node.span_a;
        const old_args = args_span.slice(cmds.store.pool.items);
        if (old_args.len == 2) {
            const arg0 = old_args[0];
            const arg1 = old_args[1];
            const new_l = try cmds.simplify_eng.simplifyOnePass(arg0, buf, step);
            const new_r = try cmds.simplify_eng.simplifyOnePass(arg1, buf, step);
            if (new_l != arg0 or new_r != arg1) {
                if (func_id < cmds.store.len()) {
                    const func_node = cmds.store.get(func_id);
                    if (func_node.tag == .sym) {
                        const op_name = cmds.store.interner.resolve(func_node.payload);
                        current = try cmds.store.binop(op_name, new_l, new_r);
                    }
                }
            }
        }
    }
    if (current >= cmds.store.len()) return current;
    for (cmds.kb.rules.items) |rule_id| {
        if (rule_id >= cmds.store.len()) continue;
        const rule_node = cmds.store.get(rule_id);
        if (rule_node.tag != .relation) continue;
        const lhs_rhs = rule_node.span_a.slice(cmds.store.pool.items);
        if (lhs_rhs.len != 2) continue;
        const lhs_id = lhs_rhs[0];
        const rhs_id = lhs_rhs[1];
        var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
        defer bindings.deinit(cmds.allocator);
        if (pattern_mod.exprPatternMatch(cmds.store, lhs_id, current, &bindings, cmds.allocator)) {
            const new_id = pattern_mod.substitutePattern(cmds.store, rhs_id, &bindings, cmds.allocator) catch continue;
            if (new_id < cmds.store.len() and new_id != current) {
                const lhs_str = expr.toString(cmds.store, lhs_id, cmds.allocator) catch continue;
                defer cmds.allocator.free(lhs_str);
                const rhs_str = expr.toString(cmds.store, rhs_id, cmds.allocator) catch continue;
                defer cmds.allocator.free(rhs_str);
                const new_str = expr.toString(cmds.store, new_id, cmds.allocator) catch continue;
                defer cmds.allocator.free(new_str);
                var tmp: [16]u8 = undefined;
                const sn = std.fmt.bufPrint(&tmp, "  step {d}: ", .{step.*}) catch "  step ?: ";
                buf.appendSlice(cmds.allocator, sn) catch continue;
                buf.appendSlice(cmds.allocator, new_str) catch continue;
                buf.appendSlice(cmds.allocator, "  [") catch continue;
                buf.appendSlice(cmds.allocator, lhs_str) catch continue;
                buf.appendSlice(cmds.allocator, " → ") catch continue;
                buf.appendSlice(cmds.allocator, rhs_str) catch continue;
                buf.appendSlice(cmds.allocator, "]\n") catch continue;
                step.* += 1;
                return new_id;
            }
        }
    }
    if (current < cmds.store.len()) {
        cmds.engine.fuel = 100;
        const folded = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, current, 0) catch current;
        if (folded != current and folded < cmds.store.len()) {
            const folded_node = cmds.store.get(folded);
            if (folded_node.tag == .lit) {
                const old_str = expr.toString(cmds.store, current, cmds.allocator) catch return current;
                defer cmds.allocator.free(old_str);
                const new_str = expr.toString(cmds.store, folded, cmds.allocator) catch return current;
                defer cmds.allocator.free(new_str);
                var tmp: [16]u8 = undefined;
                const sn = std.fmt.bufPrint(&tmp, " step {d}: ", .{step.*}) catch " step ?: ";
                buf.appendSlice(cmds.allocator, sn) catch {};
                buf.appendSlice(cmds.allocator, new_str) catch {};
                buf.appendSlice(cmds.allocator, " [eval ") catch {};
                buf.appendSlice(cmds.allocator, old_str) catch {};
                buf.appendSlice(cmds.allocator, "]\n") catch {};
                step.* += 1;
                return folded;
            }
        }
    }
    return current;
}

