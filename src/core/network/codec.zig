const std = @import("std");
const expr_mod = @import("expr");
const egraph_mod = @import("egraph");
const protocol = @import("protocol");
const platform = @import("platform");

pub const NodeType = enum(u8) {
    lit = 0x01,
    sym = 0x02,
    apply = 0x03,
    binop = 0x04,
    bind = 0x05,
};

pub const MsgType = enum(u8) {
    handshake = 1,
    egraph_sync = 2,
    proof_request = 3,
    proof_result = 4,
    work_steal_request = 5,
    work_steal_response = 6,
};

pub const CodecError = error{
    BufferTooSmall,
    InvalidNodeType,
    InvalidFormat,
    UnknownSymbol,
};

// ═══════════════════════════════════════════════════════════
// SÉRIALISATION
// ═══════════════════════════════════════════════════════════

pub const Serializer = struct {
    buffer: []u8,
    offset: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer: []u8) Serializer {
        return .{ .buffer = buffer, .offset = 0, .allocator = allocator };
    }

    pub fn writeU8(self: *Serializer, v: u8) CodecError!void {
        if (self.offset + 1 > self.buffer.len) return error.BufferTooSmall;
        self.buffer[self.offset] = v;
        self.offset += 1;
    }

    pub fn writeU16(self: *Serializer, v: u16) CodecError!void {
        if (self.offset + 2 > self.buffer.len) return error.BufferTooSmall;
        std.mem.writeInt(u16, self.buffer[self.offset..][0..2], v, .little);
        self.offset += 2;
    }

    pub fn writeU32(self: *Serializer, v: u32) CodecError!void {
        if (self.offset + 4 > self.buffer.len) return error.BufferTooSmall;
        std.mem.writeInt(u32, self.buffer[self.offset..][0..4], v, .little);
        self.offset += 4;
    }

    pub fn writeI64(self: *Serializer, v: i64) CodecError!void {
        if (self.offset + 8 > self.buffer.len) return error.BufferTooSmall;
        std.mem.writeInt(i64, self.buffer[self.offset..][0..8], v, .little);
        self.offset += 8;
    }

    pub fn writeBytes(self: *Serializer, data: []const u8) CodecError!void {
        if (self.offset + data.len > self.buffer.len) return error.BufferTooSmall;
        @memcpy(self.buffer[self.offset..][0..data.len], data);
        self.offset += data.len;
    }

    pub fn getWritten(self: *const Serializer) []const u8 {
        return self.buffer[0..self.offset];
    }
};

// ═══════════════════════════════════════════════════════════
// DÉSÉRIALISATION
// ═══════════════════════════════════════════════════════════

pub const Deserializer = struct {
    buffer: []const u8,
    offset: usize,

    pub fn init(buffer: []const u8) Deserializer {
        return .{ .buffer = buffer, .offset = 0 };
    }

    pub fn readU8(self: *Deserializer) CodecError!u8 {
        if (self.offset + 1 > self.buffer.len) return error.InvalidFormat;
        const v = self.buffer[self.offset];
        self.offset += 1;
        return v;
    }

    pub fn readU16(self: *Deserializer) CodecError!u16 {
        if (self.offset + 2 > self.buffer.len) return error.InvalidFormat;
        const v = std.mem.readInt(u16, self.buffer[self.offset..][0..2], .little);
        self.offset += 2;
        return v;
    }

    pub fn readU32(self: *Deserializer) CodecError!u32 {
        if (self.offset + 4 > self.buffer.len) return error.InvalidFormat;
        const v = std.mem.readInt(u32, self.buffer[self.offset..][0..4], .little);
        self.offset += 4;
        return v;
    }

    pub fn readI64(self: *Deserializer) CodecError!i64 {
        if (self.offset + 8 > self.buffer.len) return error.InvalidFormat;
        const v = std.mem.readInt(i64, self.buffer[self.offset..][0..8], .little);
        self.offset += 8;
        return v;
    }

    pub fn readBytes(self: *Deserializer, len: usize) CodecError![]const u8 {
        if (self.offset + len > self.buffer.len) return error.InvalidFormat;
        const data = self.buffer[self.offset..][0..len];
        self.offset += len;
        return data;
    }

    pub fn remaining(self: *const Deserializer) usize {
        return self.buffer.len - self.offset;
    }
};

pub fn decode(payload: []const u8) !protocol.Incoming {
    if (payload.len == 0) return error.EmptyPayload;

    var des = Deserializer.init(payload);
    const msg_type_raw = try des.readU8();

    // Si tous les octets sont 0xFF, c'est du bruit de buffer
    var is_noise = true;
    for (payload) |byte| {
        if (byte != 0xFF) is_noise = false;
    }
    if (is_noise) return error.NoiseDetected;

    return switch (msg_type_raw) {
        1 => .handshake,
        // Ajoutez d'autres cas ici...
        else => {
            // platform.debug.print("[CODEC] Type de message inconnu reçu: 0x{X} (taille: {d})\n", .{ msg_type_raw, payload.len });
            return error.InvalidFormat;
        },
    };
}

// ═══════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════

test "codec roundtrip" {
    var buf: [1024]u8 = undefined;
    var ser = Serializer.init(std.testing.allocator, &buf);

    try ser.writeU8(0x42);
    try ser.writeU32(12345);
    try ser.writeI64(-9876543210);

    const written = ser.getWritten();

    var des = Deserializer.init(written);
    const a = try des.readU8();
    const b = try des.readU32();
    const c = try des.readI64();

    try std.testing.expectEqual(@as(u8, 0x42), a);
    try std.testing.expectEqual(@as(u32, 12345), b);
    try std.testing.expectEqual(@as(i64, -9876543210), c);
}

