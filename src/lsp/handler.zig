const std = @import("std");
const expr = @import("expr");
const protocol = @import("protocol");
const platform = @import("platform");
const ts = platform.ts;
const Scope = @import("../compiler/scope.zig").Scope;
const DiagnosticList = @import("../compiler/diagnostics.zig").DiagnosticList;
const Bridge = @import("../compiler/ast_bridge.zig").Bridge;
const Typer = @import("../compiler/typer.zig").Typer;

pub fn handleInitialize(allocator: std.mem.Allocator, id: i64) anyerror![]u8 {
    const caps = "{" ++ "\"capabilities\":{" ++ "\"textDocumentSync\":1," ++ "\"hoverProvider\":true," ++ "\"completionProvider\":{\"triggerCharacters\":[\".\",\":\"]}," ++ "\"documentSymbolProvider\":true" ++ "}," ++ "\"serverInfo\":{\"name\":\"heaven-lsp\",\"version\":\"0.1.0\"}" ++ "}";
    return protocol.formatResponse(allocator, id, caps);
}

pub fn handleShutdown(allocator: std.mem.Allocator, id: i64) anyerror![]u8 {
    return protocol.formatResponse(allocator, id, "null");
}

pub fn handleHover(allocator: std.mem.Allocator, id: i64) anyerror![]u8 {
    const result = "{\"contents\":{\"kind\":\"markdown\",\"value\":\"Heaven type info coming soon\"}}";
    return protocol.formatResponse(allocator, id, result);
}

pub fn handleHoverWithText(allocator: std.mem.Allocator, id: i64, parser: *ts.TSParser, text: []const u8, line: u32, col: u32) anyerror![]u8 {
    const tree = ts.ts_parser_parse_string(parser, null, text.ptr, @intCast(text.len));
    if (tree == null) return handleHover(allocator, id);
    defer ts.ts_tree_delete(tree.?);

    const root = ts.ts_tree_root_node(tree.?);
    const point = ts.TSPoint{ .row = line, .column = col };
    const node = ts.ts_node_descendant_for_point_range(root, point, point);

    if (ts.ts_node_is_null(node)) return handleHover(allocator, id);

    const ntype = std.mem.span(ts.ts_node_type(node));
    const sb = ts.ts_node_start_byte(node);
    const eb = ts.ts_node_end_byte(node);
    const name = text[sb..eb];

    var store = expr.Store.init(allocator);
    defer store.deinit();
    var scope = Scope.init(allocator);
    defer scope.deinit();
    try scope.addBuiltins();
    var diags = DiagnosticList.init(allocator);
    defer diags.deinit();

    var bridge = Bridge.init(allocator, &store, &scope, &diags, text);
    bridge.buildFile(root) catch {};

    const info = scope.lookup(name);
    var msg_buf: [256]u8 = undefined;
    const msg = if (info) |i|
        std.fmt.bufPrint(&msg_buf, "**{s}** : {s} ({s})", .{ name, i.type_name, @tagName(i.kind) }) catch name
    else
        std.fmt.bufPrint(&msg_buf, "**{s}** ({s})", .{ name, ntype }) catch name;

    var result_buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(&result_buf, "{{\"contents\":{{\"kind\":\"markdown\",\"value\":\"{s}\"}}}}", .{msg}) catch
        return handleHover(allocator, id);

    return protocol.formatResponse(allocator, id, result);
}

