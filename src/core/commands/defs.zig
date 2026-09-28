//! defs.zig — Définitions (let, fn, actor, macro) de Commands (D4 batch 4).
//! Extraites de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const canon_mod = @import("canon");
const egraph_mod = @import("egraph");
const pattern_mod = @import("pattern");
const math_mod = @import("math");
const transform_mod = @import("transform");
const platform = @import("platform");

const Store = expr.Store;
const Id = expr.Id;

pub fn define(cmds: anytype, name: []const u8, value_text: []const u8) anyerror![]u8 {
    const val_id = try cmds.bridge.importExpr(value_text);
    cmds.engine.fuel = 10_000;
    const evaled = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, val_id, 0) catch val_id;
    const bind_id = try cmds.store.bind(name, evaled);
    try cmds.env.put(try cmds.store.interner.intern(name), evaled);
    return expr.toString(cmds.store, bind_id, cmds.allocator);
}

pub fn evalActorDef(cmds: anytype, input: []const u8, env: *engine_expr.Env) anyerror![]u8 {
    const with_pos = std.mem.indexOf(u8, input, " with ") orelse
        return cmds.allocator.dupe(u8, "syntax error: missing 'with'");

    const lhs = std.mem.trim(u8, input[0..with_pos], " ");
    const rhs = std.mem.trim(u8, input[with_pos + 6 ..], " ");

    const eq_pos = std.mem.indexOfScalar(u8, lhs, '=') orelse
        return cmds.allocator.dupe(u8, "syntax error: missing '='");

    const name = std.mem.trim(u8, lhs[0..eq_pos], " ");
    const init_state_str = std.mem.trim(u8, lhs[eq_pos + 1 ..], " ");

    const init_state_id = try cmds.bridge.importExpr(init_state_str);
    const lowered_state = try cmds.store.lowerRec(init_state_id);

    const handler_id = if (std.mem.indexOf(u8, rhs, "=>") != null) blk: {
        break :blk cmds.parser.parseLambda(rhs) catch {
            return cmds.allocator.dupe(u8, "syntax error in actor handler");
        };
    } else blk: {
        if (cmds.engine.fns.get(rhs) == null) {
            return std.fmt.allocPrint(cmds.allocator, "Error: function '{s}' not found for actor handler", .{rhs});
        }
        break :blk try cmds.store.sym(rhs);
    };

    const new_actor_id = cmds.engine.next_actor_id;
    cmds.engine.next_actor_id += 1;
    try cmds.engine.actors.put(cmds.engine.allocator, new_actor_id, .{
        .state = lowered_state,
        .handler = handler_id,
    });
    const actor_id = try cmds.store.int(@intCast(new_actor_id));

    const actor_sym = try cmds.store.interner.intern(name);
    try env.put(actor_sym, actor_id);

    return std.fmt.allocPrint(cmds.allocator, "actor {s} spawned (id: {d})", .{ name, actor_id });
}

pub fn evalMacroDef(cmds: anytype, input: []const u8) anyerror![]u8 {
    const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse return cmds.allocator.dupe(u8, "syntax error: missing '='");
    const lhs = std.mem.trim(u8, input[0..eq_pos], " ");
    const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

    const paren_pos = std.mem.indexOfScalar(u8, lhs, '(') orelse return cmds.allocator.dupe(u8, "syntax error: missing '('");
    if (lhs[lhs.len - 1] != ')') return cmds.allocator.dupe(u8, "syntax error: missing ')'");

    const name = std.mem.trim(u8, lhs[0..paren_pos], " ");
    const params_str = std.mem.trim(u8, lhs[paren_pos + 1 .. lhs.len - 1], " ");

    var param_ids: std.ArrayListUnmanaged(Id) = .{};
    defer param_ids.deinit(cmds.allocator);
    var it = std.mem.tokenizeAny(u8, params_str, " ,");
    while (it.next()) |p| {
        try param_ids.append(cmds.allocator, try cmds.store.sym(p));
    }
    const params_span = try cmds.store.pushSpan(param_ids.items);

    const body_id = try cmds.parser.parseSExpr(rhs);

    const name_sym = try cmds.store.interner.intern(name);
    try cmds.engine.macros.put(cmds.allocator, name_sym, .{ .params_span = params_span, .body = body_id });

    return std.fmt.allocPrint(cmds.allocator, "macro {s} defined", .{name});
}

