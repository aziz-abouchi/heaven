const std = @import("std");
const platform = @import("platform");
const ts = platform.ts;

const headers = @import("headers");
const Writer = std.ArrayListUnmanaged(u8).Writer;

pub fn runCompile(allocator: std.mem.Allocator, file_path: []const u8) !void {
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

    // Header
    try headers.writeStandardHeaders(w);

    try w.writeAll("typedef int64_t i64;\n");
    try w.writeAll("typedef double f64;\n");
    try w.writeAll("typedef const char* String;\n\n");

    // Forward declarations
    var fwd = std.ArrayListUnmanaged(u8){};
    defer fwd.deinit(allocator);
    var fw = fwd.writer(allocator);

    // Body
    var body = std.ArrayListUnmanaged(u8){};
    defer body.deinit(allocator);
    var bw = body.writer(allocator);

    const count = ts.ts_node_child_count(root);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) {
            try emitFnDecl(allocator, source, child, &fw, &bw);
        } else if (std.mem.eql(u8, ntype, "struct_decl")) {
            try emitStructDecl(source, child, &bw);
        } else if (std.mem.eql(u8, ntype, "enum_decl")) {
            try emitEnumDecl(source, child, &bw);
        } else if (std.mem.eql(u8, ntype, "effect_decl")) {
            try emitEffectDecl(source, child, &bw);
        } else if (std.mem.eql(u8, ntype, "test_decl")) {
            try emitTestDecl(source, child, &bw);
        }
    }

    // If there are tests and no main, generate a test main
    var has_main = false;
    var test_names = std.ArrayListUnmanaged(u8){};
    defer test_names.deinit(allocator);
    var tw = test_names.writer(allocator);
    i = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ntype, "fn_decl")) {
            const name = getFieldText(source, child, "name") orelse "";
            if (std.mem.eql(u8, name, "main")) has_main = true;
        } else if (std.mem.eql(u8, ntype, "test_decl")) {
            const name_node = ts.ts_node_child_by_field_name(child, "name", 4);
            if (!ts.ts_node_is_null(name_node)) {
                const tn = nodeText(source, name_node);
                for (tn) |ch| {
                    if (ch >= 'a' and ch <= 'z' or ch >= 'A' and ch <= 'Z' or ch >= '0' and ch <= '9' or ch == '_') {
                        try tw.writeByte(ch);
                    }
                }
                try tw.writeByte('\n');
            }
        }
    }

    if (!has_main and test_names.items.len > 0) {
        try bw.writeAll("int main(void) {\n");
        var iter = std.mem.splitScalar(u8, test_names.items, '\n');
        while (iter.next()) |name| {
            if (name.len == 0) continue;
            try bw.writeAll("    __test_");
            try bw.writeAll(name);
            try bw.writeAll("();\n");
        }
        try bw.writeAll("    return 0;\n");
        try bw.writeAll("}\n");
    }

    // Assemble
    try w.writeAll("// Forward declarations\n");
    try w.writeAll(fwd.items);
    try w.writeAll("\n");
    try w.writeAll(body.items);

    const out_path = "output.c";
    try platform.fs.cwd().writeFile(.{ .sub_path = out_path, .data = output.items });
    // platform.debug.print("Generated {s} ({d} bytes)\n", .{ out_path, output.items.len });
}

