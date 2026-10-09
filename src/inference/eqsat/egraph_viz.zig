const std = @import("std");
const egraph_mod = @import("egraph");
const expr = @import("expr");

const EGraph = egraph_mod.EGraph;
const Store = expr.Store;
const Id = expr.Id;
const Allocator = std.mem.Allocator;

/// Exporte l'E-Graph en JSON pour visualisation D3.js
/// Format: { "classes": [...], "nodes": [...], "edges": [...] }
pub fn exportToJson(eg: *EGraph, allocator: Allocator) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);
    try writer.writeAll("{\"classes\":[");

    // Exporter les classes d'équivalence
    var first_class = true;
    for (eg.classes.items, 0..) |class, class_id| {
        if (!first_class) try writer.writeAll(",");
        first_class = false;

        try writer.print("{{\"id\":{d},\"nodes\":[", .{class_id});

        var first_node = true;
        for (class.nodes.items) |node_id| {
            if (!first_node) try writer.writeAll(",");
            first_node = false;
            try writer.print("{d}", .{node_id});
        }

        try writer.writeAll("]}");
    }

    try writer.writeAll("],\"nodes\":[");

    // Exporter les nœuds avec leurs détails
    var first_node = true;
    const store = eg.store;
    for (0..store.len()) |node_id| {
        if (!first_node) try writer.writeAll(",");
        first_node = false;

        const node = store.get(@intCast(node_id));
        const tag_name = @tagName(node.tag);

        try writer.print("{{\"id\":{d},\"tag\":\"{s}\"", .{ node_id, tag_name });

        // Ajouter le payload si c'est un symbole
        if (node.tag == .sym) {
            const name = store.interner.resolve(node.payload);
            try writer.print(",\"name\":\"{s}\"", .{name});
        }

        try writer.writeAll("}");
    }

    try writer.writeAll("],\"merges\":[");

    // Exporter les preuves de fusion (edges)
    var first_merge = true;
    for (eg.proofs.items) |proof| {
        if (!first_merge) try writer.writeAll(",");
        first_merge = false;

        try writer.print("{{\"lhs\":{d},\"rhs\":{d},\"rule\":{d}}}", .{
            proof.lhs, proof.rhs, proof.rule_id
        });
    }

    try writer.writeAll("]}");

    return buffer.toOwnedSlice(allocator);
}
