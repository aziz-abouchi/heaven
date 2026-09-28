const std = @import("std");

pub const Position = struct {
    line: u32 = 0,
    character: u32 = 0,
};

pub const Range = struct {
    start: Position = .{},
    end: Position = .{},
};

pub fn formatDiagnostics(allocator: std.mem.Allocator, uri: []const u8, diag_items: []const u8) anyerror![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{s}\"uri\":\"{s}\",\"diagnostics\":{s}{s}{s}", .{ "{", "{", uri, diag_items, "}", "}" });
}

pub fn formatResponse(allocator: std.mem.Allocator, id: i64, result: []const u8) anyerror![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{s}{s}", .{ "{", id, result, "}" });
}
