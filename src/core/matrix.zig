const std = @import("std");
const platform = @import("platform");

pub const BobId = u32;

pub const Edge = struct {
    source: BobId,
    target: BobId,
    label: []const u8,
};

pub const Stats = struct {
    nodes: usize,
    symbols: usize,
    approx_bytes: usize,
};

pub const HBinOpKind = enum {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Eq,
    Neq,
    Lt,
    Gt,
    Lte,
    Gte,
    And,
    Or,
    BitAnd,
    BitOr,
    Xor,
    Shl,
    Shr,
    Compose,
};

pub const BobNode = union(enum) {
    // Atomes de base
    Symbol: []const u8,
    Literal: []const u8,

    // Lambda calculus
    Lambda: struct {
        param: BobId,
        body: BobId,
    },
    Apply: struct {
        function: BobId,
        args: []BobId,
    },
    Let: struct {
        name: BobId,
        value: BobId,
        body: BobId,
    },

    // Logique (Prolog style)
    Relation: struct {
        predicate: BobId,
        args: []BobId,
    },
    Rule: struct {
        head: BobId,
        body: []BobId,
    },

    // Types
    Type: struct { name: []const u8 },
    FunctionType: struct { input: BobId, output: BobId },
    ForAll: struct { variable: BobId, body: BobId },

    // Effets / distribué
    Effect: struct { kind: []const u8, value: BobId },
    Spawn: struct { task: BobId },
    Channel: struct { name: BobId },
    Send: struct { channel: BobId, value: BobId },
    Receive: struct { channel: BobId },

    // Optimisation / eGraph
    Eq: struct { left: BobId, right: BobId },

    // Bridge natif
    NativeCode: *NativeNode,

    // Fallback / divers
    Unknown,
    Bind: struct { target: BobId, value: BobId },
    Aggregate: struct { op: enum { Sum, Product, Integral, Union }, variable: BobId, range: BobId, body: BobId },
    Query: struct { goal: BobId },
    Hole: struct { name: []const u8, expected_type: ?BobId = null },
    Edge: Edge,
    Pi: struct { domain: BobId, codomain: BobId },
    EClass: []BobId,
    Mailbox: []BobId,
    Grammar: struct {
        lang_name: []const u8,
        so_path: []const u8, // Chemin vers tree-sitter-c.so, etc.
    },
    ExternalSymbol: struct {
        lib: []const u8,
        symbol: []const u8,
        signature_id: BobId, // Pointeur vers un nœud FunctionType
    },
    // Le lien vers le monde extérieur
    // Bridge natif & FFI
    ExternLink: struct {
        lib_name: []const u8, // ex: "libp2p"
        symbol_name: []const u8, // ex: "libp2p_host_new"
        abi: enum { C, StdCall, FastCall },
    },
    Declaration,
    String: []const u8,
    RawPointer: *anyopaque,
    // Type complexe pour le FFI
    CType: struct {
        name: []const u8,
        size: usize,
        align_val: usize,
    },

    Vessel: struct {
        blob_id: u32, // Index vers le binaire WASM brut
        export_name: []u8, // La fonction à appeler dans le module
    },
    Blob: []u8, // Stockage binaire (Wasm, images, etc.),
    HFunc: struct {
        name: BobId,
        params: []BobId, // Chaque param est un HParam
        ret_type: ?BobId, // Pointe vers un Type ou Symbol
        body: BobId, // Pointe vers un HBlock
    },
    HParam: struct {
        name: BobId,
        type_id: BobId,
    },
    HBlock: []BobId, // Liste ordonnée de statements
    HVarDecl: struct {
        name: BobId,
        type_id: ?BobId,
        init_value: ?BobId,
        mutable: bool,
    },
    HCall: struct {
        callee: BobId,
        args: []BobId,
    },
    HBinOp: struct {
        op: HBinOpKind,
        left: BobId,
        right: BobId,
    },
    HIf: struct {
        condition: BobId,
        then_body: BobId,
        else_body: ?BobId,
    },
    HWhile: struct {
        condition: BobId,
        body: BobId,
    },
    HReturn: struct {
        value: ?BobId,
    },
    HQuote: struct {
        expr: BobId,
    },
    HUnquote: struct {
        expr: BobId,
    },
    HAssign: struct {
        target: BobId,
        value: BobId,
    },
    HFieldAccess: struct {
        object: BobId,
        field: BobId,
    },
    HIndex: struct {
        array: BobId,
        index: BobId,
    },
    HStructDef: struct {
        name: BobId,
        fields: []BobId, // Chaque field est un HParam
    },
    HIntLit: i64,
    HFloatLit: f64,
    HStringLit: []const u8,
    HBoolLit: bool,
};

