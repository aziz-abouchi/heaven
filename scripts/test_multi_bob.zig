const std = @import("std");
const network = @import("../src/network/scut.zig");
const matrix_lib = @import("../src/core/matrix.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const ports = [_]u16{11000, 11001};

    var matrices: [2]*matrix_lib.Matrix = undefined;
    for (ports) |port, idx| {
        try network.initNetwork(port);
        matrices[idx] = try allocator.create(matrix_lib.Matrix);
        platform.debug.print("Bob lancé sur le port {d}\n", .{port});
    }

    // Broadcast existence depuis le premier Bob
    network.broadcastExistence(matrices[0]);

    // Lister les peers depuis le second Bob
    _ = network.listenForPeers(allocator);
    network.listPeers();
}
