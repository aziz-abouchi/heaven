const std = @import("std");
const codec = @import("codec");
const egraph_mod = @import("egraph");
const expr_mod = @import("expr");

pub const Swarm = struct {
    allocator: std.mem.Allocator,
    egraph: *egraph_mod.EGraph,
    store: *expr_mod.Store,
    
    // Interface réseau abstraite (fournie par la PAL)
    pub const NetworkInterface = struct {
        send: *const fn (ctx: *anyopaque, peer_id: [16]u8, data: []const u8) void,
        ctx: *anyopaque,
    };
    network: NetworkInterface,
    
    pub fn init(
        allocator: std.mem.Allocator,
        egraph: *egraph_mod.EGraph,
        store: *expr_mod.Store,
        network: NetworkInterface,
    ) Swarm {
        return .{
            .allocator = allocator,
            .egraph = egraph,
            .store = store,
            .network = network,
        };
    }
    
    // ═══════════════════════════════════════════════════════
    // DISPATCH (appelé à chaque tick)
    // ═══════════════════════════════════════════════════════
    
    pub fn handleMessage(self: *Swarm, peer_id: [16]u8, msg_type: u8, payload: []const u8) !void {
        switch (msg_type) {
            1 => try self.handleHandshake(peer_id, payload),
            2 => try self.handleEGraphSync(peer_id, payload),
            3 => try self.handleProofRequest(peer_id, payload),
            5 => try self.handleWorkStealRequest(peer_id, payload),
            4, 6 => {}, // réponses à des requêtes qu'on a émises
            else => {},
        }
    }
    
    // ═══════════════════════════════════════════════════════
    // HANDSHAKE
    // ═══════════════════════════════════════════════════════
    
    pub fn handleHandshake(self: *Swarm, peer_id: [16]u8, payload: []const u8) !void {
        _ = self;
        _ = peer_id;
        _ = payload;
    }
    
    // ═══════════════════════════════════════════════════════
    // EGRAPH SYNC (type 2)
    // ═══════════════════════════════════════════════════════
    
    pub fn handleEGraphSync(self: *Swarm, peer_id: [16]u8, payload: []const u8) !void {
        _ = peer_id;
        
        var des = codec.Deserializer.init(payload);
        const count = try des.readU32();
        
        // Map pour associer les IDs du payload aux EClass IDs locaux
        // ID 0 dans le payload = premier node désérialisé, etc.
        var id_map = std.ArrayList(egraph_mod.EClassId).init(self.allocator);
        defer id_map.deinit();
        
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const node_type = try des.readU8();
            const class_id = try self.deserializeNode(node_type, &des, id_map.items);
            try id_map.append(class_id);
        }
    }
    
    fn deserializeNode(
        self: *Swarm,
        node_type: u8,
        des: *codec.Deserializer,
        id_map: []const egraph_mod.EClassId,
    ) !egraph_mod.EClassId {
        switch (node_type) {
            0x01 => {
                const value = try des.readI64();
                // Créer un node Lit et l'ajouter à l'egraph
                const enode = egraph_mod.ENode{ .lit = .{ .value = value } };
                return self.egraph.add(enode);
            },
            0x02 => {
                const len = try des.readU16();
                const name = try des.readBytes(len);
                // Symbole : on stocke le nom dans le store
                const sym_name = try self.allocator.dupe(u8, name);
                const enode = egraph_mod.ENode{ .sym = .{ .name = sym_name } };
                return self.egraph.add(enode);
            },
            0x04 => {
                const op = try des.readU8();
                const left_idx = try des.readU32();
                const right_idx = try des.readU32();
                // Résoudre les références via id_map
                const left = if (left_idx < id_map.len) id_map[left_idx] else return error.InvalidRef;
                const right = if (right_idx < id_map.len) id_map[right_idx] else return error.InvalidRef;
                const enode = egraph_mod.ENode{ .binop = .{ .op = op, .left = left, .right = right } };
                return self.egraph.add(enode);
            },
            0x03 => {
                const func_idx = try des.readU32();
                const argc = try des.readU8();
                const func_id = if (func_idx < id_map.len) id_map[func_idx] else return error.InvalidRef;
                var args = std.ArrayList(egraph_mod.EClassId).init(self.allocator);
                defer args.deinit();
                for (0..argc) |_| {
                    const arg_idx = try des.readU32();
                    if (arg_idx >= id_map.len) return error.InvalidRef;
                    try args.append(id_map[arg_idx]);
                }
                const enode = egraph_mod.ENode{ .apply = .{ .func = func_id, .args = try args.toOwnedSlice() } };
                return self.egraph.add(enode);
            },
            else => return error.UnknownNodeType,
        }
    }
    
    // ═══════════════════════════════════════════════════════
    // PROOF REQUEST (type 3)
    // ═══════════════════════════════════════════════════════
    
    pub fn handleProofRequest(self: *Swarm, peer_id: [16]u8, payload: []const u8) !void {
        var des = codec.Deserializer.init(payload);
        const expr_len = try des.readU32();
        const expr_bytes = try des.readBytes(expr_len);
        
        // TODO: Désérialiser l'expression et essayer de la prouver
        // const expr = try deserializeExpression(self.allocator, self.store, expr_bytes);
        // const result = try self.prover.prove(expr);
        
        // Envoyer une réponse
        var response_buf: [1024]u8 = undefined;
        var ser = codec.Serializer.init(self.allocator, &response_buf);
        try ser.writeU8(4); // proof_result
        try ser.writeU8(0); // status = pending (à implémenter)
        try ser.writeU32(0); // result_len
        const response = ser.getWritten();
        self.network.send(self.network.ctx, peer_id, response);
    }
    
    // ═══════════════════════════════════════════════════════
    // WORK STEAL REQUEST (type 5)
    // ═══════════════════════════════════════════════════════
    
    pub fn handleWorkStealRequest(self: *Swarm, peer_id: [16]u8, payload: []const u8) !void {
        var des = codec.Deserializer.init(payload);
        const capacity = try des.readU32();
        
        // Extraire des sous-graphes de l'egraph local
        const work_units = try self.extractWorkUnits(capacity);
        defer self.allocator.free(work_units);
        
        // Sérialiser la réponse
        var response_buf: [8192]u8 = undefined;
        var ser = codec.Serializer.init(self.allocator, &response_buf);
        try ser.writeU8(6); // work_steal_response
        try ser.writeU32(@intCast(work_units.len));
        
        for (work_units) |unit| {
            try serializeExpression(&ser, self.store, unit);
        }
        
        self.network.send(self.network.ctx, peer_id, ser.getWritten());
    }
    
    fn extractWorkUnits(self: *Swarm, capacity: u32) ![]expr_mod.Id {
        _ = self;
        // TODO: Sélectionner capacity eclasses à déléguer
        // Critères : eclasses avec beaucoup de nodes, non-canoniques, etc.
        const result = try self.allocator.alloc(expr_mod.Id, 0);
        _ = capacity;
        return result;
    }
};