pub fn handleCompletion(allocator: std.mem.Allocator, id: i64) anyerror![]u8 {
    const result =
        \\{
        \\ "isIncomplete":false,
        \\ items":[
        \\     {"label":"fn","kind":14,"detail":"function declaration","insertText":"fn ${1:name}(${2:args}) -> ${3:type} {\n\t${0}\n}","insertTextFormat":2}, 
        \\     {"label":"let","kind":14,"detail":"variable binding","insertText":"let ${1:name} = ${0};","insertTextFormat":2},
        \\     {"label":"struct","kind":22,"detail":"struct type","insertText":"struct ${1:Name} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"enum","kind":13,"detail":"enum type","insertText":"enum ${1:Name} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"match","kind":14,"detail":"pattern match","insertText":"match ${1:expr} {\n\t${2:pattern} => ${0},\n}","insertTextFormat":2},
        \\     {"label":"if","kind":14,"detail":"conditional"},
        \\     {"label":"for","kind":14,"detail":"for loop","insertText":"for ${1:i} in ${2:range} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"while","kind":14,"detail":"while loop","insertText":"while ${1:cond} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"return","kind":14,"detail":"return value"},
        \\     {"label":"effect","kind":11,"detail":"algebraic effect","insertText":"effect ${1:Name} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"handler","kind":11,"detail":"effect handler","insertText":"handler ${1:Name} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"perform","kind":14,"detail":"perform effect"},
        \\     {"label":"actor","kind":5,"detail":"actor declaration","insertText":"actor ${1:Name} {\n\tstate: ${2:type},\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"spawn","kind":14,"detail":"spawn actor"},
        \\     {"label":"send","kind":14,"detail":"send message"},
        \\     {"label":"impl","kind":5,"detail":"implementation block","insertText":"impl ${1:Type} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"test","kind":12,"detail":"test block","insertText":"test "${1:name}" {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"fact","kind":14,"detail":"logic fact","insertText":"fact ${1:pred}(${0}).","insertTextFormat":2},
        \\     {"label":"rule","kind":14,"detail":"logic rule","insertText":"rule ${1:head} :- ${0}.","insertTextFormat":2},
        \\     {"label":"theorem","kind":14,"detail":"theorem","insertText":"theorem ${1:name} : ${2:prop} {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"axiom","kind":14,"detail":"axiom declaration"},
        \\     {"label":"class","kind":5,"detail":"type class","insertText":"class ${1:Name} a {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"instance","kind":5,"detail":"type class instance"},
        \\     {"label":"forall","kind":14,"detail":"universal quantification"},
        \\     {"label":"exists","kind":14,"detail":"existential quantification"},
        \\     {"label":"category","kind":5,"detail":"category theory"},
        \\     {"label":"functor","kind":5,"detail":"functor declaration"},
        \\     {"label":"monad","kind":5,"detail":"monad declaration"},
        \\     {"label":"explain","kind":14,"detail":"narrative block","insertText":"explain {\n\t${0}\n}","insertTextFormat":2},
        \\     {"label":"contract","kind":5,"detail":"contract declaration"},
        \\     {"label":"sensor","kind":5,"detail":"energy sensor"},
        \\     {"label":"monitor","kind":5,"detail":"energy monitor"},
        \\     {"label":"evolve","kind":14,"detail":"evolution declaration"},
        \\     {"label":"transpile","kind":14,"detail":"transpile block"},
        \\     {"label":"extern","kind":14,"detail":"FFI extern block"},
        \\     {"label":"vessel","kind":14,"detail":"WASM vessel"},
        \\     {"label":"rewrite","kind":14,"detail":"rewrite rule","insertText":"rewrite ${1:lhs} => ${0:rhs}","insertTextFormat":2},
        \\     {"label":"print","kind":3,"detail":"print value"},
        \\     {"label":"assert","kind":3,"detail":"assert condition"}
        \\ ]
        \\}
    ;
    return protocol.formatResponse(allocator, id, result);
}

pub fn handleDocumentSymbols(allocator: std.mem.Allocator, id: i64, parser: *ts.TSParser, text: []const u8) anyerror![]u8 {
    const tree = ts.ts_parser_parse_string(parser, null, text.ptr, @intCast(text.len));
    if (tree == null) return protocol.formatResponse(allocator, id, "[]");
    defer ts.ts_tree_delete(tree.?);

    const root = ts.ts_tree_root_node(tree.?);
    const count = ts.ts_node_child_count(root);

    var symbols = std.ArrayListUnmanaged(u8){};
    defer symbols.deinit(allocator);
    const w = symbols.writer(allocator);

    try w.writeAll("[");
    var first = true;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const ntype = std.mem.span(ts.ts_node_type(child));

        if (std.mem.eql(u8, ntype, "comment")) continue;

        const name_node = ts.ts_node_child_by_field_name(child, "name", 4);
        if (ts.ts_node_is_null(name_node)) continue;

        const sb = ts.ts_node_start_byte(name_node);
        const eb = ts.ts_node_end_byte(name_node);
        const name = text[sb..eb];
        const start = ts.ts_node_start_point(child);
        const end = ts.ts_node_end_point(child);

        const kind: u8 = if (std.mem.eql(u8, ntype, "fn_decl") or std.mem.eql(u8, ntype, "dist_fn")) 12 else if (std.mem.eql(u8, ntype, "struct_decl")) 23 else if (std.mem.eql(u8, ntype, "enum_decl")) 10 else if (std.mem.eql(u8, ntype, "class_decl")) 5 else if (std.mem.eql(u8, ntype, "effect_decl")) 11 else if (std.mem.eql(u8, ntype, "actor_decl")) 5 else if (std.mem.eql(u8, ntype, "test_decl")) 12 else 13;

        if (!first) try w.writeAll(",");
        first = false;

        try w.writeAll("{\"name\":\"");
        try w.writeAll(name);
        try w.writeAll("\",\"kind\":");
        try std.fmt.format(w, "{d}", .{kind});
        try w.writeAll(",\"range\":{\"start\":{\"line\":");
        try std.fmt.format(w, "{d}", .{start.row});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{start.column});
        try w.writeAll("},\"end\":{\"line\":");
        try std.fmt.format(w, "{d}", .{end.row});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{end.column});
        try w.writeAll("}},\"selectionRange\":{\"start\":{\"line\":");
        try std.fmt.format(w, "{d}", .{start.row});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{start.column});
        try w.writeAll("},\"end\":{\"line\":");
        try std.fmt.format(w, "{d}", .{start.row});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{start.column + @as(u32, @intCast(name.len))});
        try w.writeAll("}}}");
    }
    try w.writeAll("]");

    return protocol.formatResponse(allocator, id, symbols.items);
}

