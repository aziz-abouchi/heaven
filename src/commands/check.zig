const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const ts = platform.ts;

const Scope = @import("../compiler/scope.zig").Scope;
const DiagnosticList = @import("../compiler/diagnostics.zig").DiagnosticList;
const Bridge = @import("../compiler/ast_bridge.zig").Bridge;
const Typer = @import("../compiler/typer.zig").Typer;

pub fn runCheck(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const source = platform.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |e| {
        platform.debug.print("Error reading {s}: {}\n", .{ file_path, e });
        return;
    };
    defer allocator.free(source);

    const parser = ts.ts_parser_new() orelse return;
    defer ts.ts_parser_delete(parser);

    if (!ts.ts_parser_set_language(parser, platform.tree_sitter_heaven())) return;

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return;
    defer ts.ts_tree_delete(tree);

const root = ts.ts_tree_root_node(tree);

platform.debug.print(
    "ROOT={s} children={d} error={}\n",
    .{
        ts.ts_node_type(root),
        ts.ts_node_child_count(root),
        ts.ts_node_has_error(root),
    },
);

    var store = expr.Store.init(allocator);
    defer store.deinit();

    var scope = Scope.init(allocator);
    try scope.addBuiltins();
    defer scope.deinit();

    var diags = DiagnosticList.init(allocator);
    defer diags.deinit();

    var bridge = Bridge.init(allocator, &store, &scope, &diags, source);
    try bridge.buildFile(root);

    var typer = Typer.init(allocator, &store, &diags);
    defer typer.deinit();
    typer.checkAll();

    if (diags.items.items.len > 0) {
        diags.print(file_path);
        platform.debug.print("\n⚠ {d} diagnostic(s)\n", .{diags.items.items.len});
    } else {
        platform.debug.print("✓ {s} — {d} expressions, 0 errors\n", .{ file_path, store.len() });
    }
}