// ═══════════════════════════════════════════════════════
// SÉRIALISATION (pour work_steal_response)
// ═══════════════════════════════════════════════════════

pub fn serializeExpression(
    ser: *codec.Serializer,
    store: *expr_mod.Store,
    root_id: expr_mod.Id,
) !void {
    // Parcours topologique de l'expression
    var visited = std.AutoHashMap(expr_mod.Id, u32).init(store.allocator);
    defer visited.deinit();

    var worklist = std.ArrayList(expr_mod.Id).init(store.allocator);
    defer worklist.deinit();

    try worklist.append(root_id);
    var node_count: u32 = 0;

    // Count phase (pour écrire count en premier)
    while (worklist.items.len > 0) {
        const id = worklist.pop();
        if (visited.contains(id)) continue;
        try visited.put(id, node_count);
        node_count += 1;

        const node = store.get(id);
        switch (node) {
            .binop => |b| {
                try worklist.append(b.left);
                try worklist.append(b.right);
            },
            .apply => |a| {
                try worklist.append(a.func);
                for (a.args) |arg| try worklist.append(arg);
            },
            else => {},
        }
    }

    // Write count
    try ser.writeU32(node_count);

    // Write nodes in order
    var iter = visited.iterator();
    while (iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const node = store.get(id);
        try serializeNode(ser, store, node, visited);
    }
}

fn serializeNode(
    ser: *codec.Serializer,
    store: *expr_mod.Store,
    node: expr_mod.Node,
    visited: std.AutoHashMap(expr_mod.Id, u32),
) !void {
    _ = store;
    switch (node) {
        .lit => |l| {
            try ser.writeU8(0x01);
            try ser.writeI64(l.value);
        },
        .sym => |s| {
            try ser.writeU8(0x02);
            try ser.writeU16(@intCast(s.name.len));
            try ser.writeBytes(s.name);
        },
        .binop => |b| {
            try ser.writeU8(0x04);
            try ser.writeU8(b.op);
            try ser.writeU32(visited.get(b.left).?);
            try ser.writeU32(visited.get(b.right).?);
        },
        .apply => |a| {
            try ser.writeU8(0x03);
            try ser.writeU32(visited.get(a.func).?);
            try ser.writeU8(@intCast(a.args.len));
            for (a.args) |arg| {
                try ser.writeU32(visited.get(arg).?);
            }
        },
        else => {},
    }
}

// ═══════════════════════════════════════════════════════
// TICK LOOP (fonctionne en natif ET en wasm)
// ═══════════════════════════════════════════════════════

pub const TickResult = struct {
    messages_processed: u32,
    egraph_saturated: bool,
};

pub fn tick(self: *Swarm, network_poll: anytype, time_budget_ms: u64) TickResult {
    const start = std.time.milliTimestamp();
    var result = TickResult{ .messages_processed = 0, .egraph_saturated = false };

    // PHASE 1 : Poller les messages réseau
    while (true) {
        const msg = network_poll() orelse break;

        self.handleMessage(
            msg.peer_id,
            msg.msg_type,
            msg.payload,
        ) catch {};

        result.messages_processed += 1;

        // Limiter à 10 messages par tick pour ne pas bloquer
        if (result.messages_processed >= 10) break;
    }

    // PHASE 2 : Faire avancer l'egraph avec le budget restant
    const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start));
    if (elapsed < time_budget_ms) {
        const remaining = time_budget_ms - elapsed;
        // TODO: egraph.saturate(remaining)
        _ = remaining;
    }

    return result;
}
