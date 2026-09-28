//! runtime.zig — Commandes runtime (green, optimize, mir, js, …).
//! D4 batch 6b. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const egraph_mod = @import("egraph");
const mir = @import("mir");
const x86_64 = @import("x86_64");
const platform = @import("platform");

const codegen_js = @import("codegen_expr_js"); // ou "codegen_js" selon les deps du module runtime_ops
const transform_mod = @import("transform");

const Store = expr.Store;
const Id = expr.Id;

pub fn evalGreen(cmds: anytype, input: []const u8) anyerror![]u8 {
    // Même mécanisme que cmdGreen : wrapper dans (handle expr greenHandler)
    if (cmds.eval("let greenHandler(v1, v2, cost) = (+ v1 v2)")) |r| {
        cmds.allocator.free(r);
    } else |_| {}

    const expr_id = try cmds.bridge.importExpr(input);
    const handle_op = try cmds.store.sym("handle");
    const handler_sym = try cmds.store.sym("greenHandler");
    const handle_node = try cmds.store.apply(handle_op, &.{ expr_id, handler_sym });

    cmds.engine.green_call_count = 0;
    cmds.engine.green_mode = true;
    defer cmds.engine.green_mode = false;
    cmds.engine.fuel = 1_000_000;

    const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, handle_node, 0) catch |err| {
        return try std.fmt.allocPrint(cmds.allocator, "green eval error: {}", .{err});
    };
    const res_str = try expr.toStringInfix(cmds.store, result, cmds.allocator);
    defer cmds.allocator.free(res_str);
    return try std.fmt.allocPrint(cmds.allocator, "{s} (green calls: {d})", .{ res_str, cmds.engine.green_call_count });
}

pub fn evalOptimize(cmds: anytype, input: []const u8) anyerror![]u8 {
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    var qtt = egraph_mod.QttCost{};
    defer qtt.deinit(cmds.allocator);
    var it = cmds.qtt_env.iterator();
    while (it.next()) |entry| {
        const sym = try cmds.store.interner.intern(entry.key_ptr.*);
        const sym_id = try cmds.store.symId(sym);
        try qtt.quantities.put(cmds.allocator, sym_id, entry.value_ptr.*);
    }
    const optimized = try cmds.simplify_eng.simplifyWithEGraph(id, &qtt, null);
    return expr.toString(cmds.store, optimized, cmds.allocator);
}

pub fn evalAsm(cmds: anytype, input: []const u8) anyerror![]u8 {
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    var mir_func = mir.MirFunction.init(cmds.allocator);
    defer mir_func.deinit();
    const entry_block = try mir_func.newBlock();
    var locals = std.AutoHashMap(u32, mir.Id).init(cmds.allocator);
    defer locals.deinit();
    _ = try mir_func.compileExpr(cmds.store, id, entry_block, locals);
    mir_func.blocks.items[entry_block].terminator = .{ .ret = 0 };
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(cmds.allocator);
    try x86_64.emitFromFunction(&mir_func, buf.writer(cmds.allocator));
    return buf.toOwnedSlice(cmds.allocator);
}

pub fn evalSExpr(cmds: anytype, input: []const u8) anyerror![]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\n\r");
    if (trimmed.len == 0) return cmds.allocator.dupe(u8, "()");

    const expr_id = cmds.parseExpression(trimmed) catch return error.InvalidSyntax;
    cmds.engine.fuel = 1_000_000;
    const result = engine_expr.evaluate(cmds.store, cmds.env, cmds.engine, expr_id, 0) catch expr_id;
    return expr.toStringInfix(cmds.store, result, cmds.allocator);
}

pub fn substExpr(cmds: anytype, input: []const u8, varname: []const u8, value: []const u8) anyerror![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    const w = result.writer(cmds.allocator);
    var i: usize = 0;
    while (i < input.len) {
        if (i + varname.len <= input.len and std.mem.eql(u8, input[i .. i + varname.len], varname)) {
            const before_ok = i == 0 or !std.ascii.isAlphabetic(input[i - 1]);
            const after_ok = i + varname.len >= input.len or !std.ascii.isAlphabetic(input[i + varname.len]);
            if (before_ok and after_ok) {
                try w.writeAll(value);
                i += varname.len;
                continue;
            }
        }
        try w.writeByte(input[i]);
        i += 1;
    }
    return result.toOwnedSlice(cmds.allocator);
}

pub fn evalMir(cmds: anytype, input: []const u8) anyerror![]u8 {
    var instructions = std.mem.splitScalar(u8, input, ';');
    var last_expr: []const u8 = "";
    while (instructions.next()) |instr| {
        const trimmed = std.mem.trim(u8, instr, " \t");
        if (trimmed.len == 0) continue;
        last_expr = trimmed;
    }
    const id = cmds.bridge.importExpr(last_expr) catch |err| {
        return std.fmt.allocPrint(cmds.allocator, "parse error: {s}", .{@errorName(err)});
    };
    var mir_func = mir.MirFunction.init(cmds.allocator);
    defer mir_func.deinit();
    mir_func.engine = cmds.engine;
    mir_func.store_ref = cmds.store;
    const entry_block = try mir_func.newBlock();
    var locals = std.AutoHashMap(u32, mir.Id).init(cmds.allocator);
    defer locals.deinit();
    const result_val = try mir_func.compileExpr(cmds.store, id, entry_block, locals);
    if (mir_func.blocks.items[entry_block].terminator == .fallthrough) {
        mir_func.blocks.items[entry_block].terminator = .{ .ret = result_val };
    }
    var global_vars = std.AutoHashMap(u32, i64).init(cmds.allocator);
    defer global_vars.deinit();
    const result = mir_func.execute(&global_vars) catch |err| {
        return std.fmt.allocPrint(cmds.allocator, "mir exec error: {s}", .{@errorName(err)});
    };
    return std.fmt.allocPrint(cmds.allocator, "{d}", .{result});
}