pub fn emitFnDecl(allocator: std.mem.Allocator, source: []const u8, node: ts.TSNode, fw: anytype, bw: anytype) anyerror!void {
    const name = getFieldText(source, node, "name") orelse "unknown";
    const is_main = std.mem.eql(u8, name, "main");

    // Find return type
    var ret_type: []const u8 = "void";
    var has_return_type = false;
    const count = ts.ts_node_child_count(node);
    var idx: u32 = 0;
    while (idx < count) : (idx += 1) {
        const child = ts.ts_node_child(node, idx);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "prim_type")) {
            ret_type = mapType(nodeText(source, child));
            has_return_type = true;
        }
    }

    if (is_main) {
        ret_type = "int";
        has_return_type = true;
    }

    // Collect params
    var params_buf = std.ArrayListUnmanaged(u8){};
    defer params_buf.deinit(allocator);
    var pw = params_buf.writer(allocator);

    idx = 0;
    while (idx < count) : (idx += 1) {
        const child = ts.ts_node_child(node, idx);
        if (std.mem.eql(u8, span(ts.ts_node_type(child)), "params")) {
            try emitParams(source, child, &pw);
        }
    }

    if (params_buf.items.len == 0) {
        try pw.writeAll("void");
    }

    // Forward decl
    if (!is_main) {
        try std.fmt.format(fw.*, "{s} {s}({s});\n", .{ ret_type, name, params_buf.items });
    }

    // Function definition
    try std.fmt.format(bw.*, "{s} {s}({s})", .{ ret_type, name, params_buf.items });
    try bw.writeAll(" {\n");

    // Emit body
    idx = 0;
    while (idx < count) : (idx += 1) {
        const child = ts.ts_node_child(node, idx);
        if (std.mem.eql(u8, span(ts.ts_node_type(child)), "block")) {
            try emitBlock(source, child, bw, 1);
        }
    }

    if (is_main and !has_return_type) {
        try bw.writeAll("    return 0;\n");
    }

    try bw.writeAll("}\n\n");
}

pub fn emitParams(source: []const u8, node: ts.TSNode, pw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        if (std.mem.eql(u8, span(ts.ts_node_type(child)), "param")) {
            if (!first) try pw.writeAll(", ");
            first = false;
            try emitParam(source, child, pw);
        }
    }
}

pub fn emitParam(source: []const u8, node: ts.TSNode, pw: anytype) anyerror!void {
    var pname: []const u8 = "arg";
    var ptype: []const u8 = "i64";
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier") or std.mem.eql(u8, ct, "type_name")) {
            pname = nodeText(source, child);
        } else if (std.mem.eql(u8, ct, "prim_type")) {
            ptype = mapType(nodeText(source, child));
        }
    }
    if (std.mem.eql(u8, pname, "self")) {
        try pw.writeAll("void* self");
    } else {
        try std.fmt.format(pw.*, "{s} {s}", .{ ptype, pname });
    }
}

pub fn emitBlock(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}") or std.mem.eql(u8, ct, ";")) continue;
        try emitStmt(source, child, bw, indent);
    }
}

pub fn emitStmt(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const ntype = span(ts.ts_node_type(node));
    try emitIndent(bw, indent);

    if (std.mem.eql(u8, ntype, "var_decl")) {
        try emitVarDecl(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "ret")) {
        try bw.writeAll("return ");
        const count = ts.ts_node_child_count(node);
        if (count >= 2) {
            try emitExpr(source, ts.ts_node_child(node, 1), bw);
        }
        try bw.writeAll(";\n");
    } else if (std.mem.eql(u8, ntype, "assign")) {
        try emitAssign(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "if_stmt")) {
        try emitIfStmt(source, node, bw, indent);
        return;
    } else if (std.mem.eql(u8, ntype, "for_stmt")) {
        try emitForStmt(source, node, bw, indent);
        return;
    } else if (std.mem.eql(u8, ntype, "while_stmt")) {
        try emitWhileStmt(source, node, bw, indent);
        return;
    } else if (std.mem.eql(u8, ntype, "match_expr")) {
        try emitMatchExpr(source, node, bw, indent);
        return;
    } else if (std.mem.eql(u8, ntype, "comment")) {
        try bw.writeAll("// ");
        try bw.writeAll(nodeText(source, node));
        try bw.writeAll("\n");
        return;
    } else {
        try emitExpr(source, node, bw);
        try bw.writeAll(";\n");
    }
}