pub fn parseLambdaShortcut(cmds: anytype, name: []const u8, expr_str: []const u8) anyerror![]u8 {
    const open = std.mem.indexOfScalar(u8, expr_str, '(') orelse return cmds.allocator.dupe(u8, "syntax error: missing '(' in fn");
    const close = std.mem.indexOfScalar(u8, expr_str, ')') orelse return cmds.allocator.dupe(u8, "syntax error: missing ')' in fn");

    const params_str = expr_str[open + 1 .. close];
    var rest = std.mem.trim(u8, expr_str[close + 1 ..], " \t");
    if (std.mem.startsWith(u8, rest, "=>")) {
        rest = std.mem.trim(u8, rest[2..], " \t");
    }

    const fn_def_str = try std.fmt.allocPrint(cmds.allocator, "{s} {s} = {s}", .{ name, params_str, rest });
    defer cmds.allocator.free(fn_def_str);
    return evalFnDef(cmds, fn_def_str);
}

pub fn evalFnDef(cmds: anytype, input: []const u8) anyerror![]u8 {
    const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse return cmds.allocator.dupe(u8, "syntax error: missing '='");
    if (eq_pos + 1 < input.len and input[eq_pos + 1] == '=') return cmds.allocator.dupe(u8, "syntax error: use single '='");
    var lhs = std.mem.trim(u8, input[0..eq_pos], " ");
    const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

    if (lhs.len > 0 and lhs[lhs.len - 1] == ':') {
        lhs = std.mem.trim(u8, lhs[0 .. lhs.len - 1], " ");
    }

    if (std.mem.startsWith(u8, lhs, "fn ")) lhs = std.mem.trim(u8, lhs[3..], " ");
    if (std.mem.startsWith(u8, lhs, "let ")) lhs = std.mem.trim(u8, lhs[4..], " ");

    if (std.mem.startsWith(u8, rhs, "fn ") or std.mem.startsWith(u8, rhs, "fn(")) {
        const name = if (std.mem.indexOfScalar(u8, lhs, ' ')) |space| lhs[0..space] else lhs;
        return parseLambdaShortcut(cmds, name, rhs);
    }

    var owned_lhs: ?[]u8 = null;
    defer if (owned_lhs) |s| cmds.allocator.free(s);
    if (std.mem.indexOfScalar(u8, lhs, '(') != null) {
        const open = std.mem.indexOfScalar(u8, lhs, '(') orelse return cmds.allocator.dupe(u8, "syntax error");
        const close = std.mem.indexOfScalar(u8, lhs, ')') orelse return cmds.allocator.dupe(u8, "syntax error");
        if (close != lhs.len - 1) return cmds.allocator.dupe(u8, "syntax error: unexpected chars after )");
        const name = std.mem.trim(u8, lhs[0..open], " ");
        const params_str = lhs[open + 1 .. close];

        var converted = std.ArrayListUnmanaged(u8){};
        try converted.appendSlice(cmds.allocator, name);
        var it = std.mem.tokenizeAny(u8, params_str, " ,");
        while (it.next()) |p| {
            try converted.append(cmds.allocator, ' ');
            try converted.appendSlice(cmds.allocator, p);
        }
        owned_lhs = try converted.toOwnedSlice(cmds.allocator);
        lhs = owned_lhs.?;
    }

    const wrapped_lhs = try std.fmt.allocPrint(cmds.allocator, "({s})", .{lhs});
    defer cmds.allocator.free(wrapped_lhs);

    const lhs_id = cmds.parser.parseSExpr(wrapped_lhs) catch {
        return cmds.allocator.dupe(u8, "syntax error in lhs");
    };

    const lhs_node = cmds.store.get(lhs_id);

    if (lhs_node.tag == .sym) {
        const name = cmds.store.interner.resolve(lhs_node.payload);
        const body_id = cmds.parseExpression(rhs) catch return cmds.allocator.dupe(u8, "parse error in body");

        var def: engine_expr.FunctionDef = .{
            .clauses = undefined,
            .num_clauses = 1,
            .ctor_arity = null, // ← explicite
        };
        def.clauses[0] = .{ .patterns = .{0} ** 8, .num_patterns = 0, .body = body_id };

        const owned_name = try cmds.engine.allocator.dupe(u8, name);
        platform.dbg("[fns.put] site=1 name='{s}' key_addr={d}\n", .{ name, @intFromPtr(owned_name.ptr) });
        cmds.engine.fns.put(cmds.engine.allocator, owned_name, def) catch |err| {
            return std.fmt.allocPrint(cmds.engine.allocator, "registration error: {s}", .{@errorName(err)});
        };

        const name_sym = try cmds.store.interner.intern(name);
        const name_sym_id = try cmds.store.sym(name);
        try cmds.env.put(name_sym, name_sym_id);

        return std.fmt.allocPrint(cmds.allocator, "{s} defined", .{name});
    }

    if (lhs_node.tag == .apply) {
        const func_sym_node = cmds.store.get(lhs_node.payload);
        if (func_sym_node.tag != .sym) return cmds.allocator.dupe(u8, "syntax error: function name must be a symbol");
        const name = cmds.store.interner.resolve(func_sym_node.payload);

        const pool = cmds.store.pool.items;
        const arg_span = lhs_node.span_a.slice(pool);
        const num_args = arg_span.len;

        var patterns_start: usize = 0;
        if (num_args > 0) {
            const first = arg_span[0];
            if (first < cmds.store.len()) {
                const first_node = cmds.store.get(first);
                if (first_node.tag == .sym) {
                    const first_name = cmds.store.interner.resolve(first_node.payload);
                    if (std.mem.eql(u8, first_name, name)) {
                        patterns_start = 1;
                    }
                }
            }
        }

        const num_pats = num_args - patterns_start;
        if (num_pats > 8) return cmds.allocator.dupe(u8, "too many patterns");

        var pat_ids: [8]u32 = undefined;
        for (0..num_pats) |i| {
            pat_ids[i] = arg_span[patterns_start + i];
        }

        const body_id = cmds.parseExpression(rhs) catch return cmds.allocator.dupe(u8, "parse error in body");
        const lowered_body = try cmds.store.lowerRec(body_id);

        var def: engine_expr.FunctionDef = .{
            .clauses = undefined,
            .num_clauses = 1,
            .ctor_arity = null, // ← explicite
        };
        def.clauses[0] = .{
            .patterns = .{0} ** 8,
            .num_patterns = @intCast(num_pats),
            .body = lowered_body,
        };
        if (num_pats > 0) {
            @memcpy(def.clauses[0].patterns[0..num_pats], pat_ids[0..num_pats]);
        }

        const owned_name = try cmds.engine.allocator.dupe(u8, name);
        platform.dbg("[fns.put] site=2 name='{s}' key_addr={d}\n", .{ name, @intFromPtr(owned_name.ptr) });
        cmds.engine.fns.put(cmds.engine.allocator, owned_name, def) catch |err| {
            return std.fmt.allocPrint(cmds.engine.allocator, "registration error: {s}", .{@errorName(err)});
        };

        const name_sym = try cmds.store.interner.intern(name);
        const name_sym_id = try cmds.store.sym(name);
        try cmds.env.put(name_sym, name_sym_id);

        const msg = try std.fmt.allocPrint(cmds.allocator, "✓ clause enregistrée pour '{s}' ({d} patterns)", .{ name, num_pats });
        platform.dbg("[evalFnDef] alloc addr={d} name={s}\n", .{ @intFromPtr(msg.ptr), name });
        return msg;
    }

    return cmds.allocator.dupe(u8, "syntax error in function definition");
}