pub const NativeNode = struct {
    code: []const u8,
    origin: []const u8,
    line: u32,
};

pub const Matrix = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(BobId, BobNode),
    symbol_index: std.StringHashMap(BobId),
    union_find: std.AutoHashMap(BobId, BobId),
    rules: std.StringHashMap(*const fn (*Matrix, BobId) anyerror!void),
    next_id: BobId = 0,
    pending_mail: std.ArrayListUnmanaged(struct { target: BobId, message: BobId }) = .{},
    mutex: platform.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) Matrix {
        return Matrix{
            .allocator = allocator,
            .nodes = std.AutoHashMap(BobId, BobNode).init(allocator),
            .symbol_index = std.StringHashMap(BobId).init(allocator),
            .union_find = std.AutoHashMap(BobId, BobId).init(allocator),
            .rules = std.StringHashMap(*const fn (*Matrix, BobId) anyerror!void).init(allocator),
        };
    }

    pub fn deinit(self: *Matrix) void {
        // 1. Libérer les chaînes et les tableaux dynamiques possédés
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .Symbol => |s| self.allocator.free(s),
                .Literal => |l| self.allocator.free(l),
                .Edge => |e| self.allocator.free(e.label),
                .Hole => |h| self.allocator.free(h.name),
                .NativeCode => |nc| {
                    self.allocator.free(nc.code);
                    self.allocator.free(nc.origin);
                    self.allocator.destroy(nc);
                },
                // AJOUT : Libérer les tableaux de la Forge
                .HFunc => |func| {
                    self.allocator.free(func.params);
                },
                .HBlock => |ids| {
                    self.allocator.free(ids);
                },
                .Apply => |app| {
                    if (app.args.len > 0) self.allocator.free(app.args);
                },
                .Relation => |rel| {
                    if (rel.args.len > 0) self.allocator.free(rel.args);
                },
                .Rule => |rule| {
                    if (rule.body.len > 0) self.allocator.free(rule.body);
                },
                .EClass => |ids| {
                    if (ids.len > 0) self.allocator.free(ids);
                },
                .Mailbox => |ids| {
                    if (ids.len > 0) self.allocator.free(ids);
                },
                else => {}, // Les autres nœuds ne possèdent pas de mémoire allouée ici
            }
        }

        // 2. Libérer les structures de données
        self.nodes.deinit();
        self.symbol_index.deinit();
        self.union_find.deinit();
        self.rules.deinit();
        self.pending_mail.deinit(self.allocator);
    }

    pub fn clear(self: *Matrix) void {
        self.nodes.clearAndFree();
        self.symbol_index.clearAndFree();
        self.next_id = 0;
    }

    // Fonction "Safe" à appeler depuis le Dispatcher
    fn postMessageLocked(self: *Matrix, target: BobId, message: BobId) !void {
        try self.pending_mail.append(self.allocator, .{ .target = target, .message = message });
    }
    pub fn postMessage(self: *Matrix, target: BobId, message: BobId) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.postMessageLocked(target, message);
    }

    // --- Ajout de noeuds ---
    fn addNodeLocked(self: *Matrix, node: BobNode) !BobId {
        const id = self.next_id;
        try self.nodes.put(id, node);
        try self.union_find.put(id, id);
        if (node == .Symbol) {
            try self.symbol_index.put(node.Symbol, id);
        }
        self.next_id += 1;
        return id;
    }

    pub fn addNode(self: *Matrix, node: BobNode) !BobId {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.addNodeLocked(node);
    }

    fn addUniqueSymbolLocked(self: *Matrix, name: []const u8) !BobId {
        if (self.symbol_index.get(name)) |id| return id;

        const owned_name = try self.allocator.dupe(u8, name);
        return try self.addNodeLocked(.{ .Symbol = owned_name });
    }
    pub fn addUniqueSymbol(self: *Matrix, name: []const u8) !BobId {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.addUniqueSymbolLocked(name);
    }

    fn addEdgeLocked(self: *Matrix, source: BobId, target: BobId, label: []const u8) !void {
        const owned_label = try self.allocator.dupe(u8, label);
        _ = try self.addNodeLocked(.{ .Edge = .{ .source = source, .target = target, .label = owned_label } });
    }
    pub fn addEdge(self: *Matrix, source: BobId, target: BobId, label: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.addEdgeLocked(source, target, label);
    }

    fn addHoleLocked(self: *Matrix, name: []const u8, expected_type: ?BobId) !BobId {
        const owned_name = try self.allocator.dupe(u8, name);
        return try self.addNodeLocked(.{ .Hole = .{ .name = owned_name, .expected_type = expected_type } });
    }
    pub fn addHole(self: *Matrix, name: []const u8, expected_type: ?BobId) !BobId {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.addHoleLocked(name, expected_type);
    }

    // --- Union-Find basique ---
    fn findCanonicalLocked(self: *Matrix, id: BobId) BobId {
        var curr = id;
        while (self.union_find.get(curr)) |parent| {
            if (parent == curr) break;
            curr = parent;
        }
        return curr;
    }
    pub fn findCanonical(self: *Matrix, id: BobId) BobId {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.findCanonicalLocked(id);
    }

    fn fuseNodesLocked(self: *Matrix, a: BobId, b: BobId) void {
        const root_a = self.findCanonicalLocked(a);
        const root_b = self.findCanonicalLocked(b);
        if (root_a != root_b) {
            self.union_find.put(root_a, root_b) catch {};
        }
    }
    pub fn fuseNodes(self: *Matrix, a: BobId, b: BobId) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.fuseNodesLocked(a, b);
    }

    fn typesEqualLocked(self: *Matrix, a: BobId, b: BobId) bool {
        return self.findCanonicalLocked(a) == self.findCanonicalLocked(b);
    }
    pub fn typesEqual(self: *Matrix, a: BobId, b: BobId) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.typesEqualLocked(a, b);
    }

    fn saturateLocked(self: *Matrix) void {
        // PHASE 0 : Traitement intelligent des Mailboxes
        for (self.pending_mail.items) |mail| {
            // 1. Unification structurelle (comportement par défaut)
            self.fuseNodesLocked(mail.target, mail.message);

            // 2. Déclenchement de réaction
            // Si le destinataire a une règle spécifique (ex: un Agent ou une Task)
            const node = self.nodes.get(mail.target) orelse continue;
            switch (node) {
                .Spawn => |s| {
                    // Un message envoyé à un Spawn pourrait relancer la tâche
                    platform.debug.print("[REACTION] Message reçu par Task {d}\n", .{s.task});
                },
                .Symbol => |name| {
                    // ATTENTION : self.mutex est tenu à ce point. Toute fonction enregistrée dans
                    // self.rules qui rappellerait une méthode PUBLIQUE de Matrix (verrouillée)
                    // sur ce même self provoquerait un deadlock. Les callbacks doivent utiliser
                    // exclusivement les variantes `xxxLocked`.

                    // Si le symbole est enregistré dans 'rules', on appelle la fonction
                    if (self.rules.get(name)) |func| {
                        func(self, mail.message) catch {};
                    }
                },
                else => {},
            }
        }
        self.pending_mail.clearRetainingCapacity();

        // --- PHASE 1 : Saturation des égalités (ton code actuel) ---
        var changed = true;
        while (changed) : (changed = false) {
            var it = self.nodes.iterator();
            while (it.next()) |e| {
                if (e.value_ptr.* == .Eq) {
                    const eq = e.value_ptr.Eq;
                    const root_left = self.findCanonicalLocked(eq.left);
                    const root_right = self.findCanonicalLocked(eq.right);
                    if (root_left != root_right) {
                        self.union_find.put(root_left, root_right) catch {};
                        changed = true;
                    }
                }
            }
        }

        // --- PHASE 2 : Path Compression (Optimisation) ---
        var uf_it = self.union_find.iterator();
        while (uf_it.next()) |e| {
            e.value_ptr.* = self.findCanonicalLocked(e.key_ptr.*);
        }
    }
    pub fn saturate(self: *Matrix) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.saturateLocked();
    }

    // --- Symbol lookup ---
    fn findSymbolLocked(self: *Matrix, name: []const u8) ?BobId {
        return self.symbol_index.get(name);
    }
    pub fn findSymbol(self: *Matrix, name: []const u8) ?BobId {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.findSymbolLocked(name);
    }

    fn getSymbolNameLocked(self: *Matrix, id: BobId) ?[]const u8 {
        const node = self.nodes.get(id) orelse return null;
        return switch (node) {
            .Symbol => |s| s,
            else => null,
        };
    }
    pub fn getSymbolName(self: *Matrix, id: BobId) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getSymbolNameLocked(id);
    }

    // --- Stats / utilitaires ---
    fn getStatsLocked(self: *Matrix) Stats {
        return .{
            .nodes = self.nodes.count(),
            .symbols = self.symbol_index.count(),
            .approx_bytes = self.nodes.count() * @sizeOf(BobNode),
        };
    }
    pub fn getStats(self: *Matrix) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.getStatsLocked();
    }

    fn unifyLocked(self: *Matrix, a: BobId, b: BobId) !void {
        var root_a = a;
        while (true) {
            const parent = self.union_find.get(root_a) orelse break;
            if (parent == root_a) break;
            root_a = parent;
        }

        var root_b = b;
        while (true) {
            const parent = self.union_find.get(root_b) orelse break;
            if (parent == root_b) break;
            root_b = parent;
        }

        if (root_a != root_b) {
            try self.union_find.put(root_a, root_b);
        }
    }
    pub fn unify(self: *Matrix, a: BobId, b: BobId) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.unifyLocked(a, b);
    }

    fn serializeMatrixDeltaLocked(self: *Matrix, buffer: []u8, last_known_id: BobId) usize {
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        // On itère de last_known_id + 1 jusqu'à next_id
        var id: BobId = last_known_id + 1;
        while (id < self.next_id) : (id += 1) {
            const node = self.nodes.get(id) orelse continue;

            // Format compact : ID:TYPE:DATA|
            switch (node) {
                .Symbol => |s| writer.print("{d}:SYM:{s}|", .{ id, s }) catch break,
                .Literal => |l| writer.print("{d}:LIT:{s}|", .{ id, l }) catch break,
                .Eq => |eq| writer.print("{d}:EQ:{d},{d}|", .{ id, eq.left, eq.right }) catch break,
                .Bind => |b| writer.print("{d}:BND:{d},{d}|", .{ id, b.target, b.value }) catch break,
                .Edge => |e| writer.print("{d}:EDG:{d},{s},{d}|", .{ id, e.source, e.label, e.target }) catch break,
                else => writer.print("{d}:UNK:|", .{id}) catch break,
            }
        }
        return fbs.getPos() catch 0;
    }
    pub fn serializeMatrixDelta(self: *Matrix, buffer: []u8, last_known_id: BobId) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.serializeMatrixDeltaLocked(buffer, last_known_id);
    }

    fn printTraceLocked(self: *Matrix, source_id: BobId) void {
        platform.debug.print("--- [TRACE] {s} (ID:{d}) ---\n", .{ self.getSymbolNameLocked(source_id) orelse "Unknown", source_id });
        var it = self.nodes.iterator();
        var found_map = std.AutoHashMap(BobId, []const u8).init(self.allocator);
        defer found_map.deinit();

        while (it.next()) |entry| {
            if (entry.value_ptr.* == .Edge) {
                const e = entry.value_ptr.Edge;
                if (e.source == source_id) {
                    // On n'affiche qu'une fois chaque destination pour éviter le bruit de 'c'
                    if (!found_map.contains(e.target)) {
                        const name = self.getSymbolNameLocked(e.target) orelse "UnknownNode";
                        platform.debug.print("  {s: <8} -> {s: <20} (ID:{d})\n", .{ e.label, name, e.target });
                        found_map.put(e.target, e.label) catch {};
                    }
                }
            }
        }
        platform.debug.print("--------------------------------------\n", .{});
    }
    pub fn printTrace(self: *Matrix, source_id: BobId) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.printTraceLocked(source_id);
    }

    // ---------------------------
    // Synchronisation de la matrice
    // ---------------------------
    fn applySyncLocked(self: *Matrix, sync_data: []const u8) !void {
        var entries = std.mem.splitScalar(u8, sync_data, '|');

        while (entries.next()) |entry| {
            if (entry.len == 0) continue;
            var parts = std.mem.splitScalar(u8, entry, ':');
            const id_str = parts.next() orelse continue;
            _ = id_str;
            const prefix = parts.next() orelse continue;

            if (std.mem.eql(u8, prefix, "SYM")) {
                _ = parts.next();
                const name = parts.next() orelse continue;
                _ = try self.addUniqueSymbolLocked(name);
            } else if (std.mem.eql(u8, prefix, "EDG")) {
                const src_id_str = parts.next() orelse continue;
                const label = parts.next() orelse continue;
                const tgt_id_str = parts.next() orelse continue;
                const src_id = std.fmt.parseInt(BobId, src_id_str, 10) catch continue;
                const tgt_id = std.fmt.parseInt(BobId, tgt_id_str, 10) catch continue;
                try self.addEdgeLocked(src_id, tgt_id, label);
            } else if (std.mem.eql(u8, prefix, "RAW")) {
                _ = parts.next(); // id_str inutile
                const code = parts.next() orelse continue;
                const native_ptr = try self.allocator.create(NativeNode);
                native_ptr.* = .{
                    .code = try self.allocator.dupe(u8, code),
                    .origin = "network_sync",
                    .line = 0,
                };
                _ = try self.addNodeLocked(.{ .NativeCode = native_ptr });
            }
        }
    }
    pub fn applySync(self: *Matrix, sync_data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.applySyncLocked(sync_data);
    }

    fn mergeDeltaLocked(self: *Matrix, data: []const u8) !void {
        // Dans ton serializeMatrixDelta, tu utilises writer.print avec le format "ID:TYPE:DATA|"
        // On va réutiliser cette logique de parsing textuelle pour rester cohérent.
        var entries = std.mem.splitScalar(u8, data, '|');
        var count: u32 = 0;

        while (entries.next()) |entry| {
            if (entry.len == 0) continue;

            var parts = std.mem.splitScalar(u8, entry, ':');
            _ = parts.next(); // On ignore l'ID distant pour l'instant (Bob crée ses propres IDs)
            const prefix = parts.next() orelse continue;
            const payload = parts.next() orelse continue;

            if (std.mem.eql(u8, prefix, "SYM")) {
                _ = try self.addUniqueSymbolLocked(payload);
                count += 1;
            } else if (std.mem.eql(u8, prefix, "EQ")) {
                var ids = std.mem.splitScalar(u8, payload, ',');
                const left_str = ids.next() orelse continue;
                const right_str = ids.next() orelse continue;
                // Note: l'unification directe ici est risquée car les IDs sont distants.
                // Une version robuste mapperait les IDs distants vers locaux.
                _ = left_str;
                _ = right_str;
            } else if (std.mem.eql(u8, prefix, "LIT")) {
                _ = try self.addNodeLocked(.{ .Literal = try self.allocator.dupe(u8, payload) });
                count += 1;
            }
        }

        if (count > 0) {
            platform.debug.print("[MATRIX] {d} nouvelles connaissances intégrées.\n", .{count});
        }
    }
    pub fn mergeDelta(self: *Matrix, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.mergeDeltaLocked(data);
    }

    // Itération sur les symboles avec verrou
    pub fn forEachSymbol(self: *Matrix, comptime callback: anytype, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var it = self.symbol_index.iterator();
        while (it.next()) |entry| {
            @call(.auto, callback, .{ entry.key_ptr.*, entry.value_ptr.* } ++ args);
        }
    }

    // Copie des symboles pour usage externe (ex: kanren)
    pub fn snapshotSymbols(self: *Matrix, allocator: std.mem.Allocator) !std.StringHashMap(BobId) {
        self.mutex.lock();
        defer self.mutex.unlock();
        var map = std.StringHashMap(BobId).init(allocator);
        var it = self.symbol_index.iterator();
        while (it.next()) |entry| {
            const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
            try map.put(key_dup, entry.value_ptr.*);
        }
        return map;
    }

    // Accès à un nœud par ID (avec verrou)
    pub fn getNode(self: *Matrix, id: BobId) ?BobNode {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.nodes.get(id);
    }

    // Itération sur les nœuds
    pub fn forEachNode(self: *Matrix, comptime callback: anytype, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            @call(.auto, callback, .{ entry.key_ptr.*, entry.value_ptr.* } ++ args);
        }
    }
};
