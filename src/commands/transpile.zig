const std = @import("std");
const platform = @import("platform");
const ts = platform.ts;

const Target = enum {
    c_lang,
    heaven,
    zig_lang,
    latex,
};

pub fn runTranspile(allocator: std.mem.Allocator, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        platform.debug.print(
            \\Usage: heaven transpile [options] <file> 
            \\Options: 
            \\ --to c Transpile to C (default) 
            \\ --to heaven Transpile to Heaven 
            \\ --to latex Transpile to LaTeX
            \\Supported input: .hvn, .c, .zig
            \\ 
        , .{});
        return;
    }

    var target: Target = .c_lang;
    const file_path: []const u8 = args[args.len - 1];
    var i: usize = 0;
    while (i < args.len - 1) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--to") and i + 1 < args.len) {
            const t = args[i + 1];
            if (std.mem.eql(u8, t, "c")) target = .c_lang else if (std.mem.eql(u8, t, "heaven") or std.mem.eql(u8, t, "hvn")) target = .heaven else if (std.mem.eql(u8, t, "zig")) target = .zig_lang else if (std.mem.eql(u8, t, "latex")) target = .latex;
            i += 1;
        }
    }

    const source = platform.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch {
        // platform.debug.print("Error reading {s}: {}\n", .{ file_path, e });
        return;
    };
    defer allocator.free(source);

    const src_lang = detectLang(file_path);

    const parser = ts.ts_parser_new() orelse return;
    defer ts.ts_parser_delete(parser);

    const lang_set_ok = switch (src_lang) {
        .heaven => ts.ts_parser_set_language(parser, @ptrCast(platform.tree_sitter_heaven())),
        .c_lang => ts.ts_parser_set_language(parser, @ptrCast(platform.tree_sitter_c())),
        .zig_lang => ts.ts_parser_set_language(parser, @ptrCast(platform.tree_sitter_zig())),
        .latex => false,
    };

    if (!lang_set_ok) {
        // platform.debug.print("Cannot set language for {s}\n", .{file_path});
        return;
    }

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return;
    defer ts.ts_tree_delete(tree);
    const root = ts.ts_tree_root_node(tree);

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);
    var w = output.writer(allocator);

    platform.debug.print("Transpiling {s} ({s} -> {s})\n", .{
        file_path,
        @tagName(src_lang),
        @tagName(target),
    });

    switch (target) {
        .c_lang => try transpileToC(source, root, &w, src_lang),
        .latex => try transpileToLatex(source, root, &w),
        .heaven => try transpileToHeaven(source, root, &w, src_lang),
        .zig_lang => {
            // platform.debug.print("Zig output not yet supported\n", .{});
            return;
        },
    }

    const ext = switch (target) {
        .c_lang => ".c",
        .heaven => ".hvn",
        .latex => ".tex",
        .zig_lang => ".zig",
    };

    var out_path_buf: [256]u8 = undefined;
    const out_path = std.fmt.bufPrint(&out_path_buf, "output{s}", .{ext}) catch "output";

    try platform.fs.cwd().writeFile(.{ .sub_path = out_path, .data = output.items });
    // platform.debug.print("Generated {s} ({d} bytes)\n", .{ out_path, output.items.len });
}

fn detectLang(path: []const u8) Target {
    if (std.mem.endsWith(u8, path, ".hvn")) return .heaven;
    if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h")) return .c_lang;
    if (std.mem.endsWith(u8, path, ".zig")) return .zig_lang;
    return .heaven;
}

fn transpileToC(source: []const u8, root: ts.TSNode, w: anytype, src_lang: Target) anyerror!void {
    switch (src_lang) {
        .heaven => {
            const compile = @import("compile.zig");
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
                const ntype = compile.span(ts.ts_node_type(child));

                if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) {
                    try compile.emitFnDecl(std.heap.page_allocator, source, child, w, w);
                } else if (std.mem.eql(u8, ntype, "struct_decl")) {
                    try compile.emitStructDecl(source, child, w);
                } else if (std.mem.eql(u8, ntype, "enum_decl")) {
                    try compile.emitEnumDecl(source, child, w);
                } else if (std.mem.eql(u8, ntype, "effect_decl")) {
                    try compile.emitEffectDecl(source, child, w);
                } else if (std.mem.eql(u8, ntype, "test_decl")) {
                    try compile.emitTestDecl(source, child, w);
                }
            }
        },
        .c_lang => {
            try w.writeAll(source);
        },
        else => {
            try w.writeAll("// Not supported\n");
        },
    }
}

