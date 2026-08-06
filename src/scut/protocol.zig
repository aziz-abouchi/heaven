const std = @import("std");
const task_lib = @import("task");

pub const MAGIC: u32 = 0x0B0BCAFE;
pub const VERSION: u8 = 1;

pub const MsgKind = enum(u8) {
    ExecuteTask = 0,
    RPC = 1,
    MatrixSync = 2,
    SwarmQueryProlog = 3,
    SwarmReplyProlog = 4,
    SwarmShareRule = 5,
    EGraphUnion = 6, // Le nouveau type pour synchroniser les e-classes
};

pub const EGraphUnionPayload = extern struct {
    hash_a: u64, // Empreinte de la première expression
    hash_b: u64, // Empreinte de la seconde expression
    rule_id: u32, // ID de la règle de réécriture qui a permis la fusion
};

pub const Incoming = union(enum) {
    handshake: void,
    RawCode: []u8,
    MatrixSync: []u8,
    Signal: []u8,
    Task: task_lib.Task,
    EGraphUnion: EGraphUnionPayload,
};

pub const Header = packed struct {
    magic: u32,
    version: u8,
    kind: MsgKind,
    ttl: u8,
    length: u32,
    msg_id: u64,
    from: u64,
    seq: u32,
    timestamp: i64,
    checksum: u32,
};

pub fn computeChecksum(data: []const u8) u32 {
    var sum: u32 = 0;
    for (data) |b| sum +%= b;
    return sum;
}

pub fn verifyHeader(h: *const Header) bool {
    return h.magic == MAGIC and h.version == VERSION;
}

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
