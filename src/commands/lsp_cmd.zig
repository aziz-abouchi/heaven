const std = @import("std");
const server = @import("../lsp/server.zig");

pub fn runLspCmd(allocator: std.mem.Allocator) anyerror!void {
    try server.runLsp(allocator);
}
