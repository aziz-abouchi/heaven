//! meta.zig — Introspection, aide, stats (D4 batch 6a).
//! Extraites de src/core/commands.zig. Voir docs/DECISIONS.md (D4).

const std = @import("std");
const expr = @import("expr");
const types_mod = @import("types");
const egraph_mod = @import("egraph");
const canon_mod = @import("canon");
const platform = @import("platform");

const Store = expr.Store;
const Id = expr.Id;

pub fn evalHelp(cmds: anytype) anyerror![]u8 {
    return try cmds.allocator.dupe(u8, "═══ Heaven ═══\n" ++
        "  help, stats, theorems\n" ++
        "  theorem <name> : <prop>\n" ++
        "  prove by <method>\n" ++
        "  skill <name>\n" ++
        "  type <expr>\n" ++
        "  simplify <expr>\n" ++
        "  derive <expr>\n" ++
        "  solve <equation>\n" ++
        "  expand <expr>\n" ++
        "  integrate <expr>\n" ++
        "  plot <function>\n" ++
        "  latex <expr>\n" ++
        "  explain <expr>\n" ++
        "  trace <expr>\n" ++
        "  let <var> = <expr>\n");
}

pub fn evalStats(cmds: anytype) anyerror![]u8 {
    return try cmds.allocator.dupe(u8, "═══ Heaven WASM ═══\n" ++
        "Engine: active\n" ++
        "Features: eval, type, simplify, explain, latex, quote, prove");
}

pub fn evalType(cmds: anytype, input: []const u8) anyerror![]u8 {
    return typeOf(cmds, input);
}

pub fn evalExpand(cmds: anytype, input: []const u8) anyerror![]u8 {
    return cmds.math.expand(input);
}

pub fn evalExplain(cmds: anytype, input: []const u8) anyerror![]u8 {
    return explain(cmds, input);
}

pub fn evalPlot(cmds: anytype, input: []const u8) anyerror![]u8 {
    const expr_str = std.mem.trim(u8, input, " ");
    return std.fmt.allocPrint(cmds.allocator, "plot|{s}", .{expr_str});
}

pub fn evalQtt(cmds: anytype, input: []const u8) anyerror![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    defer result.deinit(cmds.allocator);
    var tokens = std.mem.tokenizeScalar(u8, input, ',');
    while (tokens.next()) |token| {
        const trimmed = std.mem.trim(u8, token, " ");
        if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
            const name = std.mem.trim(u8, trimmed[0..colon], " ");
            const qty_str = std.mem.trim(u8, trimmed[colon + 1 ..], " ");
            const qty = if (std.mem.eql(u8, qty_str, "0") or std.mem.eql(u8, qty_str, "zero")) @as(u2, 0) else if (std.mem.eql(u8, qty_str, "1") or std.mem.eql(u8, qty_str, "one")) @as(u2, 1) else @as(u2, 2);
            _ = try cmds.store.interner.intern(name);
            try cmds.qtt_env.put(cmds.allocator, name, qty);
            try result.writer(cmds.allocator).print("qtt: {s} -> {d}\n", .{ name, qty });
        }
    }
    return result.toOwnedSlice(cmds.allocator);
}

pub fn evalTrace(cmds: anytype, input: []const u8) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(cmds.allocator);
    const w = buf.writer(cmds.allocator);
    const raw_id = cmds.parseExpression(input) catch try cmds.bridge.importExpr(input);
    const id = try cmds.store.lowerRec(raw_id);
    const initial = try expr.toStringInfix(cmds.store, id, cmds.allocator);
    defer cmds.allocator.free(initial);
    try w.print("trace: {s}\n", .{initial});
    var current = try cmds.simplify_eng.simplifyRec(id, 0);
    const after_rec = try expr.toStringInfix(cmds.store, current, cmds.allocator);
    defer cmds.allocator.free(after_rec);
    if (!std.mem.eql(u8, initial, after_rec))
        try w.print("  → [rewrite] {s}\n", .{after_rec});
    var qtt = egraph_mod.QttCost{};
    defer qtt.deinit(cmds.allocator);
    var it = cmds.qtt_env.iterator();
    while (it.next()) |entry| {
        const sym = try cmds.store.interner.intern(entry.key_ptr.*);
        const sym_id = try cmds.store.symId(sym);
        try qtt.quantities.put(cmds.allocator, sym_id, entry.value_ptr.*);
    }
    const after_egraph = try cmds.simplify_eng.simplifyWithEGraph(current, &qtt, null);
    const after_egraph_str = try expr.toStringInfix(cmds.store, after_egraph, cmds.allocator);
    defer cmds.allocator.free(after_egraph_str);
    if (!std.mem.eql(u8, after_rec, after_egraph_str))
        try w.print("  → [egraph] {s}\n", .{after_egraph_str});
    current = after_egraph;
    const canon = try canon_mod.canonicalize(cmds.store, cmds.allocator, current);
    const canon_str = try expr.toStringInfix(cmds.store, canon, cmds.allocator);
    defer cmds.allocator.free(canon_str);
    if (!std.mem.eql(u8, after_egraph_str, canon_str))
        try w.print("  → [canon] {s}\n", .{canon_str});
    const node_count = countNodes(cmds, canon);
    try w.print("  cost: {d} nodes\n", .{node_count});
    return buf.toOwnedSlice(cmds.allocator);
}

