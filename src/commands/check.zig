const std = @import("std");
const expr = @import("expr");
const platform = @import("platform");
const ts = platform.ts;

const Scope = @import("../compiler/scope.zig").Scope;
const DiagnosticList = @import("../compiler/diagnostics.zig").DiagnosticList;
const Bridge = @import("../compiler/ast_bridge.zig").Bridge;
const Typer = @import("../compiler/typer.zig").Typer;
const scope_check = @import("../core/scope_check.zig");

pub fn runCheck(allocator: std.mem.Allocator, file_path: []const u8) !void {
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

    // platform.debug.print("ROOT={s} children={d} error={}\n", .{ts.ts_node_type(root), ts.ts_node_child_count(root), ts.ts_node_has_error(root),},);

    var store = expr.Store.init(allocator);
    defer store.deinit();

    var scope = Scope.init(allocator);
    try scope.addBuiltins();
    defer scope.deinit();

    var diags = DiagnosticList.init(allocator);
    defer diags.deinit();

    var bridge = Bridge.init(allocator, &store, &scope, &diags, source);
    defer bridge.deinitRoots();
    try bridge.buildFile(root);

    // DEBUG temporaire (Session 44, étape 1) : valider roots.len()
    // sur les fichiers de test avant d'écrire le walker.
    // Activable par HEAVEN_CHECK_DEBUG=1.
    if (std.process.hasEnvVar(allocator, "HEAVEN_CHECK_DEBUG") catch false) {
        std.debug.print("[roots] {s}: roots.len()={d}\n", .{ file_path, bridge.roots.items.len });
        for (bridge.roots.items, 0..) |rid, i| {
            const rn = store.get(rid);
            const nm = if (rn.payload < store.interner.list.items.len)
                store.interner.resolve(rn.payload)
            else
                "?";
            std.debug.print("  root[{d}] id={d} tag={s} payload='{s}'\n", .{ i, rid, @tagName(rn.tag), nm });
        }
    }

    var typer = Typer.init(allocator, &store, &diags);
    defer typer.deinit();
    typer.checkAll();

    // v2 : walker unbound. Opt-in via HEAVEN_CHECK_STRICT=1 tant que
    // les patterns de clause ne sont pas collectés (cf. _check_v2_plan.md).
    var unbound: usize = 0;
    if (std.process.hasEnvVar(allocator, "HEAVEN_CHECK_STRICT") catch false) {
        unbound = scope_check.checkUnboundV2(allocator, &store, bridge.roots.items, file_path);
    }

    if (diags.items.items.len > 0 or unbound > 0) {
        diags.print(file_path);
        return error.HasDiagnostics;
    }
}
