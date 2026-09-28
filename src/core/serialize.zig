//! serialize.zig — Format binaire canonique pour Store (HVN1).
//! Voir docs/spec/_serialize.md pour le format détaillé.

const std = @import("std");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;

pub const Error = error{
    InvalidMagic,
    UnsupportedVersion,
    Truncated,
    Corrupted,
    InvalidTag,
    OutOfMemory,
};

pub const MAGIC: [4]u8 = .{ 'H', 'V', 'N', '1' };
pub const VERSION: u8 = 1;

// ─── Encode ───

pub fn encode(store: *const Store, writer: anytype) Error!void {
    try writer.writeAll(&MAGIC);
    try writer.writeByte(VERSION);
    try writer.writeByte(0);
    try writer.writeInt(u32, @intCast(store.nodes.items.len), .little);
    try writer.writeInt(u32, @intCast(store.pool.items.len), .little);
    try writer.writeInt(u32, @intCast(store.lits.items.len), .little);
    try writer.writeInt(u32, @intCast(store.interner.list.items.len), .little);

    for (store.interner.list.items) |s| {
        try writer.writeInt(u32, @intCast(s.len), .little);
        try writer.writeAll(s);
    }

    for (store.lits.items) |lit| {
        try encodeLit(lit, writer);
    }

    for (store.nodes.items) |node| {
        try writer.writeByte(@intFromEnum(node.tag));
        try writer.writeInt(u32, node.payload, .little);
        try writer.writeInt(u32, node.aux, .little);
        try writer.writeInt(u32, node.span_a.start, .little);
        try writer.writeInt(u16, node.span_a.len, .little);
        try writer.writeInt(u32, node.span_b.start, .little);
        try writer.writeInt(u16, node.span_b.len, .little);
    }

    for (store.pool.items) |id| {
        try writer.writeInt(u32, id, .little);
    }
}

fn encodeLit(lit: expr.Lit, writer: anytype) Error!void {
    switch (lit) {
        .int => |v| {
            try writer.writeByte(0);
            try writer.writeInt(i64, v, .little);
        },
        .float => |v| {
            try writer.writeByte(1);
            try writer.writeInt(u64, @bitCast(v), .little);
        },
        .str => |sym| {
            try writer.writeByte(2);
            try writer.writeInt(u32, sym, .little);
        },
        .boolean => |b| {
            try writer.writeByte(3);
            try writer.writeByte(if (b) 1 else 0);
        },
        .unit => {
            try writer.writeByte(4);
        },
        .runtime => |r| {
            try writer.writeByte(5);
            switch (r) {
                .theorem => |id| {
                    try writer.writeByte(0);
                    try writer.writeInt(u32, id, .little);
                },
                .proof => |id| {
                    try writer.writeByte(1);
                    try writer.writeInt(u32, id, .little);
                },
                .skill => |id| {
                    try writer.writeByte(2);
                    try writer.writeInt(u32, id, .little);
                },
                .agent => |id| {
                    try writer.writeByte(3);
                    try writer.writeInt(u32, id, .little);
                },
            }
        },
    }
}

// ─── Decode ───

fn readNoEof(reader: anytype, buf: []u8) Error!void {
    const n = reader.readAll(buf) catch return error.Truncated;
    if (n != buf.len) return error.Truncated;
}

pub fn decode(reader: anytype, allocator: std.mem.Allocator) Error!Store {
    var store = Store.init(allocator);
    errdefer store.deinit();

    var magic: [4]u8 = undefined;
    try readNoEof(reader, &magic);
    if (!std.mem.eql(u8, &magic, &MAGIC)) return error.InvalidMagic;

    const version = reader.readByte() catch return error.Truncated;
    if (version != VERSION) return error.UnsupportedVersion;
    _ = reader.readByte() catch return error.Truncated;

    const node_count = reader.readInt(u32, .little) catch return error.Truncated;
    const pool_count = reader.readInt(u32, .little) catch return error.Truncated;
    const lit_count = reader.readInt(u32, .little) catch return error.Truncated;
    const interner_count = reader.readInt(u32, .little) catch return error.Truncated;

    try store.interner.list.ensureTotalCapacity(allocator, interner_count);
    var i: u32 = 0;
    while (i < interner_count) : (i += 1) {
        const len = reader.readInt(u32, .little) catch return error.Truncated;
        const bytes = try allocator.alloc(u8, len);
        errdefer allocator.free(bytes);
        try readNoEof(reader, bytes);
        try store.interner.list.append(allocator, bytes);
        try store.interner.map.put(allocator, bytes, @intCast(i));
    }

    try store.lits.ensureTotalCapacity(allocator, lit_count);
    i = 0;
    while (i < lit_count) : (i += 1) {
        const lit = try decodeLit(reader);
        try store.lits.append(allocator, lit);
    }

    try store.nodes.ensureTotalCapacity(allocator, node_count);
    i = 0;
    while (i < node_count) : (i += 1) {
        const tag_byte = reader.readByte() catch return error.Truncated;
        const tag = std.meta.intToEnum(Tag, tag_byte) catch return error.InvalidTag;
        const payload = reader.readInt(u32, .little) catch return error.Truncated;
        const aux = reader.readInt(u32, .little) catch return error.Truncated;
        const sa_start = reader.readInt(u32, .little) catch return error.Truncated;
        const sa_len = reader.readInt(u16, .little) catch return error.Truncated;
        const sb_start = reader.readInt(u32, .little) catch return error.Truncated;
        const sb_len = reader.readInt(u16, .little) catch return error.Truncated;
        try store.nodes.append(allocator, .{
            .tag = tag,
            .payload = payload,
            .aux = aux,
            .span_a = .{ .start = sa_start, .len = sa_len },
            .span_b = .{ .start = sb_start, .len = sb_len },
        });
    }

    try store.pool.ensureTotalCapacity(allocator, pool_count);
    i = 0;
    while (i < pool_count) : (i += 1) {
        const id = reader.readInt(u32, .little) catch return error.Truncated;
        try store.pool.append(allocator, id);
    }

    return store;
}

