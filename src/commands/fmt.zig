const std = @import("std");
const platform = @import("platform");
const ts = platform.ts;

pub fn runFmt(allocator: std.mem.Allocator, file_path: []const u8) anyerror!void {
    const source = platform.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch {
        // platform.debug.print("Error reading {s}: {}\n", .{ file_path, e });
        return;
    };
    defer allocator.free(source);

    const parser = ts.ts_parser_new() orelse return;
    defer ts.ts_parser_delete(parser);
    if (!ts.ts_parser_set_language(parser, platform.tree_sitter_heaven())) return;

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return;
    defer ts.ts_tree_delete(tree);

    const root = ts.ts_tree_root_node(tree);

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);
    var w = output.writer(allocator);

    try formatNode(source, root, &w, 0);

    // Write back
    try platform.fs.cwd().writeFile(.{ .sub_path = file_path, .data = output.items });
    // platform.debug.print("Formatted {s} ({d} bytes)\n", .{ file_path, output.items.len });
}

fn formatNode(source: []const u8, node: ts.TSNode, w: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    if (count == 0) return;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ntype = std.mem.span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ntype, "comment")) {
            try emitIndent(w, indent);
            try w.writeAll(nodeText(source, child));
            try w.writeAll("\n");
        } else if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) {
            try formatFn(source, child, w, indent);
        } else if (std.mem.eql(u8, ntype, "struct_decl")) {
            try formatStructLike(source, child, w, indent, "struct");
        } else if (std.mem.eql(u8, ntype, "enum_decl")) {
            try formatStructLike(source, child, w, indent, "enum");
        } else if (std.mem.eql(u8, ntype, "effect_decl")) {
            try formatStructLike(source, child, w, indent, "effect");
        } else if (std.mem.eql(u8, ntype, "test_decl")) {
            try formatTestDecl(source, child, w, indent);
        } else if (std.mem.eql(u8, ntype, "actor_decl")) {
            try emitIndent(w, indent);
            try w.writeAll(nodeText(source, child));
            try w.writeAll("\n\n");
        } else {
            try emitIndent(w, indent);
            try w.writeAll(nodeText(source, child));
            try w.writeAll("\n");
        }
    }
}

fn formatFn(source: []const u8, node: ts.TSNode, w: anytype, indent: u32) anyerror!void {
    try emitIndent(w, indent);
    // Reconstruct fn signature
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "block")) {
            try w.writeAll(" {\n");
            try formatBlock(source, child, w, indent + 1);
            try emitIndent(w, indent);
            try w.writeAll("}\n\n");
        } else {
            if (i > 0 and !std.mem.eql(u8, ct, "(") and !std.mem.eql(u8, ct, ")") and !std.mem.eql(u8, ct, ",")) {
                const prev = ts.ts_node_child(node, i - 1);
                const pt = std.mem.span(ts.ts_node_type(prev));
                if (!std.mem.eql(u8, pt, "(") and !std.mem.eql(u8, pt, ",")) {
                    try w.writeAll(" ");
                }
            }
            try w.writeAll(nodeText(source, child));
        }
    }
}

fn formatBlock(source: []const u8, node: ts.TSNode, w: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}") or std.mem.eql(u8, ct, ";")) continue;

        try emitIndent(w, indent);
        const text = nodeText(source, child);
        try w.writeAll(text);

        if (std.mem.eql(u8, ct, "var_decl") or std.mem.eql(u8, ct, "ret") or
            std.mem.eql(u8, ct, "assign") or std.mem.eql(u8, ct, "assert_stmt") or
            std.mem.eql(u8, ct, "call"))
        {
            if (text.len == 0 or text[text.len - 1] != ';') {
                try w.writeAll(";");
            }
        }
        try w.writeAll("\n");
    }
}

fn formatStructLike(source: []const u8, node: ts.TSNode, w: anytype, indent: u32, keyword: []const u8) anyerror!void {
    const name = getFieldText(source, node, "name") orelse "Unknown";
    try emitIndent(w, indent);
    try w.writeAll(keyword);
    try w.writeAll(" ");
    try w.writeAll(name);
    try w.writeAll(" {\n");

    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier")) {
            try emitIndent(w, indent + 1);
            try w.writeAll(nodeText(source, child));
            if (i + 1 < count) {
                const next = ts.ts_node_child(node, i + 1);
                const nt = std.mem.span(ts.ts_node_type(next));
                if (std.mem.eql(u8, nt, "prim_type")) {
                    try w.writeAll(": ");
                    try w.writeAll(nodeText(source, next));
                    i += 1;
                }
            }
            try w.writeAll(",\n");
        } else if (std.mem.eql(u8, ct, "fn_decl")) {
            try formatFn(source, child, w, indent + 1);
        } else if (std.mem.eql(u8, ct, "type_name")) {
            const txt = nodeText(source, child);
            if (!std.mem.eql(u8, txt, name)) {
                try emitIndent(w, indent + 1);
                try w.writeAll(txt);
                try w.writeAll(",\n");
            }
        }
    }

    try emitIndent(w, indent);
    try w.writeAll("}\n\n");
}

fn formatTestDecl(source: []const u8, node: ts.TSNode, w: anytype, indent: u32) anyerror!void {
    try emitIndent(w, indent);
    const name = getFieldText(source, node, "name") orelse "\"test\"";
    try w.writeAll("test ");
    try w.writeAll(name);

    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "block")) {
            try w.writeAll(" {\n");
            try formatBlock(source, child, w, indent + 1);
            try emitIndent(w, indent);
            try w.writeAll("}\n\n");
        }
    }
}

fn emitIndent(w: anytype, indent: u32) anyerror!void {
    var i: u32 = 0;
    while (i < indent) : (i += 1) {
        try w.writeAll(" ");
    }
}

fn nodeText(source: []const u8, node: ts.TSNode) []const u8 {
    const s = ts.ts_node_start_byte(node);
    const e = ts.ts_node_end_byte(node);
    return source[s..e];
}

fn getFieldText(source: []const u8, node: ts.TSNode, field: []const u8) ?[]const u8 {
    const child = ts.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
    if (ts.ts_node_is_null(child)) return null;
    return nodeText(source, child);
}
