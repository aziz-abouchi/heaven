const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const heaven_expr = @import("heaven_expr");
const mir = @import("mir");
const mir_qbe = @import("mir_qbe");
const mir_wat = @import("mir_wat");

const Store = expr.Store;
const MirFunction = mir.MirFunction;
const Reg = mir.Reg;

fn appendEscapedHeavenString(alloc: std.mem.Allocator, out: *std.ArrayList(u8), raw: []const u8) !void {
    try out.append(alloc, '"');
    for (raw) |ch| {
        switch (ch) {
            '\\' => try out.appendSlice(alloc, "\\\\"),
            '"' => try out.appendSlice(alloc, "\\\""),
            '\n' => try out.appendSlice(alloc, "\\n"),
            '\r' => try out.appendSlice(alloc, "\\r"),
            '\t' => try out.appendSlice(alloc, "\\t"),
            else => try out.append(alloc, ch),
        }
    }
    try out.append(alloc, '"');
}

/// Rejette explicitement les symboles sentinelles d'erreur produits par `Inf.parse_infix`.
pub fn validateHpSymbol(sym: []const u8) !void {
    if (std.mem.eql(u8, sym, "PARSE_ERR") or std.mem.eql(u8, sym, "HORS_LIMITE")) {
        return error.InfixParseError;
    }
}

fn extractHpHeadAndArgs(store: *Store, node: expr.Id, out_args: *[4]expr.Id) ?struct { name: []const u8, len: usize } {
    const n = store.get(node);
    if (n.tag != .apply) return null;
    const raw = n.span_a.slice(store.pool.items);
    if (raw.len == 0) return null;
    const head_node = store.get(raw[0]);
    if (head_node.tag != .sym) return null;
    const name = store.interner.resolve(head_node.payload);
    const arg_slice = raw[1..];
    if (arg_slice.len > out_args.len) return null;
    for (arg_slice, 0..) |a, i| out_args[i] = a;
    return .{ .name = name, .len = arg_slice.len };
}

fn litStringValue(store: *Store, id: expr.Id) ?[]const u8 {
    const n = store.get(id);
    if (n.tag != .lit) return null;
    return switch (store.getLit(n.aux)) {
        .str => |s| store.interner.resolve(s),
        else => null,
    };
}

fn litIntValue(store: *Store, id: expr.Id) ?i64 {
    const n = store.get(id);
    if (n.tag != .lit) return null;
    return switch (store.getLit(n.aux)) {
        .int => |v| v,
        else => null,
    };
}

/// Baisse les formes AST `HP.*` (`ELitI`, `ELitS`, `ESym`, `EApply`, `ELambda`) vers `Store`.
pub fn lowerHpToStore(
    alloc: std.mem.Allocator,
    store: *Store,
    node: expr.Id,
) !expr.Id {
    var hp_args: [4]expr.Id = undefined;
    if (extractHpHeadAndArgs(store, node, &hp_args)) |hp| {
        if (std.mem.eql(u8, hp.name, "HP.ELitI") and hp.len == 1) {
            if (litIntValue(store, hp_args[0])) |v| return try store.int(v);
        } else if (std.mem.eql(u8, hp.name, "HP.ELitS") and hp.len == 1) {
            if (litStringValue(store, hp_args[0])) |s| {
                return try store.lit(.{ .str = try store.interner.intern(s) });
            }
        } else if (std.mem.eql(u8, hp.name, "HP.ESym") and hp.len == 1) {
            if (litStringValue(store, hp_args[0])) |s| {
                try validateHpSymbol(s);
                return try store.sym(s);
            }
        } else if (std.mem.eql(u8, hp.name, "HP.EApply") and hp.len == 2) {
            const f_id = try lowerHpToStore(alloc, store, hp_args[0]);
            const a_id = try lowerHpToStore(alloc, store, hp_args[1]);
            return try store.apply(f_id, &.{a_id});
        } else if (std.mem.eql(u8, hp.name, "HP.ELambda") and hp.len == 2) {
            if (litStringValue(store, hp_args[0])) |param_name| {
                const body_id = try lowerHpToStore(alloc, store, hp_args[1]);
                return try store.lambda(&.{param_name}, body_id);
            }
        }
    }

    const n = store.get(node);
    switch (n.tag) {
        .lit => {
            const lit_val = store.getLit(n.aux);
            switch (lit_val) {
                .int => |v| return try store.int(v),
                .str => |s_id| {
                    const s = store.interner.resolve(s_id);
                    return try store.lit(.{ .str = try store.interner.intern(s) });
                },
                else => return node,
            }
        },
        .sym => {
            const name = store.interner.resolve(n.payload);
            try validateHpSymbol(name);
            return try store.sym(name);
        },
        .bind => {
            const val_id = try lowerHpToStore(alloc, store, store.pool.items[n.span_a.start]);
            const body_id = try lowerHpToStore(alloc, store, store.pool.items[n.span_a.start + 1]);
            return try store.bindSymWithBody(n.payload, val_id, body_id);
        },
        .apply => {
            const f_id = try lowerHpToStore(alloc, store, n.payload);
            const source_args = store.applyArgs(n);
            const lowered_args = try alloc.alloc(expr.Id, source_args.len);
            defer alloc.free(lowered_args);

            for (source_args, 0..) |arg_id, i| {
                lowered_args[i] = try lowerHpToStore(alloc, store, arg_id);
            }

            return try store.apply(f_id, lowered_args);
        },
        else => return node,
    }
}