fn decodeLit(reader: anytype) Error!expr.Lit {
    const tag = reader.readByte() catch return error.Truncated;
    return switch (tag) {
        0 => .{ .int = reader.readInt(i64, .little) catch return error.Truncated },
        1 => .{ .float = @bitCast(reader.readInt(u64, .little) catch return error.Truncated) },
        2 => .{ .str = reader.readInt(u32, .little) catch return error.Truncated },
        3 => .{ .boolean = (reader.readByte() catch return error.Truncated) != 0 },
        4 => .unit,
        5 => blk: {
            const kind = reader.readByte() catch return error.Truncated;
            const id = reader.readInt(u32, .little) catch return error.Truncated;
            break :blk .{ .runtime = switch (kind) {
                0 => .{ .theorem = id },
                1 => .{ .proof = id },
                2 => .{ .skill = id },
                3 => .{ .agent = id },
                else => return error.Corrupted,
            } };
        },
        else => error.Corrupted,
    };
}

// ─── Convenience ───

pub fn encodeToBytes(store: *const Store, allocator: std.mem.Allocator) Error![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try encode(store, list.writer(allocator));
    return list.toOwnedSlice(allocator);
}

pub fn decodeFromBytes(bytes: []const u8, allocator: std.mem.Allocator) Error!Store {
    var stream = std.io.fixedBufferStream(bytes);
    return decode(stream.reader(), allocator);
}

// ─── Tests ───

const testing = std.testing;

test "serialize - roundtrip empty store" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const bytes = try encodeToBytes(&store, allocator);
    defer allocator.free(bytes);

    var restored = try decodeFromBytes(bytes, allocator);
    defer restored.deinit();

    try testing.expectEqual(@as(usize, 0), restored.nodes.items.len);
    try testing.expectEqual(@as(usize, 0), restored.pool.items.len);
}

test "serialize - roundtrip (+ 1 2)" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const plus = try store.sym("+");
    const a = try store.int(1);
    const b = try store.int(2);
    _ = try store.apply(plus, &.{ a, b });

    const bytes = try encodeToBytes(&store, allocator);
    defer allocator.free(bytes);

    var restored = try decodeFromBytes(bytes, allocator);
    defer restored.deinit();

    try testing.expectEqual(store.nodes.items.len, restored.nodes.items.len);
    try testing.expectEqual(store.pool.items.len, restored.pool.items.len);
    try testing.expectEqual(store.lits.items.len, restored.lits.items.len);
    try testing.expectEqual(store.interner.list.items.len, restored.interner.list.items.len);

    // Vérifier chaque node est identique champ par champ
    for (store.nodes.items, restored.nodes.items) |orig, rest| {
        try testing.expectEqual(orig.tag, rest.tag);
        try testing.expectEqual(orig.payload, rest.payload);
        try testing.expectEqual(orig.aux, rest.aux);
        try testing.expectEqual(orig.span_a.start, rest.span_a.start);
        try testing.expectEqual(orig.span_a.len, rest.span_a.len);
        try testing.expectEqual(orig.span_b.start, rest.span_b.start);
        try testing.expectEqual(orig.span_b.len, rest.span_b.len);
    }
}

test "serialize - literals preserves all kinds" {
    const allocator = testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    _ = try store.int(42);
    _ = try store.float(3.14);
    _ = try store.boolean(true);
    _ = try store.boolean(false);

    const bytes = try encodeToBytes(&store, allocator);
    defer allocator.free(bytes);

    var restored = try decodeFromBytes(bytes, allocator);
    defer restored.deinit();

    try testing.expectEqual(@as(i64, 42), restored.lits.items[0].int);
    try testing.expectEqual(@as(f64, 3.14), restored.lits.items[1].float);
    try testing.expectEqual(true, restored.lits.items[2].boolean);
    try testing.expectEqual(false, restored.lits.items[3].boolean);
}

test "serialize - invalid magic rejected" {
    const allocator = testing.allocator;
    const bad = "XXXX\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    try testing.expectError(error.InvalidMagic, decodeFromBytes(bad, allocator));
}

test "serialize - truncated rejected" {
    const allocator = testing.allocator;
    const short = "HVN";
    try testing.expectError(error.Truncated, decodeFromBytes(short, allocator));
}