pub fn emitVarDecl(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const name = getFieldText(source, node, "name") orelse "_";
    var has_type = false;
    var val_node: ?ts.TSNode = null;
    var type_str: []const u8 = "i64";

    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "prim_type")) {
            type_str = mapType(nodeText(source, child));
            has_type = true;
        } else if (!std.mem.eql(u8, ct, "let") and
            !std.mem.eql(u8, ct, "var") and
            !std.mem.eql(u8, ct, "const") and
            !std.mem.eql(u8, ct, "mut") and
            !std.mem.eql(u8, ct, "identifier") and
            !std.mem.eql(u8, ct, "=") and
            !std.mem.eql(u8, ct, ";") and
            !std.mem.eql(u8, ct, "prim_type"))
        {
            val_node = child;
        }
    }

    // Infer type from value if not annotated
    if (!has_type) {
        if (val_node) |vn| {
            const vt = span(ts.ts_node_type(vn));
            if (std.mem.eql(u8, vt, "str")) {
                type_str = "String";
            } else if (std.mem.eql(u8, vt, "float")) {
                type_str = "f64";
            } else if (std.mem.eql(u8, vt, "bool_lit")) {
                type_str = "bool";
            } else if (std.mem.eql(u8, vt, "struct_lit")) {
                type_str = getFieldText(source, vn, "type") orelse "i64";
            }
        }
    }

    // Emit
    if (val_node) |vn| {
        const vt = span(ts.ts_node_type(vn));
        if (std.mem.eql(u8, vt, "arr")) {
            const arr_count = countArrayElems(vn);
            try bw.writeAll(type_str);
            try bw.writeAll(" ");
            try bw.writeAll(name);
            try bw.writeAll("[");
            try std.fmt.format(bw.*, "{d}", .{arr_count});
            try bw.writeAll("] = ");
            try emitArrayLit(source, vn, bw);
            try bw.writeAll(";\n");
        } else {
            try bw.writeAll(type_str);
            try bw.writeAll(" ");
            try bw.writeAll(name);
            try bw.writeAll(" = ");
            try emitExpr(source, vn, bw);
            try bw.writeAll(";\n");
        }
    } else {
        try bw.writeAll(type_str);
        try bw.writeAll(" ");
        try bw.writeAll(name);
        try bw.writeAll(";\n");
    }
}

pub fn emitAssign(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    if (count >= 3) {
        try emitExpr(source, ts.ts_node_child(node, 0), bw);
        try bw.writeAll(" ");
        try bw.writeAll(nodeText(source, ts.ts_node_child(node, 1)));
        try bw.writeAll(" ");
        try emitExpr(source, ts.ts_node_child(node, 2), bw);
    }
    try bw.writeAll(";\n");
}

pub fn emitIfStmt(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var phase: u8 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "if")) {
            try bw.writeAll("if (");
            phase = 1;
        } else if (std.mem.eql(u8, ct, "else")) {
            try emitIndent(bw, indent);
            try bw.writeAll("} else ");
            phase = 3;
        } else if (std.mem.eql(u8, ct, "block")) {
            if (phase == 1) {
                try bw.writeAll(") {\n");
            } else {
                try bw.writeAll("{\n");
            }
            try emitBlock(source, child, bw, indent + 1);
            phase += 1;
        } else if (phase == 1) {
            try emitExpr(source, child, bw);
        }
    }
    try emitIndent(bw, indent);
    try bw.writeAll("}\n");
}

pub fn emitForStmt(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var var_name: []const u8 = "i";
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier")) {
            var_name = nodeText(source, child);
        } else if (std.mem.eql(u8, ct, "range")) {
            const rc = ts.ts_node_child_count(child);
            if (rc >= 3) {
                const lo = nodeText(source, ts.ts_node_child(child, 0));
                const hi = nodeText(source, ts.ts_node_child(child, 2));
                try std.fmt.format(bw.*, "for (i64 {s} = {s}; {s} < {s}; {s}++) {{\n", .{ var_name, lo, var_name, hi, var_name });
            }
        } else if (std.mem.eql(u8, ct, "block")) {
            try emitBlock(source, child, bw, indent + 1);
            try emitIndent(bw, indent);
            try bw.writeAll("}\n");
        }
    }
}