pub fn evalLet(cmds: anytype, input: []const u8) anyerror![]u8 {
    // Défensif : certains call sites passent le "let " préfixé (ligne 254).
    var rest = std.mem.trim(u8, input, " \t");
    if (std.mem.startsWith(u8, rest, "let ")) {
        rest = std.mem.trim(u8, rest["let ".len..], " \t");
    }

    // QTT : préfixe de multiplicité (native)
    var qty_kw: ?[]const u8 = null;

    const kws = [_][]const u8{ "linear", "erased", "many" };
    for (kws) |kw| {
        if (std.mem.startsWith(u8, rest, kw) and rest.len > kw.len and (rest[kw.len] == ' ' or rest[kw.len] == '\t')) {
            const after = std.mem.trimLeft(u8, rest[kw.len..], " \t");
            // Ne pas confondre avec `let linear = 5` (variable nommée "linear")
            if (after.len > 0 and after[0] != '=') {
                qty_kw = kw;
                rest = after;
                break;
            }
        }
    }

    // Si un préfixe QTT est présent, on extrait le binding/body pour
    // pouvoir compter les usages après évaluation de l'AST.
    if (qty_kw != null) {
        const in_pos = std.mem.indexOf(u8, rest, " in ") orelse
            return cmds.allocator.dupe(u8, "syntax error in qtt let");
        const binding_str = std.mem.trim(u8, rest[0..in_pos], " \t");
        const body_str = std.mem.trim(u8, rest[in_pos + 4 ..], " \t");

        // binding_str = "x = 5" ou "x := 5"
        const eq = std.mem.indexOfScalar(u8, binding_str, '=') orelse
            return cmds.allocator.dupe(u8, "syntax error in qtt binding");
        var name = std.mem.trim(u8, binding_str[0..eq], " \t:");
        _ = &name;
        // (on tolère "x :=" en trimmant aussi le ':')
        const body_id = cmds.parseExpression(body_str) catch
            return cmds.allocator.dupe(u8, "syntax error in qtt body");

        const uses = expr.countSymUses(cmds.store, body_id, name);
        const ok = if (std.mem.eql(u8, qty_kw.?, "linear"))
            uses == 1
        else if (std.mem.eql(u8, qty_kw.?, "erased"))
            uses == 0
        else
            true; // many : aucune contrainte

        if (!ok) {
            return std.fmt.allocPrint(cmds.allocator, "linear violation: '{s}' declared {s}, used {d} time(s)", .{ name, qty_kw.?, uses });
        }
        // Sinon, on continue : le reste du evalLet se charge de l'exécution normale.
    }

    if (std.mem.indexOf(u8, rest, " in ")) |_| {
        const ast = cmds.parser.parseLetExpr(rest) catch return try cmds.allocator.dupe(u8, "syntax error in let expression");
        cmds.engine.fuel = 10_000;
        const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, ast, 0) catch ast;
        return expr.toStringInfix(cmds.store, result, cmds.allocator);
    }

    const op_len: usize = if (std.mem.startsWith(u8, rest, ":=")) 2 else 1;
    var eq_pos: ?usize = null;
    var i: usize = rest.len;
    while (i > 1) : (i -= 1) {
        if (rest[i - 1] == '=') {
            const prev_c = if (i >= 2) rest[i - 2] else ' ';
            if (prev_c != '!' and prev_c != '<' and prev_c != '>') {
                if (op_len == 1 or prev_c == ':') {
                    eq_pos = i - 1;
                    break;
                }
            }
        }
    }

    if (eq_pos) |eq| {
        var name = std.mem.trim(u8, rest[0..eq], " \t:");
        // Support "name:Type" → garder seulement "name"
        if (std.mem.indexOfScalar(u8, name, ':')) |colon| {
            name = std.mem.trim(u8, name[0..colon], " \t");
        }
        const expr_str = std.mem.trim(u8, rest[eq + 1 ..], " \t");

        if (std.mem.startsWith(u8, expr_str, "fn ") or std.mem.startsWith(u8, expr_str, "fn(")) {
            const fn_def_str = try std.fmt.allocPrint(cmds.allocator, "{s} = {s}", .{ name, expr_str });
            defer cmds.allocator.free(fn_def_str);
            return evalFnDef(cmds, fn_def_str);
        }

        const has_params = std.mem.indexOfScalar(u8, name, '(') != null and
            std.mem.endsWith(u8, name, ")");
        if (has_params or std.mem.indexOfScalar(u8, name, ' ') != null) {
            const fn_def_str = try std.fmt.allocPrint(cmds.allocator, "{s} = {s}", .{ name, expr_str });
            defer cmds.allocator.free(fn_def_str);
            return evalFnDef(cmds, fn_def_str);
        }
        return define(cmds, name, expr_str);
    }

    return try cmds.allocator.dupe(u8, "syntax error: missing =");
}

