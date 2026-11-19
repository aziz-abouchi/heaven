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

/// Baisse les formes AST `HP.*` (`ELitI`, `ELitS`, `ESym`, `EApply`, `ELambda`) vers `Store`.
pub fn lowerHpToStore(
    alloc: std.mem.Allocator,
    store: *Store,
    node: expr.Id,
) !expr.Id {
    const n = store.get(node);
    switch (n.tag) {
        .lit => {
            const lit_val = store.getLit(node);
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
            const fn_id = store.pool.items[n.span_a.start];
            const arg_id = store.pool.items[n.span_a.start + 1];
            const fn_node = store.get(fn_id);
            if (fn_node.tag == .lambda) {
                const val_id = try lowerHpToStore(alloc, store, arg_id);
                const body_id = try lowerHpToStore(alloc, store, store.pool.items[fn_node.span_a.start + 1]);
                return try store.bindSymWithBody(fn_node.payload, val_id, body_id);
            }
            const f_id = try lowerHpToStore(alloc, store, fn_id);
            const a_id = try lowerHpToStore(alloc, store, arg_id);
            return try store.apply(f_id, &.{a_id});
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

    const entry = try mf.newBlock();
    var locals = std.AutoHashMap(u32, Reg).init(alloc);
    defer locals.deinit();

    const result = try mf.compileExpr(store, root_id, entry, locals);
    if (mf.blocks.items[entry].terminator == .fallthrough) {
        mf.blocks.items[entry].terminator = .{ .ret = result };
    }
    return mf;
}

pub fn runCompileC(allocator: std.mem.Allocator, src_path: []const u8, out_path: []const u8) !void {
    const src_code = try std.fs.cwd().readFileAlloc(allocator, src_path, 10 * 1024 * 1024);
    defer allocator.free(src_code);

    var heaven = heaven_expr.Heaven.init(allocator) catch return error.HeavenInit;
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    _ = heaven.eval("import \"lib/parse/infix.hvn\" as Inf") catch {};

    var cmd_buf: std.ArrayList(u8) = .empty;
    defer cmd_buf.deinit(allocator);
    try cmd_buf.appendSlice(allocator, "Inf.parse_infix ");
    try appendEscapedHeavenString(allocator, &cmd_buf, std.mem.trim(u8, src_code, " \t\r\n"));

    const ast_repr = try heaven.eval(cmd_buf.items);
    defer allocator.free(ast_repr);

    const trimmed_ast = std.mem.trim(u8, ast_repr, " \t\r\n");
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