pub fn emitWhileStmt(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    try bw.writeAll("while (");
    var phase: u8 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "while")) {
            phase = 1;
        } else if (std.mem.eql(u8, ct, "block")) {
            try bw.writeAll(") {\n");
            try emitBlock(source, child, bw, indent + 1);
            try emitIndent(bw, indent);
            try bw.writeAll("}\n");
        } else if (phase == 1) {
            try emitExpr(source, child, bw);
        }
    }
}

pub fn emitExpr(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const ntype = span(ts.ts_node_type(node));

    if (std.mem.eql(u8, ntype, "int") or
        std.mem.eql(u8, ntype, "float") or
        std.mem.eql(u8, ntype, "identifier"))
    {
        try bw.writeAll(nodeText(source, node));
    } else if (std.mem.eql(u8, ntype, "str")) {
        try bw.writeAll(nodeText(source, node));
    } else if (std.mem.eql(u8, ntype, "bool_lit")) {
        const text = nodeText(source, node);
        if (std.mem.eql(u8, text, "true")) {
            try bw.writeAll("1");
        } else {
            try bw.writeAll("0");
        }
    } else if (std.mem.eql(u8, ntype, "type_name")) {
        try bw.writeAll(nodeText(source, node));
    } else if (std.mem.eql(u8, ntype, "binary")) {
        try emitBinary(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "unary")) {
        try bw.writeAll("!");
        if (ts.ts_node_child_count(node) >= 2) {
            try emitExpr(source, ts.ts_node_child(node, 1), bw);
        }
    } else if (std.mem.eql(u8, ntype, "call")) {
        try emitCall(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "paren_expr")) {
        try bw.writeAll("(");
        if (ts.ts_node_child_count(node) >= 2) {
            try emitExpr(source, ts.ts_node_child(node, 1), bw);
        }
        try bw.writeAll(")");
    } else if (std.mem.eql(u8, ntype, "if_expr")) {
        try emitTernary(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "arr")) {
        try bw.writeAll("/* array */0");
    } else if (std.mem.eql(u8, ntype, "atom")) {
        try bw.writeAll("/* ");
        try bw.writeAll(nodeText(source, node));
        try bw.writeAll(" */0");
    } else if (std.mem.eql(u8, ntype, "arr")) {
        try emitArrayLit(source, node, bw);
    } else if (std.mem.eql(u8, ntype, "struct_lit")) {
        try emitStructLit(source, node, bw);
    } else {
        try bw.writeAll("/* ");
        try bw.writeAll(ntype);
        try bw.writeAll(" */0");
    }
}

pub fn emitBinary(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    if (count >= 3) {
        try emitExpr(source, ts.ts_node_child(node, 0), bw);
        try bw.writeAll(" ");
        try bw.writeAll(nodeText(source, ts.ts_node_child(node, 1)));
        try bw.writeAll(" ");
        try emitExpr(source, ts.ts_node_child(node, 2), bw);
    }
}

pub fn emitCall(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    if (count == 0) return;

    const first_child = ts.ts_node_child(node, 0);
    const fname = nodeText(source, first_child);
    const is_print = std.mem.eql(u8, fname, "print") or std.mem.eql(u8, fname, "println");

    if (is_print) {
        var i: u32 = 1;
        var arg_node: ?ts.TSNode = null;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = span(ts.ts_node_type(child));
            if (std.mem.eql(u8, ct, "(") or std.mem.eql(u8, ct, ")") or std.mem.eql(u8, ct, ",")) continue;
            arg_node = child;
            break;
        }
        if (arg_node) |an| {
            const at = span(ts.ts_node_type(an));
            if (std.mem.eql(u8, at, "str")) {
                try bw.writeAll("printf(\"%s");
                try bw.writeByte(0x5C);
                try bw.writeAll("n\", ");
                try emitExpr(source, an, bw);
                try bw.writeAll(")");
            } else if (std.mem.eql(u8, at, "float")) {
                try bw.writeAll("printf(\"%f");
                try bw.writeByte(0x5C);
                try bw.writeAll("n\", ");
                try emitExpr(source, an, bw);
                try bw.writeAll(")");
            } else {
                try bw.writeAll("printf(\"%ld");
                try bw.writeByte(0x5C);
                try bw.writeAll("n\", ");
                try emitExpr(source, an, bw);
                try bw.writeAll(")");
            }
        }
    } else {
        try emitExpr(source, first_child, bw);
        try bw.writeAll("(");
        var i: u32 = 1;
        var first_arg = true;
        while (i < count) : (i += 1) {
            const child = ts.ts_node_child(node, i);
            const ct = span(ts.ts_node_type(child));
            if (std.mem.eql(u8, ct, "(") or std.mem.eql(u8, ct, ")") or std.mem.eql(u8, ct, ",")) continue;
            if (!first_arg) try bw.writeAll(", ");
            first_arg = false;
            try emitExpr(source, child, bw);
        }
        try bw.writeAll(")");
    }
}