fn transpileToLatex(source: []const u8, root: ts.TSNode, w: anytype) anyerror!void {
    try w.writeAll("\\documentclass{article}\n");
    try w.writeAll("\\usepackage{listings}\n");
    try w.writeAll("\\usepackage{amsmath}\n");
    try w.writeAll("\\begin{document}\n\n");
    try w.writeAll("\\section{Heaven Source}\n\n");
    try w.writeAll("\\begin{lstlisting}\n");

    const count = ts.ts_node_child_count(root);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = std.mem.span(ts.ts_node_type(child));
        const sb = ts.ts_node_start_byte(child);
        const eb = ts.ts_node_end_byte(child);
        const text = source[sb..eb];

        if (std.mem.eql(u8, ntype, "fn_decl") or
            std.mem.eql(u8, ntype, "struct_decl") or
            std.mem.eql(u8, ntype, "enum_decl"))
        {
            try w.writeAll(text);
            try w.writeAll("\n\n");
        }
    }

    try w.writeAll("\\end{lstlisting}\n\n");
    try w.writeAll("\\section{Functions}\n\n");

    i = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ntype, "fn_decl")) {
            const name = getFieldText(source, child, "name") orelse "f";
            try w.writeAll("\\begin{equation}\n");
            try std.fmt.format(w.*, "\\text{{{s}}} : ", .{name});
            try emitLatexType(source, child, w);
            try w.writeAll("\n\\end{equation}\n\n");
        }
    }

    try w.writeAll("\\end{document}\n");
}

fn transpileToHeaven(source: []const u8, root: ts.TSNode, w: anytype, src_lang: Target) anyerror!void {
    switch (src_lang) {
        .heaven => {
            try w.writeAll(source);
        },
        .c_lang => {
            try w.writeAll("-- Transpiled from C to Heaven\n\n");
            try transpileCToHeaven(source, root, w);
        },
        else => {
            try w.writeAll("-- Transpilation not yet supported\n");
        },
    }
}

fn transpileCToHeaven(source: []const u8, root: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(root);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = std.mem.span(ts.ts_node_type(child));
        const sb = ts.ts_node_start_byte(child);
        const eb = ts.ts_node_end_byte(child);
        const text = source[sb..eb];

        if (std.mem.eql(u8, ntype, "function_definition")) {
            try translateCFunction(source, child, w);
        } else if (std.mem.eql(u8, ntype, "declaration")) {
            try w.writeAll("-- C: ");
            try w.writeAll(text[0..@min(text.len, 60)]);
            try w.writeAll("\n");
        } else if (std.mem.eql(u8, ntype, "comment")) {
            try w.writeAll(text);
            try w.writeAll("\n");
        } else if (std.mem.eql(u8, ntype, "preproc_include")) {
            try w.writeAll("-- ");
            try w.writeAll(text);
            try w.writeAll("\n");
        }
    }
}

fn translateCFunction(source: []const u8, node: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var ret_type: []const u8 = "i64";
    var fn_name: []const u8 = "unknown";
    var i: u32 = 0;

    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ct, "primitive_type") or std.mem.eql(u8, ct, "type_identifier")) {
            ret_type = mapCType(nodeText(source, child));
        } else if (std.mem.eql(u8, ct, "function_declarator")) {
            const dc = ts.ts_node_child_count(child);
            var j: u32 = 0;
            while (j < dc) : (j += 1) {
                const dch = ts.ts_node_child(child, j);
                const dt = std.mem.span(ts.ts_node_type(dch));
                if (std.mem.eql(u8, dt, "identifier")) {
                    fn_name = nodeText(source, dch);
                } else if (std.mem.eql(u8, dt, "parameter_list")) {
                    try w.writeAll("fn ");
                    try w.writeAll(fn_name);
                    try w.writeAll("(");
                    try translateCParams(source, dch, w);
                    try w.writeAll(")");
                }
            }
        } else if (std.mem.eql(u8, ct, "compound_statement")) {
            if (!std.mem.eql(u8, ret_type, "void")) {
                try w.writeAll(" -> ");
                try w.writeAll(ret_type);
            }
            try w.writeAll(" {\n");
            try translateCBody(source, child, w, 1);
            try w.writeAll("}\n\n");
        }
    }
}

fn translateCParams(source: []const u8, node: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "parameter_declaration")) {
            if (!first) try w.writeAll(", ");
            first = false;
            try translateCParam(source, child, w);
        }
    }
}

