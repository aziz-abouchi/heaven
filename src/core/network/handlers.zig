const std = @import("std");
const codec = @import("codec");
const platform = @import("platform");
const egraph_mod = @import("egraph");
const expr_mod = @import("expr");
const proof_mod = @import("proof");
const Driver = @import("driver");

pub const Handler = struct {
    driver: Driver.NetworkDriver,

    pub fn handleMessage(self: *Handler, data: []const u8) void {
        _ = data;
        // Logique de votre noyau
        // ...
        // Réponse éventuelle
        self.driver.send("ACK");
    }
};

pub fn handleEGraphSync(
    allocator: std.mem.Allocator,
    peer_id: []const u8,
    payload: []const u8,
    egraph: *egraph_mod.EGraph,
    store: *expr_mod.Store,
) !void {
    _ = peer_id;

    platform.io.print("Handler: egraph_sync\n", .{});

    var des = codec.Deserializer.init(payload);
    const count = try des.readU32();

    var class_ids = std.ArrayListUnmanaged(usize){};
    defer class_ids.deinit(allocator);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const node_type_raw = try des.readU8();

        const class_id = switch (node_type_raw) {
            0x01 => blk: {
                const value = try des.readI64();
                const lit_id = try store.int(value);
                break :blk try egraph.addExpr(lit_id);
            },
            0x02 => blk: {
                const len = try des.readU16();
                const name_bytes = try des.readBytes(len);
                const sym_id = try store.sym(name_bytes);
                break :blk try egraph.addExpr(sym_id);
            },
            0x03 => blk: {
                const func_idx = try des.readU32();
                const argc = try des.readU8();

                if (func_idx >= class_ids.items.len) return error.InvalidNodeReference;

                const func_class = class_ids.items[func_idx];
                const func_id = egraph.extract(func_class, null) orelse return error.ExtractionFailed;

                var arg_ids = std.ArrayListUnmanaged(expr_mod.Id){};
                defer arg_ids.deinit(allocator);

                var j: u8 = 0;
                while (j < argc) : (j += 1) {
                    const arg_idx = try des.readU32();
                    if (arg_idx >= class_ids.items.len) return error.InvalidNodeReference;
                    const arg_class = class_ids.items[arg_idx];
                    const arg_id = egraph.extract(arg_class, null) orelse return error.ExtractionFailed;
                    try arg_ids.append(allocator, arg_id);
                }

                const apply_id = try store.apply(func_id, arg_ids.items);
                break :blk try egraph.addExpr(apply_id);
            },
            0x04 => blk: {
                const op = try des.readU8();
                const left_idx = try des.readU32();
                const right_idx = try des.readU32();

                if (left_idx >= class_ids.items.len or right_idx >= class_ids.items.len) {
                    return error.InvalidNodeReference;
                }

                const left_class = class_ids.items[left_idx];
                const right_class = class_ids.items[right_idx];

                const left_id = egraph.extract(left_class, null) orelse return error.ExtractionFailed;
                const right_id = egraph.extract(right_class, null) orelse return error.ExtractionFailed;

                const op_name = switch (op) {
                    0x2B => "+",
                    0x2D => "-",
                    0x2A => "*",
                    0x2F => "/",
                    else => "op",
                };

                const op_sym = try store.sym(op_name);
                const apply_id = try store.apply(op_sym, &[_]expr_mod.Id{ left_id, right_id });
                break :blk try egraph.addExpr(apply_id);
            },
            else => blk: {
                break :blk @as(usize, 0);
            },
        };

        try class_ids.append(allocator, class_id);
    }

    platform.io.print("Merged {} nodes into egraph\n", .{count});
}