pub fn buildMirFunctionFromStore(
    alloc: std.mem.Allocator,
    store: *Store,
    root_id: expr.Id,
) !MirFunction {
    var mf = MirFunction.initWithStore(alloc, store);
    errdefer mf.deinit();
    try mf.precompileUserFns();

    var cur_block = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();

    const result = try mf.compileExpr(store, root_id, &cur_block, locals);
    if (mf.blocks.items[cur_block].terminator == .fallthrough) {
        mf.blocks.items[cur_block].terminator = .{ .ret = result };
    }
    return mf;
}

pub fn isImportFailureMessage(message: []const u8) bool {
    const trimmed = std.mem.trim(u8, message, " \t\r\n");
    return std.mem.startsWith(u8, trimmed, "✗");
}

pub fn runCompileC(allocator: std.mem.Allocator, src_path: []const u8, out_path: []const u8) !void {
    const src_code = try std.fs.cwd().readFileAlloc(allocator, src_path, 10 * 1024 * 1024);
    defer allocator.free(src_code);

    var heaven = heaven_expr.Heaven.init(allocator) catch return error.HeavenInit;
    defer {
        heaven.deinit();
    }

    const import_msg = try heaven.eval("import \"lib/parse/infix.hvn\" as Inf");
    defer allocator.free(import_msg);
    if (isImportFailureMessage(import_msg)) {
        platform.debug.print("[compile-c] échec import parser infixe: {s}\n", .{import_msg});
        return error.InfixParserImportError;
    }

    var cmd_buf: std.ArrayList(u8) = .empty;
    defer cmd_buf.deinit(allocator);
    try cmd_buf.appendSlice(allocator, "(Inf.parse_infix ");
    try appendEscapedHeavenString(allocator, &cmd_buf, std.mem.trim(u8, src_code, " \t\r\n"));
    try cmd_buf.append(allocator, ')');

    const call_id = try heaven.parseExpression(cmd_buf.items);
    const eval_id = try heaven.engine.eval(call_id);
    const ast_repr = try expr.toStringInfix(heaven.store, eval_id, allocator);
    defer allocator.free(ast_repr);

    const trimmed_ast = std.mem.trim(u8, ast_repr, " \t\r\n");
    platform.debug.print("[infix ast_repr] {s}\n", .{ trimmed_ast });
    if (std.mem.indexOf(u8, trimmed_ast, "PARSE_ERR") != null or
        std.mem.indexOf(u8, trimmed_ast, "HORS_LIMITE") != null)
    {
        return error.InfixParseError;
    }

    const parsed_id = try heaven.parseExpression(trimmed_ast);
    const lowered_id = try lowerHpToStore(allocator, heaven.store, parsed_id);

    var mf = try buildMirFunctionFromStore(allocator, heaven.store, lowered_id);
    defer mf.deinit();

    const qbe_ssa = try mir_qbe.emitQbe(allocator, &mf);
    defer allocator.free(qbe_ssa);

    const wat_src = try mir_wat.emitWat(allocator, &mf);
    defer allocator.free(wat_src);

    try std.fs.cwd().writeFile(.{ .sub_path = out_path, .data = qbe_ssa });
    platform.debug.print(
        "✓ MIR émis ({d} octets QBE, {d} octets WAT) -> {s}\n",
        .{ qbe_ssa.len, wat_src.len, out_path },
    );
}
test "infix juxtaposition precedence over caret and error sentinel" {
    const allocator = std.testing.allocator;
    var heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    const import_msg = try heaven.eval("import \"lib/parse/infix.hvn\" as Inf");
    defer allocator.free(import_msg);
    try std.testing.expect(!isImportFailureMessage(import_msg));

    // f x ^ 2 doit parser (f x) ^ 2 : la tête externe est ^, et son opérande gauche est (f x)
    const call_id = try heaven.parseExpression("(Inf.parse_infix \"f x ^ 2\")");
    const eval_id = try heaven.engine.eval(call_id);
    const ast_repr = try expr.toStringInfix(heaven.store, eval_id, allocator);
    defer allocator.free(ast_repr);

    const trimmed = std.mem.trim(u8, ast_repr, " \t\r\n");
    try std.testing.expect(std.mem.indexOf(u8, trimmed, "PARSE_ERR") == null);

    const parsed_id = try heaven.parseExpression(trimmed);
    const lowered_id = try lowerHpToStore(allocator, heaven.store, parsed_id);
    const root_node = heaven.store.get(lowered_id);
    try std.testing.expectEqual(expr.Tag.apply, root_node.tag);

    const outer_callee = heaven.store.get(root_node.payload);
    try std.testing.expectEqual(expr.Tag.sym, outer_callee.tag);
    try std.testing.expectEqualStrings("^", heaven.store.interner.resolve(outer_callee.payload));

    const outer_args = heaven.store.applyArgs(root_node);
    try std.testing.expectEqual(@as(usize, 2), outer_args.len);

    const left_node = heaven.store.get(outer_args[0]);
    try std.testing.expectEqual(expr.Tag.apply, left_node.tag);
    const inner_callee = heaven.store.get(left_node.payload);
    try std.testing.expectEqual(expr.Tag.sym, inner_callee.tag);
    try std.testing.expectEqualStrings("f", heaven.store.interner.resolve(inner_callee.payload));

    // Une expression invalide doit produire PARSE_ERR
    const bad_call = try heaven.parseExpression("(Inf.parse_infix \"1 + * 2\")");
    const bad_eval = try heaven.engine.eval(bad_call);
    const bad_repr = try expr.toStringInfix(heaven.store, bad_eval, allocator);
    defer allocator.free(bad_repr);
    try std.testing.expect(std.mem.indexOf(u8, bad_repr, "PARSE_ERR") != null);
}
test "infix application chain, caret right-associativity, and unclosed paren" {
    const allocator = std.testing.allocator;
    var heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    const import_msg = try heaven.eval("import \"lib/parse/infix.hvn\" as Inf");
    defer allocator.free(import_msg);
    try std.testing.expect(!isImportFailureMessage(import_msg));

    // Associativite a gauche de la juxtaposition : f x y => ((f x) y)
    {
        const call_id = try heaven.parseExpression("(Inf.parse_infix \"f x y\")");
        const eval_id = try heaven.engine.eval(call_id);
        const ast_repr = try expr.toStringInfix(heaven.store, eval_id, allocator);
        defer allocator.free(ast_repr);

        const trimmed = std.mem.trim(u8, ast_repr, " \t\r\n");
        try std.testing.expect(std.mem.indexOf(u8, trimmed, "PARSE_ERR") == null);

        const parsed_id = try heaven.parseExpression(trimmed);
        const lowered_id = try lowerHpToStore(allocator, heaven.store, parsed_id);
        const root = heaven.store.get(lowered_id);
        try std.testing.expectEqual(expr.Tag.apply, root.tag);

        const root_args = heaven.store.applyArgs(root);
        try std.testing.expectEqual(@as(usize, 1), root_args.len);
        const last_arg = heaven.store.get(root_args[0]);
        try std.testing.expectEqual(expr.Tag.sym, last_arg.tag);
        try std.testing.expectEqualStrings("y", heaven.store.interner.resolve(last_arg.payload));

        const inner = heaven.store.get(root.payload);
        try std.testing.expectEqual(expr.Tag.apply, inner.tag);
        const inner_callee = heaven.store.get(inner.payload);
        try std.testing.expectEqual(expr.Tag.sym, inner_callee.tag);
        try std.testing.expectEqualStrings("f", heaven.store.interner.resolve(inner_callee.payload));
    }

    // Associativite a droite de ^ : a ^ b ^ c => ^ a (^ b c)
    {
        const call_id = try heaven.parseExpression("(Inf.parse_infix \"a ^ b ^ c\")");
        const eval_id = try heaven.engine.eval(call_id);
        const ast_repr = try expr.toStringInfix(heaven.store, eval_id, allocator);
        defer allocator.free(ast_repr);

        const trimmed = std.mem.trim(u8, ast_repr, " \t\r\n");
        try std.testing.expect(std.mem.indexOf(u8, trimmed, "PARSE_ERR") == null);

        const parsed_id = try heaven.parseExpression(trimmed);
        const lowered_id = try lowerHpToStore(allocator, heaven.store, parsed_id);
        const root = heaven.store.get(lowered_id);
        try std.testing.expectEqual(expr.Tag.apply, root.tag);

        const op_sym = heaven.store.get(root.payload);
        try std.testing.expectEqualStrings("^", heaven.store.interner.resolve(op_sym.payload));

        const args = heaven.store.applyArgs(root);
        try std.testing.expectEqual(@as(usize, 2), args.len);
        const lhs = heaven.store.get(args[0]);
        try std.testing.expectEqualStrings("a", heaven.store.interner.resolve(lhs.payload));

        const rhs = heaven.store.get(args[1]);
        try std.testing.expectEqual(expr.Tag.apply, rhs.tag);
        const rhs_op = heaven.store.get(rhs.payload);
        try std.testing.expectEqualStrings("^", heaven.store.interner.resolve(rhs_op.payload));
    }

    // Parenthese non fermee => PARSE_ERR
    {
        const bad_call = try heaven.parseExpression("(Inf.parse_infix \"(1 + 2\")");
        const bad_eval = try heaven.engine.eval(bad_call);
        const bad_repr = try expr.toStringInfix(heaven.store, bad_eval, allocator);
        defer allocator.free(bad_repr);
        try std.testing.expect(std.mem.indexOf(u8, bad_repr, "PARSE_ERR") != null);
    }
}