fn translateCParam(source: []const u8, node: ts.TSNode, w: anytype) anyerror!void {
    var pname: []const u8 = "arg";
    var ptype: []const u8 = "i64";
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "identifier")) {
            pname = nodeText(source, child);
        } else if (std.mem.eql(u8, ct, "primitive_type") or std.mem.eql(u8, ct, "type_identifier")) {
            ptype = mapCType(nodeText(source, child));
        }
    }
    try w.writeAll(pname);
    try w.writeAll(": ");
    try w.writeAll(ptype);
}

fn translateCBody(source: []const u8, node: ts.TSNode, w: anytype, indent: u32) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "{") or std.mem.eql(u8, ct, "}")) continue;

        if (std.mem.eql(u8, ct, "return_statement")) {
            var j: u32 = 0;
            while (j < indent) : (j += 1) try w.writeAll("    ");
            try w.writeAll("return ");
            const rc = ts.ts_node_child_count(child);
            var k: u32 = 0;
            while (k < rc) : (k += 1) {
                const rch = ts.ts_node_child(child, k);
                const rt = std.mem.span(ts.ts_node_type(rch));
                if (std.mem.eql(u8, rt, "return") or std.mem.eql(u8, rt, ";")) continue;
                try w.writeAll(nodeText(source, rch));
            }
            try w.writeAll(";\n");
        } else if (std.mem.eql(u8, ct, "declaration")) {
            var j: u32 = 0;
            while (j < indent) : (j += 1) try w.writeAll("    ");
            try w.writeAll("let ");
            try w.writeAll(nodeText(source, child));
            try w.writeAll("\n");
        } else if (!std.mem.eql(u8, ct, ";")) {
            var j: u32 = 0;
            while (j < indent) : (j += 1) try w.writeAll("    ");
            try w.writeAll(nodeText(source, child));
            try w.writeAll(";\n");
        }
    }
}

fn mapCType(t: []const u8) []const u8 {
    if (std.mem.eql(u8, t, "int") or std.mem.eql(u8, t, "long")) return "i64";
    if (std.mem.eql(u8, t, "double") or std.mem.eql(u8, t, "float")) return "f64";
    if (std.mem.eql(u8, t, "char")) return "String";
    if (std.mem.eql(u8, t, "void")) return "void";
    return t;
}

fn emitAllDecls(source: []const u8, root: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(root);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const sb = ts.ts_node_start_byte(child);
        const eb = ts.ts_node_end_byte(child);
        try w.writeAll("// ");
        try w.writeAll(source[sb..@min(eb, sb + 60)]);
        try w.writeAll("\n");
    }
}

fn emitLatexType(source: []const u8, node: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var has_params = false;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "params")) {
            has_params = true;
            try emitLatexParams(source, child, w);
        } else if (std.mem.eql(u8, ct, "prim_type")) {
            if (has_params) try w.writeAll(" \to ");
            const t = nodeText(source, child);
            if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "Int")) {
                try w.writeAll("\\mathbb{Z}");
            } else if (std.mem.eql(u8, t, "f64") or std.mem.eql(u8, t, "Float")) {
                try w.writeAll("\\mathbb{R}");
            } else if (std.mem.eql(u8, t, "Bool")) {
                try w.writeAll("\\mathbb{B}");
            } else {
                try w.writeAll("\text{");
                try w.writeAll(t);
                try w.writeAll("}");
            }
        }
    }
    if (!has_params) {
        try w.writeAll("\text{void}");
    }
}

fn emitLatexParams(source: []const u8, node: ts.TSNode, w: anytype) anyerror!void {
    const count = ts.ts_node_child_count(node);
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        const ct = std.mem.span(ts.ts_node_type(child));
        if (std.mem.eql(u8, ct, "param")) {
            if (!first) try w.writeAll(" \times ");
            first = false;
            const pc = ts.ts_node_child_count(child);
            var j: u32 = 0;
            while (j < pc) : (j += 1) {
                const pch = ts.ts_node_child(child, j);
                if (std.mem.eql(u8, std.mem.span(ts.ts_node_type(pch)), "prim_type")) {
                    const t = nodeText(source, pch);
                    if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "Int")) {
                        try w.writeAll("\\mathbb{Z}");
                    } else if (std.mem.eql(u8, t, "f64") or std.mem.eql(u8, t, "Float")) {
                        try w.writeAll("\\mathbb{R}");
                    } else {
                        try w.writeAll("\text{");
                        try w.writeAll(t);
                        try w.writeAll("}");
                    }
                }
            }
        }
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
