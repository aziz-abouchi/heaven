const std = @import("std");

pub const LSPClient = struct {
    process: std.ChildProcess,
    allocator: std.mem.Allocator,
    id_counter: usize = 0,

    pub fn init(allocator: std.mem.Allocator, server_path: []const u8) !LSPClient {
        var proc = std.ChildProcess.init(&[_][]const u8{server_path}, allocator);
        proc.stdin_behavior = .Pipe;
        proc.stdout_behavior = .Pipe;
        try proc.spawn();

        return LSPClient{ .process = proc, .allocator = allocator };
    }

    pub fn sendRequest(self: *LSPClient, method: []const u8, params_json: []const u8) !void {
        self.id_counter += 1;
        const payload = try std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{s}}}", .{ self.id_counter, method, params_json });
        defer self.allocator.free(payload);

        // Le protocole LSP demande un header Content-Length
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{payload.len});
        defer self.allocator.free(header);

        try self.process.stdin.?.writeAll(header);
        try self.process.stdin.?.writeAll(payload);
    }
};