pub fn evalAsk(cmds: anytype, input: []const u8) anyerror![]u8 {
    const prompt = std.mem.trim(u8, input, " ");
    if (prompt.len == 0) return try cmds.allocator.dupe(u8, "Usage: ask <question>");
    const suggestion = try cmds.agent.suggest(prompt) orelse
        return try cmds.allocator.dupe(u8, "Je ne sais pas répondre à cette question.");
    var buf: [1024]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "[INFO] Suggestion : {s}\n", .{suggestion});
    const result = try cmds.eval(suggestion);
    defer cmds.allocator.free(result);
    return std.fmt.allocPrint(cmds.allocator, "{s}→ {s}", .{ msg, result });
}

pub fn evalJs(cmds: anytype, input: []const u8) anyerror![]u8 {
    const id = cmds.bridge.importExpr(input) catch |err| {
        return std.fmt.allocPrint(cmds.allocator, "js parse error: {s}", .{@errorName(err)});
    };
    return codegen_js.exprToJs(cmds.store, id, cmds.allocator);
}

pub fn evalTransform(cmds: anytype, input: []const u8) anyerror![]u8 {
    const eq_pos = std.mem.indexOf(u8, input, "=") orelse return error.InvalidSyntax;
    const lhs_str = std.mem.trim(u8, input[0..eq_pos], " ");
    const rhs_str = std.mem.trim(u8, input[eq_pos + 1 ..], " ");
    const lhs_id = cmds.bridge.importExpr(lhs_str) catch return error.InvalidSyntax;
    const rhs_id = cmds.bridge.importExpr(rhs_str) catch return error.InvalidSyntax;
    var tf = transform_mod.Transform.init(cmds.allocator, cmds.store, cmds.kb);
    const result = tf.transform(lhs_id, rhs_id, cmds.engine);
    return transform_mod.format(result, cmds.store, cmds.allocator);
}

pub fn mkBinop(cmds: anytype, op: []const u8, a: Id, b: Id) anyerror!Id {
    if (a >= cmds.store.len() or b >= cmds.store.len()) return cmds.store.int(0);
    const na = cmds.store.get(a);
    const nb = cmds.store.get(b);
    const is_a_zero = na.tag == .lit and cmds.store.lits.items[na.aux].eql(.{ .int = 0 });
    const is_b_zero = nb.tag == .lit and cmds.store.lits.items[nb.aux].eql(.{ .int = 0 });
    const is_a_one = na.tag == .lit and cmds.store.lits.items[na.aux].eql(.{ .int = 1 });
    const is_b_one = nb.tag == .lit and cmds.store.lits.items[nb.aux].eql(.{ .int = 1 });
    if (std.mem.eql(u8, op, "+")) {
        if (is_a_zero) return b;
        if (is_b_zero) return a;
        if (na.tag == .lit and nb.tag == .lit) {
            const la = cmds.store.lits.items[na.aux];
            const lb = cmds.store.lits.items[nb.aux];
            switch (la) {
                .int => |va| switch (lb) {
                    .int => |vb| return cmds.store.int(std.math.add(i64, va, vb) catch return error.Overflow),
                    else => {},
                },
                else => {},
            }
        }
    } else if (std.mem.eql(u8, op, "-")) {
        if (is_b_zero) return a;
        if (na.tag == .lit and nb.tag == .lit) {
            const la = cmds.store.lits.items[na.aux];
            const lb = cmds.store.lits.items[nb.aux];
            switch (la) {
                .int => |va| switch (lb) {
                    .int => |vb| return cmds.store.int(std.math.sub(i64, va, vb) catch return error.Overflow),
                    else => {},
                },
                else => {},
            }
        }
    } else if (std.mem.eql(u8, op, "*")) {
        if (is_a_zero or is_b_zero) return cmds.store.int(0);
        if (is_a_one) return b;
        if (is_b_one) return a;
        if (na.tag == .lit and nb.tag == .lit) {
            const la = cmds.store.lits.items[na.aux];
            const lb = cmds.store.lits.items[nb.aux];
            switch (la) {
                .int => |va| switch (lb) {
                    .int => |vb| return cmds.store.int(std.math.mul(i64, va, vb) catch return error.Overflow),
                    else => {},
                },
                else => {},
            }
        }
    } else if (std.mem.eql(u8, op, "/")) {
        if (is_a_zero) return cmds.store.int(0);
        if (is_b_one) return a;
    } else if (std.mem.eql(u8, op, "^")) {
        if (is_b_zero) return cmds.store.int(1);
        if (is_b_one) return a;
    }
    return cmds.store.binop(op, a, b);
}
