const std = @import("std");

const SemanticGraph =
    @import("semantic_graph.zig").SemanticGraph;

const SemanticKind =
    @import("semantic.zig").SemanticKind;

pub fn execute(
    graph: *SemanticGraph,
    node_index: usize,
) !void {
    const node =
        graph.nodes.items[node_index];

    switch (node.kind) {
        .goal => {
            platform.debug.print(
                "Goal: {s}\n",
                .{node.name},
            );
        },

        .proof => {
            platform.debug.print(
                "Proof: {s}\n",
                .{node.name},
            );
        },

        .task => {
            platform.debug.print(
                "Task: {s}\n",
                .{node.name},
            );
        },

        .agent => {
            platform.debug.print(
                "Agent: {s}\n",
                .{node.name},
            );
        },

        .expression => {
            platform.debug.print(
                "Expression: {s}\n",
                .{node.name},
            );
        },
    }
}