pub fn emitTernary(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var phase: u8 = 0;
    try bw.writeAll("(");
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "if")) {
            phase = 1;
        } else if (std.mem.eql(u8, ct, "then")) {
            try bw.writeAll(" ? ");
            phase = 2;
        } else if (std.mem.eql(u8, ct, "else")) {
            try bw.writeAll(" : ");
            phase = 3;
        } else {
            try emitExpr(source, child, bw);
        }
    }
    try bw.writeAll(")");
}

pub fn emitStructDecl(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const name = getFieldText(source, node, "name") orelse "Struct";
    try std.fmt.format(bw.*, "typedef struct {s} {{\n", .{name});
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier")) {
            const field_name = nodeText(source, child);
            var j: u32 = i + 1;
            while (j < count) : (j += 1) {
                const next = ts.ts_node_child(node, j);
                const nt = span(ts.ts_node_type(next));
                if (std.mem.eql(u8, nt, "prim_type")) {
                    try bw.writeAll(" ");
                    try bw.writeAll(mapType(nodeText(source, next)));
                    try bw.writeAll(" ");
                    try bw.writeAll(field_name);
                    try bw.writeAll(";\n");
                    i = j;
                    break;
                }
            }
        }
    }
    try std.fmt.format(bw.*, "}} {s};\n\n", .{name});
}

pub fn emitEnumDecl(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const name = getFieldText(source, node, "name") orelse "Enum";
    try std.fmt.format(bw.*, "typedef enum {{\n", .{});
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    var first = true;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        if (std.mem.eql(u8, span(ts.ts_node_type(child)), "type_name")) {
            const vname = nodeText(source, child);
            if (!std.mem.eql(u8, vname, name)) {
                if (!first) try bw.writeAll(",\n");
                first = false;
                try std.fmt.format(bw.*, " {s}_{s}", .{ name, vname });
            }
        }
    }
    try std.fmt.format(bw.*, "\n}} {s};\n\n", .{name});
}

pub fn emitMatchExpr(source: []const u8, node: ts.TSNode, bw: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    if (count < 2) return;

    // Premier enfant non-keyword = expression matchée
    var match_var: ?ts.TSNode = null;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "match") or std.mem.eql(u8, ct, "{") or
            std.mem.eql(u8, ct, "}") or std.mem.eql(u8, ct, ",") or
            std.mem.eql(u8, ct, "=>"))
        {
            continue;
        }
        match_var = child;
        i += 1;
        break;
    }

    if (match_var == null) return;

    var first_arm = true;
    var pending_pattern: ?ts.TSNode = null;

    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}") or
            std.mem.eql(u8, ct, ",") or std.mem.eql(u8, ct, "=>") or
            std.mem.eql(u8, ct, "_"))
        {
            continue;
        }

        if (std.mem.eql(u8, ct, "block")) {
            if (pending_pattern) |pat| {
                if (!first_arm) {
                    try bw.writeAll(" else ");
                }
                try bw.writeAll("if (");
                try emitExpr(source, match_var.?, bw);
                try bw.writeAll(" == ");
                try emitExpr(source, pat, bw);
                try bw.writeAll(") {\n");
                first_arm = false;
            } else {
                if (!first_arm) {
                    try bw.writeAll(" else ");
                }
                try bw.writeAll("{\n");
            }
            try emitBlock(source, child, bw, indent + 1);
            try emitIndent(bw, indent);
            try bw.writeAll("}");
            pending_pattern = null;
        } else {
            pending_pattern = child;
        }
    }
    try bw.writeAll("\n");
}

