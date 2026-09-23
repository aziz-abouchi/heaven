const std = @import("std");

const semantic =
    @import("core/semantic.zig");

const graph_mod =
    @import("core/semantic_graph.zig");

const engine =
    @import("core/semantic_engine.zig");

pub fn main() !void {

    var gpa =
        std.heap.GeneralPurposeAllocator(.{}){};

    defer _ = gpa.deinit();

    const allocator =
        gpa.allocator();

    var graph =
        graph_mod.SemanticGraph.init(
            allocator,
        );

    defer graph.deinit();

    const goal =
        try graph.addNode(
            semantic.SemanticObject.init(
                1,
                .goal,
                "Build Heaven",
            ),
        );

    const task =
        try graph.addNode(
            semantic.SemanticObject.init(
                2,
                .task,
                "Compile Kernel",
            ),
        );

    const proof =
        try graph.addNode(
            semantic.SemanticObject.init(
                3,
                .proof,
                "Kernel Compiles",
            ),
        );

    try graph.addEdge(
        goal,
        task,
        .depends_on,
    );

    try graph.addEdge(
        task,
        proof,
        .proves,
    );

    try engine.execute(
        &graph,
        goal,
    );
}