test "infix mixed precedence a + b * c ^ d and lowering" {
    const allocator = std.testing.allocator;
    var heaven = try heaven_expr.Heaven.init(allocator);
    defer heaven.deinit();

    const import_msg = try heaven.eval("import \"lib/parse/infix.hvn\" as Inf");
    defer allocator.free(import_msg);
    try std.testing.expect(!isImportFailureMessage(import_msg));

    const call_id = try heaven.parseExpression("(Inf.parse_infix \"a + b * c ^ d\")");
    const eval_id = try heaven.engine.eval(call_id);
    const ast_repr = try expr.toStringInfix(heaven.store, eval_id, allocator);
    defer allocator.free(ast_repr);

    const trimmed = std.mem.trim(u8, ast_repr, " \t\r\n");
    try std.testing.expect(std.mem.indexOf(u8, trimmed, "PARSE_ERR") == null);

    const parsed_id = try heaven.parseExpression(trimmed);
    const lowered_id = try lowerHpToStore(allocator, heaven.store, parsed_id);
    const root = heaven.store.get(lowered_id);
    try std.testing.expectEqual(expr.Tag.apply, root.tag);

    const root_op = heaven.store.get(root.payload);
    try std.testing.expectEqualStrings("+", heaven.store.interner.resolve(root_op.payload));

    const add_args = heaven.store.applyArgs(root);
    try std.testing.expectEqual(@as(usize, 2), add_args.len);
    try std.testing.expectEqualStrings("a", heaven.store.interner.resolve(heaven.store.get(add_args[0]).payload));

    const mul_node = heaven.store.get(add_args[1]);
    try std.testing.expectEqual(expr.Tag.apply, mul_node.tag);
    try std.testing.expectEqualStrings("*", heaven.store.interner.resolve(heaven.store.get(mul_node.payload).payload));

    const mul_args = heaven.store.applyArgs(mul_node);
    try std.testing.expectEqual(@as(usize, 2), mul_args.len);
    try std.testing.expectEqualStrings("b", heaven.store.interner.resolve(heaven.store.get(mul_args[0]).payload));

    const pow_node = heaven.store.get(mul_args[1]);
    try std.testing.expectEqual(expr.Tag.apply, pow_node.tag);
    try std.testing.expectEqualStrings("^", heaven.store.interner.resolve(heaven.store.get(pow_node.payload).payload));
}
