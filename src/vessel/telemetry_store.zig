// src/vessel/telemetry_store.zig — telemetry JSON depuis Store (E1/5, D9)
// Remplace matrix.getStats() par lecture directe de expr.Store.
// Conserve net2.known_peers pour les peers Bob.

const std = @import("std");
const expr = @import("expr");

fn writeJsonEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => try w.writeByte(c),
        }
    }
}

// Label lisible pour un noeud. sym -> nom resolu, lit -> tag du literal,
// autres -> tag du noeud (apply, bind, lambda, relation, ...).
fn nodeLabel(store: *const expr.Store, node: expr.Node) []const u8 {
    return switch (node.tag) {
        .sym => store.interner.resolve(@intCast(node.payload)),
        .lit => @tagName(std.meta.activeTag(store.lits.items[node.aux])),
        else => @tagName(node.tag),
    };
}

pub fn render(
    allocator: std.mem.Allocator,
    store: *const expr.Store,
    self_port: u16,
    peer_ports: []const u16,
) ![]u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);
    const w = list.writer(allocator);

    const node_count = store.nodes.items.len;
    const symbol_count = store.interner.list.items.len;
    const approx_bytes = node_count * 64 + symbol_count * 32;
    const load: f64 = if (node_count > 0)
        @min(@as(f64, @floatFromInt(node_count)) / 1000.0, 1.0)
    else
        0.0;

    try w.writeAll("{ \"stats\": {");
    try std.fmt.format(w,
        "\"node_count\": {d}, \"symbol_count\": {d}, \"approx_bytes\": {d}, \"hash_map_load\": {d:.4}",
        .{ node_count, symbol_count, approx_bytes, load });
    try w.writeAll("}, \"nodes\": [");

    var first = true;
    // Bob node local (peers ajoutes par l'appelant, voir bridge.zig)
    try w.writeAll("{\"id\": 99999, \"tag\": \"Bob\", ");
    try std.fmt.format(w, "\"label\": \"Bob:{d}\", \"status\": \"active\"", .{self_port});
    try w.writeAll("}");

    for (peer_ports) |pp| {
        try w.writeAll(",");
        try std.fmt.format(w, "{{\"id\": {d}, \"tag\": \"Bob\", \"label\": \"Bob:{d}\", \"status\": \"active\"}}", .{ pp, pp });
    }

    first = false;

    // Nœuds du Store (limité à 500 pour ne pas exploser le JSON)
    const limit = @min(node_count, 500);
    for (store.nodes.items[0..limit], 0..) |node, i| {
        if (!first) try w.writeAll(",");
        const label = nodeLabel(store, node);
        const truncated = if (label.len > 64) label[0..64] else label;
        try std.fmt.format(w,
            "{{\"id\": {d}, \"tag\": \"{s}\", \"payload\": {d}, \"aux\": {d}, \"label\": \"",
            .{ i, @tagName(node.tag), node.payload, node.aux });
        try writeJsonEscaped(w, truncated);
        try w.writeAll("\"}");
        first = false;
    }

    try w.writeAll("]}");
    return list.toOwnedSlice(allocator);
}

test "render : JSON bien forme, contient stats et nodes" {
    const allocator = std.testing.allocator;
    var store = expr.Store.init(allocator);
    defer store.deinit();
    // 1 nœud (lit int)
    _ = try store.int(42);

    const json = try render(allocator, &store, 8080, &.{});
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"node_count\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"symbol_count\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"Bob:8080\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\": 99999") != null);
    try std.testing.expect(json.len > 1 and json[json.len - 1] == '}');
}