// ═══════════════════════════════════════════════════════════
// SÉRIALISATION D'UN SOUS-GRAPHE EGRAPH
// ═══════════════════════════════════════════════════════════

pub fn serializeSubgraph(
    allocator: std.mem.Allocator,
    store: *const expr_mod.Store,
    egraph: *const egraph_mod.EGraph,
    root_class: usize,
    output: *Serializer,
) !void {
    var visited = std.AutoHashMap(usize, void).init(allocator);
    defer visited.deinit();

    var order = std.ArrayListUnmanaged(usize){};
    defer order.deinit(allocator);

    try collectReachable(egraph, store, root_class, &visited, &order, allocator);

    var class_to_idx = std.AutoHashMap(usize, u32).init(allocator);
    defer class_to_idx.deinit();

    for (order.items, 0..) |cls, idx| {
        try class_to_idx.put(cls, @intCast(idx));
    }

    try output.writeU32(@intCast(order.items.len));

    for (order.items) |cls| {
        if (cls >= egraph.classes.items.len) continue;
        const eclass = egraph.classes.items[cls];

        if (eclass.nodes.items.len == 0) continue;
        const expr_id = eclass.nodes.items[0];
        const expr = store.get(expr_id);

        switch (expr.tag) {
            .lit => {
                try output.writeU8(0x01);
                const lit = store.getLit(expr_id);
                switch (lit) {
                    .int => |v| try output.writeI64(v),
                    .float => |v| try output.writeI64(@intFromFloat(v)),
                    .boolean => |v| try output.writeI64(if (v) 1 else 0),
                    .unit => try output.writeI64(0),
                    .str => |s| {
                        try output.writeU8(0x02);
                        const name = store.interner.resolve(s);
                        try output.writeU16(@intCast(name.len));
                        try output.writeBytes(name);
                        return; // Sortir car on a déjà écrit le tag
                    },
                    .runtime => |_| {
                        // Les références runtime ne sont pas sérialisables
                        // Écrire un littéral nul
                        try output.writeI64(0);
                    },
                }
            },
            .sym => {
                try output.writeU8(0x02);
                const name = store.interner.resolve(expr.payload);
                try output.writeU16(@intCast(name.len));
                try output.writeBytes(name);
            },
            .apply => {
                try output.writeU8(0x03);
                const func_class = try findClassForExpr(egraph, expr.payload);
                const func_idx = class_to_idx.get(func_class) orelse return error.InvalidReference;
                try output.writeU32(func_idx);

                const span_start = expr.span_a.start;
                const span_len = expr.span_a.len;
                const args = store.childPool()[span_start .. span_start + span_len];
                try output.writeU8(@intCast(args.len));
                for (args) |arg_id| {
                    const arg_class = try findClassForExpr(egraph, arg_id);
                    const arg_idx = class_to_idx.get(arg_class) orelse return error.InvalidReference;
                    try output.writeU32(arg_idx);
                }
            },
            .bind => {
                try output.writeU8(0x05);
                const name = store.interner.resolve(expr.payload);
                try output.writeU16(@intCast(name.len));
                try output.writeBytes(name);
                const value_id: expr_mod.Id = @bitCast(expr.aux);
                const value_class = try findClassForExpr(egraph, value_id);
                const value_idx = class_to_idx.get(value_class) orelse return error.InvalidReference;
                try output.writeU32(value_idx);
            },
            else => {
                try output.writeU8(0x02);
                try output.writeU16(0);
            },
        }
    }
}

fn collectReachable(
    egraph: *const egraph_mod.EGraph,
    store: *const expr_mod.Store,
    class_id: usize,
    visited: *std.AutoHashMap(usize, void),
    order: *std.ArrayListUnmanaged(usize),
    allocator: std.mem.Allocator,
) !void {
    if (visited.contains(class_id)) return;
    if (class_id >= egraph.classes.items.len) return;

    try visited.put(class_id, {});

    const eclass = egraph.classes.items[class_id];
    if (eclass.nodes.items.len > 0) {
        const expr_id = eclass.nodes.items[0];
        const expr = store.get(expr_id);

        switch (expr.tag) {
            .apply => {
                const func_class = findClassForExpr(egraph, expr.payload) catch return;
                try collectReachable(egraph, store, func_class, visited, order, allocator);

                const span_start = expr.span_a.start;
                const span_len = expr.span_a.len;
                const args = store.childPool()[span_start .. span_start + span_len];
                for (args) |arg_id| {
                    const arg_class = findClassForExpr(egraph, arg_id) catch continue;
                    try collectReachable(egraph, store, arg_class, visited, order, allocator);
                }
            },
            .bind => {
                const value_id: expr_mod.Id = @bitCast(expr.aux);
                const value_class = findClassForExpr(egraph, value_id) catch return;
                try collectReachable(egraph, store, value_class, visited, order, allocator);
            },
            else => {},
        }
    }

    try order.append(allocator, class_id);
}

fn findClassForExpr(egraph: *const egraph_mod.EGraph, expr_id: expr_mod.Id) !usize {
    for (egraph.classes.items, 0..) |eclass, idx| {
        for (eclass.nodes.items) |node_id| {
            if (node_id == expr_id) return idx;
        }
    }
    return error.ExprNotFound;
}
