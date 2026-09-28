//! format.zig — Rendu et sérialisation de Commands (D4 batch 5).
//! Extraites de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const codegen_c = @import("codegen_expr_c");
const codegen_latex = @import("codegen_expr_latex");

const Store = expr.Store;
const Id = expr.Id;

pub fn evalLatex(cmds: anytype, input: []const u8) anyerror![]u8 {
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    const latex = try toLaTeXInline(cmds, id);
    defer cmds.allocator.free(latex); // ← ajouter
    return std.fmt.allocPrint(cmds.allocator, "latex|{s}", .{latex});
}

pub fn toC(cmds: anytype, ids: []const Id) anyerror![]u8 {
    var cg = codegen_c.Codegen.init(cmds.store, cmds.allocator);
    defer cg.deinit();
    return cg.generate(ids);
}

pub fn toLaTeX(cmds: anytype, ids: []const Id) anyerror![]u8 {
    var gen = codegen_latex.LaTeX.init(cmds.store, cmds.allocator);
    defer gen.deinit();
    return gen.generate(ids);
}

pub fn toLaTeXInline(cmds: anytype, id: Id) anyerror![]u8 {
    var gen = codegen_latex.LaTeX.init(cmds.store, cmds.allocator);
    defer gen.deinit();
    return gen.renderInline(id);
}

pub fn format(cmds: anytype, id: Id) anyerror![]u8 {
    return expr.toString(cmds.store, id, cmds.allocator);
}

pub fn dumpAst(cmds: anytype, input: []const u8) anyerror![]u8 {
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(cmds.allocator);
    try writeAst(cmds, id, 0, &buf);
    return buf.toOwnedSlice(cmds.allocator);
}

pub fn writeAst(cmds: anytype, id: Id, depth: u32, buf: *std.ArrayListUnmanaged(u8)) anyerror!void {
    if (id >= cmds.store.len()) return;
    const node = cmds.store.get(id);
    var i: u32 = 0;
    while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
    switch (node.tag) {
        .sym => {
            const name = cmds.store.interner.resolve(node.payload);
            try buf.appendSlice(cmds.allocator, "(sym \"");
            try buf.appendSlice(cmds.allocator, name);
            try buf.appendSlice(cmds.allocator, "\")\n");
        },
        .lit => {
            const l = cmds.store.lits.items[node.aux];
            switch (l) {
                .int => |v| {
                    var tmp: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&tmp, "(lit {d})\n", .{v}) catch return;
                    try buf.appendSlice(cmds.allocator, s);
                },
                else => try buf.appendSlice(cmds.allocator, "(lit ?)\n"),
            }
        },
        .apply => {
            try buf.appendSlice(cmds.allocator, "(apply\n");
            try writeAst(cmds, node.payload, depth + 1, buf);
            for (node.span_a.slice(cmds.store.pool.items)) |child| try writeAst(cmds, child, depth + 1, buf);
            i = 0;
            while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
            try buf.appendSlice(cmds.allocator, ")\n");
        },
        .bind => {
            try buf.appendSlice(cmds.allocator, "(bind ");
            try buf.appendSlice(cmds.allocator, cmds.store.interner.resolve(node.payload));
            try buf.appendSlice(cmds.allocator, "\n");
            for (node.span_a.slice(cmds.store.pool.items)) |child| try writeAst(cmds, child, depth + 1, buf);
            i = 0;
            while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
            try buf.appendSlice(cmds.allocator, ")\n");
        },
        .lambda => {
            try buf.appendSlice(cmds.allocator, "(lambda ");
            try buf.appendSlice(cmds.allocator, cmds.store.interner.resolve(node.payload));
            try buf.appendSlice(cmds.allocator, "\n");
            for (node.span_a.slice(cmds.store.pool.items)) |child| try writeAst(cmds, child, depth + 1, buf);
            i = 0;
            while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
            try buf.appendSlice(cmds.allocator, ")\n");
        },
        .relation => {
            try buf.appendSlice(cmds.allocator, "(relation ");
            try buf.appendSlice(cmds.allocator, cmds.store.interner.resolve(node.payload));
            try buf.appendSlice(cmds.allocator, "\n");
            for (node.span_a.slice(cmds.store.pool.items)) |child| try writeAst(cmds, child, depth + 1, buf);
            i = 0;
            while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
            try buf.appendSlice(cmds.allocator, ")\n");
        },
        .source_file, .block, .block_legacy => {
            try buf.appendSlice(cmds.allocator, "(");
            try buf.appendSlice(cmds.allocator, @tagName(node.tag));
            try buf.appendSlice(cmds.allocator, "\n");
            for (node.span_a.slice(cmds.store.pool.items)) |child| try writeAst(cmds, child, depth + 1, buf);
            i = 0;
            while (i < depth) : (i += 1) try buf.appendSlice(cmds.allocator, " ");
            try buf.appendSlice(cmds.allocator, ")\n");
        },
        else => {
            try buf.appendSlice(cmds.allocator, "(");
            try buf.appendSlice(cmds.allocator, @tagName(node.tag));
            try buf.appendSlice(cmds.allocator, ")\n");
        },
    }
}

pub fn exprToC(cmds: anytype, input: []const u8) anyerror![]u8 {
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    var cg = codegen_c.Codegen.init(cmds.store, cmds.allocator);
    defer cg.deinit();
    return cg.generateExpr(id);
}

// ─── Preuve ───