pub fn countNodes(cmds: anytype, id: Id) usize {
    if (id >= cmds.store.len()) return 0;
    const node = cmds.store.get(id);
    var count: usize = 1;
    switch (node.tag) {
        .apply => {
            count += countNodes(cmds, node.payload);
            for (node.span_a.slice(cmds.store.pool.items)) |child|
                count += countNodes(cmds, child);
        },
        .bind => {
            const children = node.span_a.slice(cmds.store.pool.items);
            if (children.len != 2) return 0;
            count += countNodes(cmds, children[0]);
            count += countNodes(cmds, children[1]);
        },
        else => {},
    }
    return count;
}

pub fn typeOf(cmds: anytype, input: []const u8) anyerror![]u8 {
    const trimmed = std.mem.trim(u8, input, " \t");
    const id = blk: {
        if (std.mem.indexOf(u8, trimmed, "(λ") != null or std.mem.indexOf(u8, trimmed, "(\\") != null) {
            break :blk try cmds.parseApp(trimmed);
        } else if (trimmed.len > 0 and trimmed[0] == '(') {
            break :blk try cmds.parser.parseSExpr(trimmed);
        } else {
            // Fallback robuste
            break :blk cmds.parseExpression(trimmed) catch try cmds.bridge.importExpr(trimmed);
        }
    };
    var inf = types_mod.Infer.init(cmds.store, cmds.allocator);
    defer inf.deinit();
    const t = try inf.typeOf(id);
    return inf.typeStr(&inf.subst, t, cmds.allocator);
}

pub fn listRules(cmds: anytype) anyerror![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    const w = buf.writer(cmds.allocator);
    try w.writeAll("  KB rules as data:\n");
    for (cmds.kb.rules.items, 0..) |rule_id, idx| {
        if (rule_id >= cmds.store.len()) continue;
        const s = expr.toString(cmds.store, rule_id, cmds.allocator) catch continue;
        defer cmds.allocator.free(s);
        try std.fmt.format(w, "  [{d}] {s}\n", .{ idx, s });
    }
    return buf.toOwnedSlice(cmds.allocator);
}

pub fn explain(cmds: anytype, input: []const u8) anyerror![]u8 {
    var current = try cmds.bridge.importExpr(input);
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(cmds.allocator);
    const s0 = try expr.toString(cmds.store, current, cmds.allocator);
    defer cmds.allocator.free(s0);
    try buf.appendSlice(cmds.allocator, "  step 0: ");
    try buf.appendSlice(cmds.allocator, s0);
    try buf.append(cmds.allocator, '\n');
    var step: u32 = 1;
    while (step < 20) {
        const prev = current;
        current = try cmds.simplify_eng.simplifyOnePass(current, &buf, &step);
        if (current == prev) break;
    }
    const final_str = try expr.toString(cmds.store, current, cmds.allocator);
    defer cmds.allocator.free(final_str);
    try buf.appendSlice(cmds.allocator, "  ∴ ");
    try buf.appendSlice(cmds.allocator, s0);
    try buf.appendSlice(cmds.allocator, " = ");
    try buf.appendSlice(cmds.allocator, final_str);
    var tmp: [32]u8 = undefined;
    const count_str = std.fmt.bufPrint(&tmp, "  ({d} rewrites)\n", .{step - 1}) catch "?\n";
    try buf.appendSlice(cmds.allocator, count_str);
    return buf.toOwnedSlice(cmds.allocator);
}

pub fn describeKB(cmds: anytype) anyerror![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(cmds.allocator);
    var tmp: [64]u8 = undefined;
    const n_str = std.fmt.bufPrint(&tmp, " {d} rewrite rules\n", .{cmds.kb.rules.items.len}) catch "?\n";
    try buf.appendSlice(cmds.allocator, n_str);
    for (cmds.kb.rules.items) |rule_id| {
        if (rule_id >= cmds.store.len()) continue;
        const s = try expr.toString(cmds.store, rule_id, cmds.allocator);
        defer cmds.allocator.free(s);
        try buf.appendSlice(cmds.allocator, " ");
        try buf.appendSlice(cmds.allocator, s);
        try buf.append(cmds.allocator, '\n');
    }
    return buf.toOwnedSlice(cmds.allocator);
}