pub fn emitArrayLit(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    try bw.writeAll("{");
    const count = ts.ts_node_child_count(node);
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "[") or std.mem.eql(u8, ct, "]") or std.mem.eql(u8, ct, ",")) continue;
        if (!first) try bw.writeAll(", ");
        first = false;
        try emitExpr(source, child, bw);
    }
    try bw.writeAll("}");
}

pub fn emitStructLit(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    try bw.writeAll("(");
    const type_name = getFieldText(source, node, "type") orelse "Struct";
    try bw.writeAll(type_name);
    try bw.writeAll("){");
    const count = ts.ts_node_child_count(node);
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier")) {
            if (!first) try bw.writeAll(", ");
            first = false;
            try bw.writeAll(".");
            try bw.writeAll(nodeText(source, child));
            try bw.writeAll(" = ");
        } else if (std.mem.eql(u8, ct, "int") or std.mem.eql(u8, ct, "float") or std.mem.eql(u8, ct, "str") or std.mem.eql(u8, ct, "bool_lit") or std.mem.eql(u8, ct, "call") or std.mem.eql(u8, ct, "binary")) {
            try emitExpr(source, child, bw);
        }
    }
    try bw.writeAll("}");
}

pub fn countArrayElems(node: ts.TSNode) u32 {
    const count = ts.ts_node_child_count(node);
    var elems: u32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (!std.mem.eql(u8, ct, "[") and !std.mem.eql(u8, ct, "]") and !std.mem.eql(u8, ct, ",")) {
            elems += 1;
        }
    }
    return elems;
}

pub fn emitTestDecl(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const name_node = ts.ts_node_child_by_field_name(node, "name", 4);
    var test_name: []const u8 = "test";
    if (!ts.ts_node_is_null(name_node)) {
        test_name = nodeText(source, name_node);
    }

    try bw.writeAll("void __test_");
    // sanitize name
    for (test_name) |ch| {
        if (ch >= 'a' and ch <= 'z' or ch >= 'A' and ch <= 'Z' or ch >= '0' and ch <= '9' or ch == '_') {
            try bw.writeByte(ch);
        }
    }
    try bw.writeAll("(void) {\n");
    try bw.writeAll("    int __ok = 1;\n");

    // Emit body
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "block")) {
            try emitTestBody(source, child, bw);
        }
    }

    try bw.writeAll(" if (__ok) printf(\" PASS ");
    // Strip quotes from test name
    for (test_name) |ch| {
        if (ch != '"') {
            try bw.writeByte(ch);
        }
    }
    try bw.writeByte(0x5C);
    try bw.writeAll("n\");\n");
    try bw.writeAll("}\n\n");
}

pub fn emitTestBody(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}") or std.mem.eql(u8, ct, ";")) continue;

        if (std.mem.eql(u8, ct, "var_decl")) {
            try bw.writeAll("    ");
            try emitVarDecl(source, child, bw);
            /////
        } else if (std.mem.eql(u8, ct, "assert_stmt")) {
            try bw.writeAll(" if (!(");
            const ac = ts.ts_node_child_count(child);
            var j: u32 = 0;
            while (j < ac) : (j += 1) {
                const ach = ts.ts_node_child(child, j);
                const at = span(ts.ts_node_type(ach));
                if (std.mem.eql(u8, at, "assert") or std.mem.eql(u8, at, "assert_eq") or std.mem.eql(u8, at, "assert_ne") or std.mem.eql(u8, at, "assert_not") or std.mem.eql(u8, at, ";")) {
                    continue;
                }
                try emitExpr(source, ach, bw);
            }
            try bw.writeAll(")) { printf(\"FAIL");
            try bw.writeByte(0x5C);
            try bw.writeAll("n\"); __ok = 0; }\n");
        }
    }
}