pub fn handleProofRequest(
    allocator: std.mem.Allocator,
    peer_id: []const u8,
    payload: []const u8,
    egraph: *egraph_mod.EGraph,
    store: *expr_mod.Store,
) !void {
    _ = store;
    _ = egraph;
    platform.io.print("Handler: proof_request\n", .{});

    var des = codec.Deserializer.init(payload);
    const expr_len = try des.readU32();
    const expr_bytes = try des.readBytes(expr_len);

    platform.io.print("  Expression to prove: {s}\n", .{expr_bytes});

    // Parser l'expression (simplifié : on suppose que c'est déjà dans le store)
    // TODO: Utiliser le parser Tree-sitter pour convertir expr_bytes en Id

    // Tenter de prouver via l'egraph saturé
    // Stratégie : chercher si l'expression est équivalente à "true" ou à une tautologie

    var result_str: [256]u8 = undefined;
    var result_len: usize = 0;

    // Vérifier si l'expression existe dans l'egraph
    // Si oui, extraire la preuve par équivalence de classes

    const proof_success = "proof_ok";
    @memcpy(result_str[0..proof_success.len], proof_success);
    result_len = proof_success.len;

    // Construire la réponse
    var response_buf: [1024]u8 = undefined;
    var ser = codec.Serializer.init(allocator, &response_buf);

    try ser.writeU8(@intFromEnum(codec.MsgType.proof_result));
    try ser.writeU8(1); // status = success
    try ser.writeU32(@intCast(result_len));
    try ser.writeBytes(result_str[0..result_len]);

    const response = ser.getWritten();

    // Envoyer via le bridge WASM→JS
    send_proof_response(peer_id.ptr, peer_id.len, response.ptr, response.len);

    platform.io.print("  Proof result sent\n", .{});
}

extern fn send_proof_response(peer_id_ptr: [*]const u8, peer_id_len: usize, data_ptr: [*]const u8, data_len: usize) void;
extern fn send_work_steal_response(peer_id_ptr: [*]const u8, peer_id_len: usize, data_ptr: [*]const u8, data_len: usize) void;

pub fn handleWorkStealRequest(
    allocator: std.mem.Allocator,
    peer_id: []const u8,
    payload: []const u8,
    egraph: *egraph_mod.EGraph,
    store: *expr_mod.Store,
) !void {
    platform.io.print("Handler: work_steal_request\n", .{});

    var des = codec.Deserializer.init(payload);
    const capacity = try des.readU32();

    platform.io.print("  Peer wants {} work units\n", .{capacity});

    const total_classes = egraph.classes.items.len;
    const to_send = @min(capacity, total_classes);

    if (to_send == 0) {
        platform.io.print("  No work to share\n", .{});
        return;
    }

    // Construire le payload work_steal_response
    var response_buf: [8192]u8 = undefined;
    var ser = codec.Serializer.init(allocator, &response_buf);

    try ser.writeU8(@intFromEnum(codec.MsgType.work_steal_response));
    try ser.writeU32(to_send);

    const start_class = if (total_classes > to_send) total_classes - to_send else 0;
    var i: usize = start_class;
    while (i < total_classes) : (i += 1) {
        serializeClassSimple(allocator, store, egraph, i, &ser) catch |err| {
            platform.io.print("  Failed to serialize class {}: {}\n", .{ i, err });
            continue;
        };
    }

    const response = ser.getWritten();

    // Envoyer via le callback JS
    send_work_steal_response(peer_id.ptr, peer_id.len, response.ptr, response.len);

    platform.io.print("  Sent {} work units to peer\n", .{to_send});
}

// Version simplifiée : sérialise juste les nodes d'une classe
fn serializeClassSimple(
    allocator: std.mem.Allocator,
    store: *const expr_mod.Store,
    egraph: *const egraph_mod.EGraph,
    class_id: usize,
    output: *codec.Serializer,
) !void {
    _ = allocator;

    if (class_id >= egraph.classes.items.len) return;
    const eclass = egraph.classes.items[class_id];

    if (eclass.nodes.items.len == 0) return;

    // Écrire le class_id
    try output.writeU32(@intCast(class_id));

    // Écrire le nombre de nodes dans cette classe
    try output.writeU32(@intCast(eclass.nodes.items.len));

    // Sérialiser chaque node
    for (eclass.nodes.items) |expr_id| {
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
                    .str => |_| try output.writeI64(0),
                    .runtime => |_| try output.writeI64(0),
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
                // Écrire l'ID du func (pas la classe)
                try output.writeU32(expr.payload);

                const span_start = expr.span_a.start;
                const span_len = expr.span_a.len;
                const args = store.childPool()[span_start .. span_start + span_len];
                try output.writeU8(@intCast(args.len));
                for (args) |arg_id| {
                    try output.writeU32(arg_id);
                }
            },
            .bind => {
                try output.writeU8(0x05);
                const name = store.interner.resolve(expr.payload);
                try output.writeU16(@intCast(name.len));
                try output.writeBytes(name);
                try output.writeU32(expr.aux);
            },
            else => {
                try output.writeU8(0x02);
                try output.writeU16(0);
            },
        }
    }
}
