const std = @import("std");
const platform = @import("platform");
const ts = platform.ts;

pub fn runParse(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const source = platform.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch {
        // platform.debug.print("Error reading {s}: {}\n", .{ file_path, err });
        return;
    };
    defer allocator.free(source);

    const parser = ts.ts_parser_new() orelse {
        // platform.debug.print("Failed to create parser\n", .{});
        return;
    };
    defer ts.ts_parser_delete(parser);

    if (!ts.ts_parser_set_language(parser, platform.tree_sitter_heaven())) {
        // platform.debug.print("Failed to set language\n", .{});
        return;
    }

    const tree = ts.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse {
        // platform.debug.print("Failed to parse\n", .{});
        return;
    };
    defer ts.ts_tree_delete(tree);

    const root = ts.ts_tree_root_node(tree);
    const has_error = ts.ts_node_has_error(root);
    const child_count = ts.ts_node_child_count(root);

    if (has_error) {
        // platform.debug.print("⚠ Parse errors in {s}\n", .{file_path});
        printErrors(root, source);
    } else {
        // platform.debug.print("✓ {s} — {d} top-level declarations\n", .{ file_path, child_count });
    }

    // platform.debug.print("\n── Declarations ──\n", .{});
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = ts.ts_node_child(root, i);
        const node_type = ts.ts_node_type(child);
        const start = ts.ts_node_start_point(child);
        _ = start;
        const type_str = std.mem.span(node_type);
        _ = type_str;
        // platform.debug.print("  [{d}:{d}] {s}\n", .{ start.row + 1, start.column, type_str });
    }
}

fn printErrors(node: ts.TSNode, source: []const u8) void {
    const node_type = std.mem.span(ts.ts_node_type(node));

    if (ts.ts_node_is_missing(node)) {
        const start = ts.ts_node_start_point(node);
        platform.debug.print("  MISSING {s} at {d}:{d}\n", .{ node_type, start.row + 1, start.column });
    } else if (std.mem.eql(u8, node_type, "ERROR")) {
        const start = ts.ts_node_start_point(node);
        const end = ts.ts_node_end_point(node);
        const start_byte = ts.ts_node_start_byte(node);
        const end_byte = ts.ts_node_end_byte(node);
        const len = @min(end_byte - start_byte, 40);
        const snippet = source[start_byte .. start_byte + len];

        platform.debug.print("  ERROR [{d}:{d}-{d}:{d}] `{s}`\n", .{ start.row + 1, start.column, end.row + 1, end.column, snippet });
    }

    const count = ts.ts_node_child_count(node);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const child = ts.ts_node_child(node, i);
        if (ts.ts_node_has_error(child)) {
            printErrors(child, source);
        }
    }
}