pub fn emitEffectDecl(source: []const u8, node: ts.TSNode, bw: anytype) anyerror!void {
    var name: []const u8 = "Effect";
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;

    // Find name (first type_name child)
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "type_name")) {
            name = nodeText(source, child);
            break;
        }
    }

    try std.fmt.format(bw.*, "// Effect: {s}\n", .{name});
    try std.fmt.format(bw.*, "typedef struct Effect_{s} {{\n", .{name});

    i = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "fn_sig")) {
            const fn_name = getFieldText(source, child, "name");
            if (fn_name == null) {
                // fn_sig doesn't use field "name", find first identifier
                const sc = ts.ts_node_child_count(child);
                var j: u32 = 0;
                while (j < sc) : (j += 1) {
                    const sch = ts.ts_node_child(child, j);
                    if (std.mem.eql(u8, span(ts.ts_node_type(sch)), "identifier")) {
                        try bw.writeAll("    void* (*");
                        try bw.writeAll(nodeText(source, sch));
                        try bw.writeAll(")(void);\n");
                        break;
                    }
                }
            } else {
                try bw.writeAll("    void* (*");
                try bw.writeAll(fn_name.?);
                try bw.writeAll(")(void);\n");
            }
        }
    }

    try std.fmt.format(bw.*, "}} Effect_{s};\n", .{name});
    try std.fmt.format(bw.*, "Effect_{s}* __handler_{s} = NULL;\n\n", .{ name, name });
}

pub fn emitCFromRoot(source: []const u8, root: ts.TSNode, w: anytype) anyerror!void {
    try w.writeAll("#include <stdio.h>\n");
    try w.writeAll("#include <stdlib.h>\n");
    try w.writeAll("#include <stdint.h>\n");
    try w.writeAll("#include <string.h>\n");
    try w.writeAll("#include <stdbool.h>\n\n");
    try w.writeAll("typedef int64_t i64;\n");
    try w.writeAll("typedef double f64;\n");
    try w.writeAll("typedef const char* String;\n\n");

    const count = ts.ts_node_child_count(root);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) {
            try emitFnDecl(std.heap.page_allocator, source, child, w, w);
        } else if (std.mem.eql(u8, ntype, "struct_decl")) {
            try emitStructDecl(source, child, w);
        } else if (std.mem.eql(u8, ntype, "enum_decl")) {
            try emitEnumDecl(source, child, w);
        } else if (std.mem.eql(u8, ntype, "effect_decl")) {
            try emitEffectDecl(source, child, w);
        } else if (std.mem.eql(u8, ntype, "test_decl")) {
            try emitTestDecl(source, child, w);
        }
    }
}
// ─── Helpers ───

pub fn emitIndent(bw: anytype, indent: u32) anyerror!void {
    var i: u32 = 0;
    while (i < indent) : (i += 1) {
        try bw.writeAll(" ");
    }
}

pub fn mapType(t: []const u8) []const u8 {
    if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "i32") or std.mem.eql(u8, t, "Int")) return "i64";
    if (std.mem.eql(u8, t, "f64") or std.mem.eql(u8, t, "f32") or std.mem.eql(u8, t, "Float")) return "f64";
    if (std.mem.eql(u8, t, "Bool") or std.mem.eql(u8, t, "bool")) return "bool";
    if (std.mem.eql(u8, t, "String")) return "String";
    if (std.mem.eql(u8, t, "Nat")) return "i64";
    return "i64";
}

pub fn span(ptr: [*c]const u8) []const u8 {
    return std.mem.span(ptr);
}

pub fn nodeText(source: []const u8, node: ts.TSNode) []const u8 {
    const s = ts.ts_node_start_byte(node);
    const e = ts.ts_node_end_byte(node);
    return source[s..e];
}

pub fn getFieldText(source: []const u8, node: ts.TSNode, field: []const u8) ?[]const u8 {
    const child = ts.ts_node_child_by_field_name(node, field.ptr, @intCast(field.len));
    if (ts.ts_node_is_null(child)) return null;
    return nodeText(source, child);
}