pub fn runDiagnostics(allocator: std.mem.Allocator, parser: *ts.TSParser, uri: []const u8, text: []const u8) anyerror![]u8 {
    const tree = ts.ts_parser_parse_string(parser, null, text.ptr, @intCast(text.len));
    if (tree == null) {
        return protocol.formatDiagnostics(allocator, uri, "[]");
    }
    defer ts.ts_tree_delete(tree.?);

    const root = ts.ts_tree_root_node(tree.?);

    var store = expr.Store.init(allocator);
    defer store.deinit();
    var scope = Scope.init(allocator);
    defer scope.deinit();
    try scope.addBuiltins();
    var diags = DiagnosticList.init(allocator);
    defer diags.deinit();

    var bridge = Bridge.init(allocator, &store, &scope, &diags, text);
    bridge.buildFile(root) catch {};

    var typer = Typer.init(allocator, &store, &diags);
    defer typer.deinit();
    typer.checkAll();

    var diag_json = std.ArrayListUnmanaged(u8){};
    defer diag_json.deinit(allocator);
    const w = diag_json.writer(allocator);

    try w.writeAll("[");
    for (diags.items.items, 0..) |d, idx| {
        if (idx > 0) try w.writeAll(",");
        const sev: u8 = switch (d.severity) {
            .err => 1,
            .warning => 2,
            .info => 3,
            .hint => 4,
        };
        try w.writeAll("{\"range\":{\"start\":{\"line\":");
        try std.fmt.format(w, "{d}", .{d.start.line});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{d.start.col});
        try w.writeAll("},\"end\":{\"line\":");
        try std.fmt.format(w, "{d}", .{d.end.line});
        try w.writeAll(",\"character\":");
        try std.fmt.format(w, "{d}", .{d.end.col});
        try w.writeAll("}},\"severity\":");
        try std.fmt.format(w, "{d}", .{sev});
        try w.writeAll(",\"source\":\"heaven\",\"message\":\"");
        try w.writeAll(d.message);
        try w.writeAll("\"}");
    }
    try w.writeAll("]");

    return protocol.formatDiagnostics(allocator, uri, diag_json.items);
}
