const std = @import("std");
const platform = @import("platform");
const Allocator = std.mem.Allocator;

pub const Id = u32;
pub const NULL: Id = std.math.maxInt(Id);
pub const Sym = u32;

pub const Span = struct {
    start: u32,
    len: u16,
    pub const EMPTY: Span = .{ .start = 0, .len = 0 };
    pub fn slice(self: Span, pool: []const Id) []const Id {
        return pool[self.start..][0..self.len];
    }
};

pub const RuntimeRef = union(enum) {
    theorem: u32,
    proof: u32,
    skill: u32,
    agent: u32,
};

pub const Lit = union(enum) {
    int: i64,
    float: f64,
    str: Sym,
    boolean: bool,
    unit,
    runtime: RuntimeRef,

    pub fn eql(a: Lit, b: Lit) bool {
        switch (a) {
            .int => |va| switch (b) {
                .int => |vb| return va == vb,
                else => return false,
            },
            .float => |va| switch (b) {
                .float => |vb| return va == vb,
                else => return false,
            },
            .str => |va| switch (b) {
                .str => |vb| return va == vb,
                else => return false,
            },
            .boolean => |va| switch (b) {
                .boolean => |vb| return va == vb,
                else => return false,
            },
            .unit => switch (b) {
                .unit => return true,
                else => return false,
            },
            .runtime => |va| switch (b) {
                .runtime => |vb| return std.meta.eql(va, vb),
                else => return false,
            },
        }
    }

    pub fn hash(self: Lit) u64 {
        var h: u64 = 0xcbf29ce484222325;
        const prime: u64 = 0x100000001b3;
        switch (self) {
            .int => |v| {
                h ^= 0;
                h *%= prime;
                h ^= @bitCast(v);
            },
            .float => |v| {
                h ^= 1;
                h *%= prime;
                h ^= @bitCast(v);
            },
            .str => |v| {
                h ^= 2;
                h *%= prime;
                h ^= @as(u64, v);
            },
            .boolean => |v| {
                h ^= 3;
                h *%= prime;
                h ^= @intFromBool(v);
            },
            .unit => {
                h ^= 4;
                h *%= prime;
            },
            .runtime => |v| {
                h ^= 5;
                h *%= prime;
                h ^= @intFromEnum(v);
                switch (v) {
                    .theorem => |x| {
                        h ^= @as(u64, x);
                        h *%= prime;
                    },
                    .proof => |x| {
                        h ^= @as(u64, x);
                        h *%= prime;
                    },
                    .skill => |x| {
                        h ^= @as(u64, x);
                        h *%= prime;
                    },
                    .agent => |x| {
                        h ^= @as(u64, x);
                        h *%= prime;
                    },
                }
            },
        }
        return h;
    }
};

/// Les 6 primitives fondamentales du noyau Heaven.
pub const Primitive = enum(u8) {
    lit,
    sym,
    apply,
    bind,
    lambda,
    relation,
};

pub const Tag = enum(u8) {
    // === 6 primitives fondamentales (noyau) ===
    lit,
    sym,
    apply,
    bind,
    lambda,
    relation,

    // === Frontend / extensions (doivent être lowered) ===
    hole,
    evar, // Métavariable interne (unification, tactics v3.5)
    true,
    false,
    int,
    float,
    string,
    var_tag,
    let,
    fun,
    eq,
    add,
    sub,
    mul,
    div,
    mod,
    and_tag,
    or_tag,
    not,
    cons,
    head,
    tail,
    tuple,
    block,
    seq,
    unit_lit,
    vector,
    vector_lit,
    sum,
    aggregate,

    // === Legacy tags (compatibilité descendante) ===
    source_file,
    block_legacy,
    call,
    binary,
    unary,
    identifier,
    str_legacy,
    bool_lit,
    pi_tag,
    universe_tag,
    ctor,
    data,
    forall,
    exists,
    arrow,
    sigma,
    pair,

    pub fn isPrimitive(self: Tag) bool {
        return switch (self) {
            .lit, .sym, .apply, .bind, .lambda, .relation => true,
            else => false,
        };
    }

    pub fn assertPrimitive(self: Tag) !void {
        if (!self.isPrimitive()) {
            return error.ExtensionNotLowered;
        }
    }

    pub fn asPrimitive(self: Tag) ?Primitive {
        return switch (self) {
            .lit => .lit,
            .sym => .sym,
            .apply => .apply,
            .bind => .bind,
            .lambda => .lambda,
            .relation => .relation,
            else => null,
        };
    }
};

pub const Node = struct {
    tag: Tag,
    payload: u32,
    aux: u32,
    span_a: Span,
    span_b: Span,
};

pub const StringInterner = struct {
    map: std.StringHashMapUnmanaged(Sym),
    list: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) StringInterner {
        return .{ .map = .{}, .list = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *StringInterner) void {
        for (self.list.items) |s| self.allocator.free(s);
        self.list.deinit(self.allocator);
        self.map.deinit(self.allocator);
    }

    pub fn intern(self: *StringInterner, s: []const u8) !Sym {
        if (self.map.get(s)) |id| return id;
        const owned = try self.allocator.dupe(u8, s);
        const id: Sym = @intCast(self.list.items.len);
        try self.list.append(self.allocator, owned);
        try self.map.put(self.allocator, owned, id);
        return id;
    }

    pub fn resolve(self: *const StringInterner, id: Sym) []const u8 {
        return self.list.items[id];
    }

    pub fn lookup(self: *const StringInterner, s: []const u8) ?Sym {
        return self.map.get(s);
    }
};

pub const LowerError = error{
    ExtensionNotLowered,
    OutOfMemory,
};

/// Structural hash of a Core expression.
///
/// IMPORTANT:
/// - source spans are deliberately ignored;
/// - node IDs are deliberately ignored;
/// - hashes accelerate structural lookup but never establish equality;
/// - every semantic field of the six Core primitives participates.
///
/// The layout mirrors the Core encoding:
///
///   lit:      aux      -> literal
///   sym:      payload  -> symbol
///   apply:    payload  -> function, span_a -> arguments
///   bind:     payload  -> name,     aux    -> value
///   lambda:   payload  -> parameter, span_a -> body
///   relation: payload  -> head,     span_a -> lhs, span_b -> rhs
pub fn nodeHash(store: *const Store, id: Id) u64 {
    var hasher = std.hash.Wyhash.init(0);
    const node = store.get(id);

    hashTag(&hasher, node.tag);

    switch (node.tag) {
        .lit => {
            const lit = store.lits.items[node.aux];
            hashU64(&hasher, lit.hash());
        },

        .sym => {
            // Hash the interned symbol identity, not its source span.
            hashU32(&hasher, node.payload);
        },

        .apply => {
            hashU64(&hasher, nodeHash(store, node.payload));
            hashSpan(&hasher, store, node.span_a);
        },

        .bind => {
            hashU32(&hasher, node.payload);
            hashU32(&hasher, node.aux);
            hashSpan(&hasher, store, node.span_a);
            hashSpan(&hasher, store, node.span_b);
        },

        .lambda => {
            hashU32(&hasher, node.payload);
            hashSpan(&hasher, store, node.span_a);
            hashSpan(&hasher, store, node.span_b);
        },

        .relation => {
            hashU32(&hasher, node.payload);
            hashSpan(&hasher, store, node.span_a);
            hashSpan(&hasher, store, node.span_b);
        },

        else => {
            // nodeHash is primarily a Core operation. Keeping this
            // deterministic for frontend nodes is useful for diagnostics,
            // but such nodes must not enter the EGraph.
            hashU32(&hasher, node.payload);
            hashU32(&hasher, node.aux);
            hashSpan(&hasher, store, node.span_a);
            hashSpan(&hasher, store, node.span_b);
        },
    }

    return hasher.final();
}

/// Structural equality for Core expressions.
///
/// This is the semantic equality used to disambiguate hash-consing
/// candidates. A hash collision must never imply equality.
///
/// Source spans, node IDs and allocation locations are ignored.
pub fn structuralEql(store: *const Store, a: Id, b: Id) bool {
    if (a >= store.nodes.items.len or b >= store.nodes.items.len) {
        return false;
    }

    const na = store.get(a);
    const nb = store.get(b);

    if (na.tag != nb.tag) return false;

    switch (na.tag) {
        .lit => {
            if (na.aux >= store.lits.items.len or
                nb.aux >= store.lits.items.len)
            {
                return false;
            }

            return store.lits.items[na.aux].eql(store.lits.items[nb.aux]);
        },

        .sym => {
            return na.payload == nb.payload;
        },

        .apply => {
            if (na.payload >= store.nodes.items.len or
                nb.payload >= store.nodes.items.len)
            {
                return false;
            }

            if (!structuralEql(store, na.payload, nb.payload)) {
                return false;
            }

            return structuralSpanEql(store, na.span_a, nb.span_a);
        },

        .bind => {
            if (na.payload != nb.payload) return false;
            if (na.aux != nb.aux) return false;

            return structuralSpanEql(store, na.span_a, nb.span_a) and
                structuralSpanEql(store, na.span_b, nb.span_b);
        },

        .evar => {
            // Les evars sont comparés par identité : deux evars de payload
            // différent ne sont JAMAIS structurellement égaux, même si
            // leurs contextes de création se ressemblent.
            return na.payload == nb.payload;
        },

        .lambda => {
            if (na.payload != nb.payload) return false;

            return structuralSpanEql(store, na.span_a, nb.span_a) and
                structuralSpanEql(store, na.span_b, nb.span_b);
        },

        .relation => {
            if (na.payload != nb.payload) return false;

            return structuralSpanEql(store, na.span_a, nb.span_a) and
                structuralSpanEql(store, na.span_b, nb.span_b);
        },

        else => {
            // Frontend/legacy expressions are not Core identity objects.
            // Still provide deterministic structural equality for callers
            // outside the EGraph.
            if (na.payload != nb.payload or na.aux != nb.aux) {
                return false;
            }

            return structuralSpanEql(store, na.span_a, nb.span_a) and
                structuralSpanEql(store, na.span_b, nb.span_b);
        },
    }
}

fn structuralSpanEql(
    store: *const Store,
    a: Span,
    b: Span,
) bool {
    if (a.len != b.len) return false;

    const aa = a.slice(store.pool.items);
    const bb = b.slice(store.pool.items);

    for (aa, bb) |x, y| {
        if (!structuralEql(store, x, y)) {
            return false;
        }
    }

    return true;
}

fn hashTag(hasher: *std.hash.Wyhash, tag: Tag) void {
    const value: u8 = @intFromEnum(tag);
    hasher.update(std.mem.asBytes(&value));
}

fn hashU32(hasher: *std.hash.Wyhash, value: u32) void {
    hasher.update(std.mem.asBytes(&value));
}

fn hashU64(hasher: *std.hash.Wyhash, value: u64) void {
    hasher.update(std.mem.asBytes(&value));
}

fn hashSpan(
    hasher: *std.hash.Wyhash,
    store: *const Store,
    span: Span,
) void {
    hashU32(hasher, span.len);

    for (span.slice(store.pool.items)) |child| {
        hashU64(hasher, nodeHash(store, child));
    }
}

pub fn toString(store: *const Store, id: Id, allocator: std.mem.Allocator) ![]u8 {
    return store.toString(id, allocator);
}

pub fn toStringInfix(store: *const Store, id: Id, allocator: std.mem.Allocator) ![]u8 {
    return store.toString(id, allocator);
}

pub const Store = struct {
    allocator: Allocator,
    nodes: std.ArrayListUnmanaged(Node),
    pool: std.ArrayListUnmanaged(Id),
    lits: std.ArrayListUnmanaged(Lit),
    interner: StringInterner,

    pub fn init(allocator: Allocator) Store {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .pool = .{},
            .lits = .{},
            .interner = StringInterner.init(allocator),
        };
    }

    pub fn deinit(self: *Store) void {
        self.nodes.deinit(self.allocator);
        self.pool.deinit(self.allocator);
        self.lits.deinit(self.allocator);
        self.interner.deinit();
    }

    /// Snapshot d'une slice d'Ids issue de pool.items.
    /// À utiliser AVANT tout appel qui peut réallouer le pool
    /// (apply, pushSpan, reserveSpan, lowerRec, evaluate, etc.).
    ///
    /// Libération : `self.allocator.free(snapshot)`, ou via `defer`.
    pub fn snapshotArgs(self: *Store, allocator: Allocator, args: []const Id) ![]Id {
        _ = self;
        assertNoDangling(args);
        const copy = try allocator.alloc(Id, args.len);
        @memcpy(copy, args);
        return copy;
    }

    pub fn assertNoDangling(slice: []const Id) void {
        if (!platform.target.is_debug) return;
        for (slice) |id| {
            if (id == 0xAAAAAAAA) {
                @panic("dangling Id in slice — snapshot manquant");
            }
        }
    }

    pub fn addNode(self: *Store, node: Node) !Id {
        const id: Id = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return id;
    }

    pub fn addLit(self: *Store, l: Lit) !u32 {
        const idx: u32 = @intCast(self.lits.items.len);
        try self.lits.append(self.allocator, l);
        return idx;
    }

    pub fn get(self: *const Store, id: Id) Node {
        // GARDE : attraper TOUT accès à un Id invalide AVEC sa stack !
        if (id >= self.nodes.items.len) {
            platform.debug.print("[GET BUG] id={d} >= len={d} — STACK TRACE MANQUANT\n", .{ id, self.nodes.items.len });
            @panic("invalid Id access"); // crash MAIS avec le message
        }
        return self.nodes.items[id];
    }

    pub fn set(self: *Store, id: Id, node: Node) void {
        self.nodes.items[id] = node;
    }

    /// Duplique le contenu d'un Span dans un ArrayListUnmanaged.
    /// Utiliser AVANT tout appel qui peut réallouer `pool` :
    /// reserveSpan, pushSpan, apply, relation.
    pub fn dupSpan(self: *Store, span: Span) !std.ArrayListUnmanaged(Id) {
        var copy = std.ArrayListUnmanaged(Id){};
        try copy.appendSlice(self.allocator, self.spanSliceConst(span));
        return copy;
    }

    fn copyPoolSlice(self: *Store, s: []const Id) ![]Id {
        const copy = try self.allocator.alloc(Id, s.len);
        @memcpy(copy, s);
        return copy;
    }

    pub fn reserveSpan(self: *Store, length: usize) !Span {
        const start: u32 = @intCast(self.pool.items.len);
        try self.pool.resize(self.allocator, self.pool.items.len + length);
        // zéro-init — un slot oublié donne 0 (node 0, pas crash) au lieu de 0xAAAAAAAA
        @memset(self.pool.items[start .. start + length], 0);
        return .{ .start = start, .len = @intCast(length) };
    }

    pub fn spanSlice(self: *Store, span: Span) []Id {
        return self.pool.items[span.start..][0..span.len];
    }

    pub fn spanSliceConst(self: *const Store, span: Span) []const Id {
        return self.pool.items[span.start..][0..span.len];
    }

    pub fn len(self: *const Store) usize {
        return self.nodes.items.len;
    }

    /// Returns true iff the expression node itself belongs to the six-node Core.
    ///
    /// This does not recursively validate children. Use `assertCoreExpr()`
    /// for recursive validation.
    pub fn isCore(self: *const Store, id: Id) bool {
        if (id >= self.nodes.items.len) return false;
        return self.nodes.items[id].tag.isPrimitive();
    }

    fn assertCoreSpan(self: *const Store, span: Span) error{ InvalidExpr, ExtensionNotLowered }!void {
        const children = span.slice(self.pool.items);

        for (children) |child| {
            try self.assertCoreExpr(child);
        }
    }

    pub fn assertCoreExpr(self: *const Store, id: Id) error{ InvalidExpr, ExtensionNotLowered }!void {
        if (id == NULL or id >= self.nodes.items.len) {
            return error.InvalidExpr;
        }

        const node = self.nodes.items[id];

        if (!node.tag.isPrimitive()) {
            return error.ExtensionNotLowered;
        }

        switch (node.tag) {
            .lit => {
                if (node.aux >= self.lits.items.len) {
                    return error.InvalidExpr;
                }

                try self.assertCoreSpan(node.span_a);
                try self.assertCoreSpan(node.span_b);
            },

            .sym => {
                if (node.payload >= self.interner.list.items.len) {
                    return error.InvalidExpr;
                }

                try self.assertCoreSpan(node.span_a);
                try self.assertCoreSpan(node.span_b);
            },

            .apply => {
                if (node.payload >= self.nodes.items.len) {
                    return error.InvalidExpr;
                }

                if (node.span_a.len == 0) {
                    return error.InvalidExpr;
                }

                const children = node.span_a.slice(self.pool.items);

                if (children[0] != node.payload) {
                    return error.InvalidExpr;
                }

                try self.assertCoreSpan(node.span_a);
                try self.assertCoreSpan(node.span_b);
            },

            .bind => {
                // Core invariant:
                //   payload = binding name (Sym)
                //   aux     = 0
                //   span_a  = [value, body]
                //   span_b  = EMPTY

                if (node.payload >= self.interner.list.items.len) {
                    return error.InvalidExpr;
                }

                if (node.aux != 0) {
                    return error.InvalidExpr;
                }

                if (node.span_a.len != 2) {
                    return error.InvalidExpr;
                }

                if (node.span_b.len != 0) {
                    return error.InvalidExpr;
                }

                const children = node.span_a.slice(self.pool.items);

                try self.assertCoreExpr(children[0]); // value
                try self.assertCoreExpr(children[1]); // body
            },

            .lambda => {
                // payload == 0 est actuellement utilisé comme sentinel
                // pour certaines lambdas sans paramètre.
                if (node.payload != 0 and
                    node.payload >= self.interner.list.items.len)
                {
                    return error.InvalidExpr;
                }

                try self.assertCoreSpan(node.span_a);
                try self.assertCoreSpan(node.span_b);
            },

            .relation => {
                if (node.payload >= self.interner.list.items.len) {
                    return error.InvalidExpr;
                }

                try self.assertCoreSpan(node.span_a);
                try self.assertCoreSpan(node.span_b);
            },

            else => unreachable,
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Méthodes helper frontend (compatibilité descendante)
    // ═══════════════════════════════════════════════════════════════

    pub fn sym(self: *Store, name: []const u8) !Id {
        const s = try self.interner.intern(name);
        return self.addNode(.{ .tag = .sym, .payload = s, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    }

    pub fn symId(self: *Store, s: Sym) !Id {
        return self.addNode(.{ .tag = .sym, .payload = s, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    }

    pub fn int(self: *Store, val: i64) !Id {
        return self.lit(.{ .int = val });
    }

    pub fn float(self: *Store, val: f64) !Id {
        return self.lit(.{ .float = val });
    }

    pub fn boolean(self: *Store, val: bool) !Id {
        return self.lit(.{ .boolean = val });
    }

    pub fn unitLit(self: *Store) !Id {
        return self.lit(.unit);
    }

    /// Compteur global pour les evars (métavariables internes).
    var evar_counter: u32 = 0;

    /// Crée une nouvelle métavariable, avec un payload unique.
    /// À terme, la substitution associera chaque payload à un Id.
    pub fn mkEvar(self: *Store) !Id {
        evar_counter += 1;
        return self.addNode(.{
            .tag = .evar,
            .payload = evar_counter,
            .aux = 0,
            .span_a = Span.EMPTY,
            .span_b = Span.EMPTY,
        });
    }

    /// Retourne le payload de l'evar, ou null si `id` n'est pas un evar.
    pub fn isEvar(self: *Store, id: Id) ?u32 {
        if (id >= self.len()) return null;
        const node = self.get(id);
        if (node.tag != .evar) return null;
        return @intCast(node.payload);
    }

    pub fn hole(self: *Store, idx: u32) !Id {
        return self.addNode(.{ .tag = .hole, .payload = idx, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    }

    pub fn lit(self: *Store, value: Lit) !Id {
        try self.lits.append(self.allocator, value);
        const idx = self.lits.items.len - 1;
        return self.addNode(.{
            .tag = .lit,
            .payload = 0,
            .aux = @as(u32, @intCast(idx)),
            .span_a = .{ .start = 0, .len = 0 },
            .span_b = .{ .start = 0, .len = 0 },
        });
    }

    pub fn universe(self: *Store) !Id {
        return self.addNode(.{ .tag = .universe_tag, .payload = 0, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    }

    pub fn bind(self: *Store, name: []const u8, val: Id) !Id {
        const s = try self.interner.intern(name);
        const span = try self.reserveSpan(2);
        self.pool.items[span.start] = val;
        self.pool.items[span.start + 1] = try self.unitLit(); // corps par défaut = unit
        return self.addNode(.{ .tag = .bind, .payload = s, .aux = 0, .span_a = span, .span_b = Span.EMPTY });
    }

    pub fn lambda(self: *Store, params: []const []const u8, body: Id) !Id {
        if (params.len == 0) {
            return self.addNode(.{ .tag = .lambda, .payload = 0, .aux = 0, .span_a = try self.singleSpan(body), .span_b = Span.EMPTY });
        }
        // Curryfication : lambda(x, y, body) -> lambda(x, lambda(y, body))
        var cur = body;
        var i: usize = params.len;
        while (i > 0) {
            i -= 1;
            const s = try self.interner.intern(params[i]);
            const span = try self.singleSpan(cur);
            cur = try self.addNode(.{ .tag = .lambda, .payload = s, .aux = 0, .span_a = span, .span_b = Span.EMPTY });
        }
        return cur;
    }

    pub fn lambdaNative(self: *Store, params: []const []const u8, body: Id) !Id {
        return self.lambda(params, body);
    }

    pub fn relation(
        self: *Store,
        head: []const u8,
        args1: []const Id,
        args2: []const Id,
    ) !Id {
        // Snapshot les DEUX args avant les reserveSpan
        var snap1 = std.ArrayListUnmanaged(Id){};
        defer snap1.deinit(self.allocator);
        try snap1.appendSlice(self.allocator, args1);

        var snap2 = std.ArrayListUnmanaged(Id){};
        defer snap2.deinit(self.allocator);
        try snap2.appendSlice(self.allocator, args2);

        const s = try self.interner.intern(head);

        const span_a = try self.reserveSpan(snap1.items.len);
        @memcpy(self.pool.items[span_a.start .. span_a.start + snap1.items.len], snap1.items);

        const span_b = try self.reserveSpan(snap2.items.len);
        @memcpy(self.pool.items[span_b.start .. span_b.start + snap2.items.len], snap2.items);

        return self.addNode(.{
            .tag = .relation,
            .payload = s,
            .aux = 0,
            .span_a = span_a,
            .span_b = span_b,
        });
    }

    pub fn apply(self: *Store, func: Id, args: []const Id) !Id {
        // ── DEBUG : détecter l'ID avant qu'il soit écrit ──
        for (args, 0..) |a, i| {
            if (a == 0xAAAAAAAA) {
                platform.debug.print("[apply CORRUPT] func={d} arg[{d}]=0xAA store.len={d}\n", .{ func, i, self.nodes.items.len });
                @panic("apply received corrupted arg");
            }
        }
        // Snapshot args AVANT reserveSpan
        var args_snap = std.ArrayListUnmanaged(Id){};
        defer args_snap.deinit(self.allocator);
        try args_snap.appendSlice(self.allocator, args);

        var fixed_func = func;

        if (platform.target.is_debug) {
            if (fixed_func >= self.nodes.items.len) {
                platform.debug.print("[apply BUG] func={d} >= {d}\n", .{ fixed_func, self.nodes.items.len });
                fixed_func = 0;
            }
            for (args_snap.items, 0..) |a, i| {
                if (a >= self.nodes.items.len) {
                    platform.debug.print("[apply BUG] arg[{d}]={d} >= {d}\n", .{ i, a, self.nodes.items.len });
                    args_snap.items[i] = 0;
                }
            }
        }

        const span = try self.reserveSpan(1 + args_snap.items.len);
        self.pool.items[span.start] = fixed_func;
        @memcpy(
            self.pool.items[span.start + 1 .. span.start + 1 + args_snap.items.len],
            args_snap.items,
        );
        return self.addNode(.{
            .tag = .apply,
            .payload = fixed_func,
            .aux = 0,
            .span_a = span,
            .span_b = Span.EMPTY,
        });
    }

    pub fn call(self: *Store, name: []const u8, args: []const Id) !Id {
        const func = try self.sym(name);
        return self.apply(func, args);
    }

    pub fn binop(self: *Store, op: []const u8, a: Id, b: Id) !Id {
        const op_sym = try self.sym(op);
        return self.apply(op_sym, &.{ a, b });
    }

    pub fn aggregate(self: *Store, op: []const u8, var_name: []const u8, lo: Id, hi: Id, body: Id) !Id {
        const op_sym = try self.sym(op);
        const var_sym = try self.sym(var_name);
        return self.apply(op_sym, &.{ var_sym, lo, hi, body });
    }

    pub fn push(self: *Store, node: Node) !Id {
        return self.addNode(node);
    }

    pub fn pushSpan(self: *Store, items: []const Id) !Span {
        // Snapshot AVANT reserveSpan : items peut aliasing pool
        var snap = std.ArrayListUnmanaged(Id){};
        defer snap.deinit(self.allocator);
        try snap.appendSlice(self.allocator, items);

        // GARDE : les Ids écrits doivent être valides
        for (snap.items, 0..) |it, i| {
            if (it >= self.nodes.items.len) {
                platform.debug.print("[pushSpan BUG] items[{d}]={d} >= {d}\n", .{ i, it, self.nodes.items.len });
            }
        }
        const span = try self.reserveSpan(snap.items.len);
        @memcpy(self.pool.items[span.start .. span.start + snap.items.len], snap.items);
        return span;
    }

    pub fn childPool(self: *const Store, id: Id) []const Id {
        const node = self.get(id);
        return node.span_a.slice(self.pool.items);
    }

    pub fn getLit(self: *const Store, aux: u32) Lit {
        return self.lits.items[aux];
    }

    fn singleSpan(self: *Store, id: Id) !Span {
        const span = try self.reserveSpan(1);
        self.pool.items[span.start] = id;
        return span;
    }

    // ═══════════════════════════════════════════════════════════════
    // Lowering mécanique : frontend → 6 primitives
    // ═══════════════════════════════════════════════════════════════

    pub fn lower(self: *Store, id: Id) LowerError!Id {
        const node = self.get(id);
        if (node.tag.isPrimitive()) return id;

        return switch (node.tag) {
            .true => self.makeLit(.{ .boolean = true }),
            .false => self.makeLit(.{ .boolean = false }),
            .int => self.makeLit(self.lits.items[node.aux]),
            .float => self.makeLit(self.lits.items[node.aux]),
            .string => self.makeLit(self.lits.items[node.aux]),
            .unit_lit => self.makeLit(.unit),
            .fun => self.makeNode(.lambda, node.payload, node.aux, node.span_a, node.span_b),
            .let => self.makeNode(.bind, node.payload, node.aux, node.span_a, node.span_b),
            .eq => self.makeNode(.relation, node.payload, node.aux, node.span_a, node.span_b),
            .add, .sub, .mul, .div, .mod, .and_tag, .or_tag, .cons => blk: {
                const sym_str = switch (node.tag) {
                    .add => "+",
                    .sub => "-",
                    .mul => "*",
                    .div => "/",
                    .mod => "%",
                    .and_tag => "&",
                    .or_tag => "|",
                    .cons => "::",
                    else => unreachable,
                };
                const sym_id = try self.interner.intern(sym_str);
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },
            .not, .head, .tail => blk: {
                const sym_str = switch (node.tag) {
                    .not => "!",
                    .head => "head",
                    .tail => "tail",
                    else => unreachable,
                };
                const sym_id = try self.interner.intern(sym_str);
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },
            .tuple => blk: {
                const sym_id = try self.interner.intern("tuple");
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },
            .block, .seq => blk: {
                const sym_id = try self.interner.intern(if (node.tag == .block) "block" else "seq");
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },
            .var_tag => self.makeNode(.sym, node.payload, 0, Span.EMPTY, Span.EMPTY),
            .hole => id,
            .evar => id, // idempotent : déjà primitif interne
            // --- LOWERING VECTORIEL / LISTES ---

            // 1. Vecteur n-aire : [x1, x2, ...] -> apply(sym("vector"), x1, x2, ...)
            .vector => blk: {
                const sym_id = try self.interner.intern("vector");
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },

            // 2. Chapelet structurel : [x, y] -> apply(Cons, x, apply(Cons, y, Nil))
            .vector_lit => blk: {
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src);
                defer self.allocator.free(args);

                const nil_sym = try self.interner.intern("Nil");
                const cons_sym_id = try self.interner.intern("Cons");

                var current = try self.makeNode(.sym, nil_sym, 0, Span.EMPTY, Span.EMPTY);
                const cons_node = try self.makeNode(.sym, cons_sym_id, 0, Span.EMPTY, Span.EMPTY);

                var i: usize = args.len;
                while (i > 0) {
                    i -= 1;
                    const elem = try self.lower(args[i]); // args est notre copie → stable

                    const new_span = try self.reserveSpan(3);
                    self.pool.items[new_span.start] = cons_node;
                    self.pool.items[new_span.start + 1] = elem;
                    self.pool.items[new_span.start + 2] = current;

                    current = try self.makeNode(.apply, cons_node, 0, new_span, Span.EMPTY);
                }
                break :blk current;
            },

            // --- LOWERING DES AGRÉGATS MATHÉMATIQUES (Σ / Aggregate) ---

            .sum, .aggregate => blk: {
                // Traduction de Aggregate(op, init, vec) -> apply(sym("foldl"), op, init, vec)
                const sym_id = try self.interner.intern("foldl");
                const sym_node = try self.makeNode(.sym, sym_id, 0, Span.EMPTY, Span.EMPTY);
                const args_src = self.spanSliceConst(node.span_a);
                const args = try self.copyPoolSlice(args_src); // ← snapshot AVANT reserveSpan
                defer self.allocator.free(args);
                const new_span = try self.reserveSpan(1 + args.len);
                self.pool.items[new_span.start] = sym_node;
                @memcpy(self.pool.items[new_span.start + 1 .. new_span.start + 1 + args.len], args);
                break :blk self.makeNode(.apply, sym_node, 0, new_span, Span.EMPTY);
            },
            else => error.ExtensionNotLowered,
        };
    }

    fn makeLit(self: *Store, l: Lit) !Id {
        const aux = try self.addLit(l);
        return self.addNode(.{ .tag = .lit, .payload = 0, .aux = aux, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
    }

    fn makeNode(self: *Store, tag: Tag, payload: u32, aux: u32, span_a: Span, span_b: Span) !Id {
        return self.addNode(.{ .tag = tag, .payload = payload, .aux = aux, .span_a = span_a, .span_b = span_b });
    }

    pub fn lowerRec(self: *Store, id: Id) LowerError!Id {
        const node = self.get(id);
        //platform.dbg("[lowerRec] id={d} tag={s}\n", .{ id, @tagName(node.tag) });

        if (node.tag.isPrimitive()) {
            var new_span_a = node.span_a;
            var new_span_b = node.span_b;
            var changed = false;

            if (node.span_a.len > 0) {
                // 1. Snapshot AVANT tout appel récursif
                const old_snap = try self.copyPoolSlice(self.spanSliceConst(node.span_a));
                defer self.allocator.free(old_snap);

                // 2. Un seul passage : lower chaque enfant une fois
                const new_args = try self.allocator.alloc(Id, old_snap.len);
                defer self.allocator.free(new_args);

                var any_changed = false;
                for (old_snap, 0..) |child, i| {
                    new_args[i] = try self.lowerRec(child);
                    if (new_args[i] != child) any_changed = true;
                }
                if (any_changed) {
                    new_span_a = try self.pushSpan(new_args); // pushSpan est déjà safe
                    changed = true;
                }
            }

            if (node.span_b.len > 0) {
                const old_snap = try self.copyPoolSlice(self.spanSliceConst(node.span_b));
                defer self.allocator.free(old_snap);

                const new_args = try self.allocator.alloc(Id, old_snap.len);
                defer self.allocator.free(new_args);

                var any_changed = false;
                for (old_snap, 0..) |child, i| {
                    new_args[i] = try self.lowerRec(child);
                    if (new_args[i] != child) any_changed = true;
                }
                if (any_changed) {
                    new_span_b = try self.pushSpan(new_args);
                    changed = true;
                }
            }

            if (!changed) return id;
            return self.addNode(.{
                .tag = node.tag,
                .payload = node.payload,
                .aux = node.aux,
                .span_a = new_span_a,
                .span_b = new_span_b,
            });
        }

        var lowered_children: std.ArrayListUnmanaged(Id) = .{};
        defer lowered_children.deinit(self.allocator);

        if (node.span_a.len > 0) {
            // Snapshot AVANT tout lowerRec (qui peut reserveSpan)
            const old_snap = try self.copyPoolSlice(self.spanSliceConst(node.span_a));
            defer self.allocator.free(old_snap);

            try lowered_children.ensureTotalCapacity(self.allocator, old_snap.len);
            for (old_snap) |child| {
                try lowered_children.append(self.allocator, try self.lowerRec(child));
            }
        }

        const new_span_a = if (lowered_children.items.len > 0) blk: {
            // pushSpan est safe (snapshot interne)
            break :blk try self.pushSpan(lowered_children.items);
        } else Span.EMPTY;

        const temp_id = try self.addNode(.{
            .tag = node.tag,
            .payload = node.payload,
            .aux = node.aux,
            .span_a = new_span_a,
            .span_b = node.span_b,
        });

        return self.lower(temp_id);
    }

    // ═══════════════════════════════════════════════════════════════
    // Sérialisation (compatibilité)
    // ═══════════════════════════════════════════════════════════════

    pub fn toString(self: *const Store, id: Id, allocator: Allocator) Allocator.Error![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(allocator);
        try self.serialize(id, &buf, allocator);
        return buf.toOwnedSlice(allocator);
    }

    pub fn toStringInfix(self: *const Store, id: Id, allocator: Allocator) Allocator.Error![]u8 {
        return self.toString(id, allocator);
    }

    fn serialize(self: *const Store, id: Id, buf: *std.ArrayList(u8), allocator: Allocator) Allocator.Error!void {
        const node = self.get(id);
        switch (node.tag) {
            .lit => {
                const l = self.lits.items[node.aux];
                switch (l) {
                    .int => |v| buf.writer(allocator).print("{d}", .{v}) catch return error.OutOfMemory,
                    .float => |v| buf.writer(allocator).print("{d}", .{v}) catch return error.OutOfMemory,
                    .boolean => |v| buf.appendSlice(allocator, if (v) "true" else "false") catch return error.OutOfMemory,
                    .str => |v| {
                        buf.append(allocator, '"') catch return error.OutOfMemory;
                        buf.appendSlice(allocator, self.interner.resolve(v)) catch return error.OutOfMemory;
                        buf.append(allocator, '"') catch return error.OutOfMemory;
                    },
                    .unit => buf.appendSlice(allocator, "()") catch return error.OutOfMemory,
                    .runtime => buf.appendSlice(allocator, "<runtime>") catch return error.OutOfMemory,
                }
            },
            .sym => {
                buf.appendSlice(allocator, self.interner.resolve(node.payload)) catch return error.OutOfMemory;
            },
            .apply => {
                const args = node.span_a.slice(self.pool.items);
                // Détecter quote/unquote pour affichage lossless
                if (args.len >= 2) {
                    const head_node = self.get(args[0]);
                    if (head_node.tag == .sym) {
                        const head_name = self.interner.resolve(head_node.payload);
                        if (std.mem.eql(u8, head_name, "quote")) {
                            buf.appendSlice(allocator, "(quote ") catch return error.OutOfMemory;
                            try self.serialize(args[1], buf, allocator);
                            buf.append(allocator, ')') catch return error.OutOfMemory;
                            return;
                        }
                        if (std.mem.eql(u8, head_name, "unquote")) {
                            buf.appendSlice(allocator, "(unquote ") catch return error.OutOfMemory;
                            try self.serialize(args[1], buf, allocator);
                            buf.append(allocator, ')') catch return error.OutOfMemory;
                            return;
                        }
                    }
                }
                buf.append(allocator, '(') catch return error.OutOfMemory;
                for (args, 0..) |arg, i| {
                    if (i > 0) buf.append(allocator, ' ') catch return error.OutOfMemory;
                    try self.serialize(arg, buf, allocator);
                }
                buf.append(allocator, ')') catch return error.OutOfMemory;
            },
            .bind => {
                // Le test attend : "x := 42"
                buf.appendSlice(allocator, self.interner.resolve(node.payload)) catch return error.OutOfMemory;
                buf.appendSlice(allocator, " := ") catch return error.OutOfMemory;
                const args = node.span_a.slice(self.pool.items);
                if (args.len > 0) {
                    try self.serialize(args[0], buf, allocator);
                }
            },
            .lambda => {
                buf.appendSlice(allocator, "(lambda ") catch return error.OutOfMemory;
                buf.appendSlice(allocator, self.interner.resolve(node.payload)) catch return error.OutOfMemory;
                buf.append(allocator, ' ') catch return error.OutOfMemory;
                const args = node.span_a.slice(self.pool.items);
                for (args, 0..) |arg, i| {
                    if (i > 0) buf.append(allocator, ' ') catch return error.OutOfMemory;
                    try self.serialize(arg, buf, allocator);
                }
                buf.append(allocator, ')') catch return error.OutOfMemory;
            },
            .relation => {
                buf.append(allocator, '(') catch return error.OutOfMemory;
                buf.appendSlice(allocator, self.interner.resolve(node.payload)) catch return error.OutOfMemory;
                const args = node.span_a.slice(self.pool.items);
                for (args) |arg| {
                    buf.append(allocator, ' ') catch return error.OutOfMemory;
                    try self.serialize(arg, buf, allocator);
                }
                buf.append(allocator, ')') catch return error.OutOfMemory;
            },
            // Legacy tags (au cas où le lowering n'est pas encore appelé)
            .int => buf.writer(allocator).print("{d}", .{self.lits.items[node.aux].int}) catch return error.OutOfMemory,
            .float => buf.writer(allocator).print("{d}", .{self.lits.items[node.aux].float}) catch return error.OutOfMemory,
            .true => buf.appendSlice(allocator, "true") catch return error.OutOfMemory,
            .false => buf.appendSlice(allocator, "false") catch return error.OutOfMemory,
            .unit_lit => buf.appendSlice(allocator, "()") catch return error.OutOfMemory,
            else => buf.appendSlice(allocator, "<?>") catch return error.OutOfMemory,
        }
    }

    pub fn pi(self: *Store, param_name: []const u8, domain: Id, codomain: Id) !Id {
        const param_sym = try self.sym(param_name);
        return self.addNode(.{
            .tag = .bind,
            .payload = param_sym,
            .aux = codomain,
            .span_a = try self.pushSpan(&.{domain}),
            .span_b = .{ .start = 0, .len = 0 },
        });
    }

    pub fn handle(self: *Store, body: Id, handler: Id) !Id {
        const h = try self.sym("handle");
        return self.apply(h, &.{ body, handler });
    }
    pub fn quote(self: *Store, inner: Id) !Id {
        const q = try self.sym("quote");
        return self.apply(q, &.{inner});
    }
    pub fn unquote(self: *Store, inner: Id) !Id {
        const u = try self.sym("unquote");
        return self.apply(u, &.{inner});
    }
    pub fn perform(self: *Store, name: []const u8, args: []const Id) !Id {
        const p = try self.sym("perform");
        var all: std.ArrayListUnmanaged(Id) = .{};
        defer all.deinit(self.allocator);
        try all.append(self.allocator, try self.sym(name));
        for (args) |a| try all.append(self.allocator, a);
        return self.apply(p, all.items);
    }
    /// Variante de `bind` prenant un `Sym` déjà interné.
    /// Produit un nœud `.bind` avec `span_a = [val, unit]`.
    pub fn bindSym(self: *Store, sym_id: Sym, val: Id) !Id {
        const span = try self.reserveSpan(2);
        self.pool.items[span.start] = val;
        self.pool.items[span.start + 1] = try self.unitLit();
        return self.addNode(.{
            .tag = .bind,
            .payload = sym_id,
            .aux = 0,
            .span_a = span,
            .span_b = Span.EMPTY,
        });
    }

    /// Variante de `letIn` prenant un `Sym` déjà interné.
    /// Produit un nœud `.bind` avec `span_a = [val, body]`.
    pub fn bindSymWithBody(self: *Store, sym_id: Sym, val: Id, body: Id) !Id {
        const span = try self.reserveSpan(2);
        self.pool.items[span.start] = val;
        self.pool.items[span.start + 1] = body;
        return self.addNode(.{
            .tag = .bind,
            .payload = sym_id,
            .aux = 0,
            .span_a = span,
            .span_b = Span.EMPTY,
        });
    }
    pub fn letIn(self: *Store, name: []const u8, rhs: Id, body: Id) !Id {
        const name_sym = try self.interner.intern(name);
        // Snapshot rhs et body AVANT reserveSpan (qui peut réallouer pool)
        const saved_rhs = rhs;
        const saved_body = body;
        const span = try self.reserveSpan(2);
        self.pool.items[span.start] = saved_rhs;
        self.pool.items[span.start + 1] = saved_body;
        return self.addNode(.{
            .tag = .let,
            .payload = name_sym,
            .aux = 0,
            .span_a = span,
            .span_b = Span.EMPTY,
        });
    }
};

// ═══════════════════════════════════════════════════
// Utilitaires Unicode : exposants ⁿ → ^n
// ═══════════════════════════════════════════════════

pub const SuperResult = struct {
    is_minus: bool,
    digit: u8, // valide si !is_minus
    next_pos: usize,
};

/// Détecte un caractère exposant Unicode à la position i.
/// Supporte : ⁰¹²³⁴⁵⁶⁷⁸⁹ et ⁻ (moins).
pub fn superCharAt(s: []const u8, i: usize) ?SuperResult {
    // Séquences 2 bytes (Latin-1) : ¹ = C2 B9, ² = C2 B2, ³ = C2 B3
    if (i + 1 < s.len and s[i] == 0xc2) {
        const d: ?u8 = switch (s[i + 1]) {
            0xb2 => '2',
            0xb3 => '3',
            0xb9 => '1',
            else => null,
        };
        if (d) |digit| return .{ .is_minus = false, .digit = digit, .next_pos = i + 2 };
    }
    // Séquences 3 bytes (U+2070-207F) : ⁰, ⁴-⁹, ⁻
    if (i + 2 < s.len and s[i] == 0xe2 and s[i + 1] == 0x81) {
        if (s[i + 2] == 0xbb) return .{ .is_minus = true, .digit = 0, .next_pos = i + 3 };
        const d: ?u8 = switch (s[i + 2]) {
            0xb0 => '0',
            0xb4 => '4',
            0xb5 => '5',
            0xb6 => '6',
            0xb7 => '7',
            0xb8 => '8',
            0xb9 => '9',
            else => null,
        };
        if (d) |digit| return .{ .is_minus = false, .digit = digit, .next_pos = i + 3 };
    }
    return null;
}

pub fn containsSuperscript(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) {
        if (superCharAt(s, i) != null) return true;
        i += 1;
    }
    return false;
}

/// Convertit les exposants Unicode en notation caret :
///   x² → x^2, x¹⁰ → x^10, x²³ → x^23, x⁻³ → x^-3
pub fn normalizeUnicodePowers(input: []const u8, allocator: Allocator) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (superCharAt(input, i)) |first| {
            // Collecter tous les superscripts consécutifs
            var digits_buf: [24]u8 = undefined;
            var digits_len: usize = 0;
            var has_minus = false;
            var pos = i;

            if (first.is_minus) {
                has_minus = true;
                pos = first.next_pos;
            } else {
                digits_buf[digits_len] = first.digit;
                digits_len += 1;
                pos = first.next_pos;
            }
            while (superCharAt(input, pos)) |r| {
                if (r.is_minus) break; // un seul moins
                if (digits_len < digits_buf.len) {
                    digits_buf[digits_len] = r.digit;
                    digits_len += 1;
                }
                pos = r.next_pos;
            }

            if (digits_len > 0) {
                try buf.append(allocator, '^');
                if (has_minus) try buf.append(allocator, '-');
                try buf.appendSlice(allocator, digits_buf[0..digits_len]);
            } else if (has_minus) {
                try buf.append(allocator, '-');
            }
            i = pos;
        } else {
            try buf.append(allocator, input[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(allocator);
}

// ═══════════════════════════════════════════════════
// SYNTAXE NATIVE → S-EXPRESSION
// "2 + 3 * x^2" → "(+ 2 (* 3 (^ x 2)))"
// Appeler normalizeUnicodePowers AVANT si nécessaire.
// ═══════════════════════════════════════════════════

pub const NativeError = error{ InvalidSyntax, OutOfMemory };

const TokKind = enum { num, ident, str, op, lparen, rparen, comma, eof };
const Tok = struct { kind: TokKind, text: []const u8 };

const Lexer = struct {
    src: []const u8,
    pos: usize = 0,

    fn next(self: *Lexer) NativeError!Tok {
        while (self.pos < self.src.len and std.ascii.isWhitespace(self.src[self.pos])) self.pos += 1;
        if (self.pos >= self.src.len) return .{ .kind = .eof, .text = "" };
        const c = self.src[self.pos];

        if (std.ascii.isDigit(c)) {
            const start = self.pos;
            while (self.pos < self.src.len and (std.ascii.isDigit(self.src[self.pos]) or self.src[self.pos] == '.'))
                self.pos += 1;
            return .{ .kind = .num, .text = self.src[start..self.pos] };
        }

        if (std.ascii.isAlphabetic(c) or c == '_' or c == '?') {
            const start = self.pos;
            while (self.pos < self.src.len and (std.ascii.isAlphanumeric(self.src[self.pos]) or self.src[self.pos] == '_' or self.src[self.pos] == '?'))
                self.pos += 1;
            return .{ .kind = .ident, .text = self.src[start..self.pos] };
        }

        if (c == '"') {
            const start = self.pos;
            self.pos += 1;
            while (self.pos < self.src.len and self.src[self.pos] != '"') self.pos += 1;
            if (self.pos >= self.src.len) return error.InvalidSyntax;
            self.pos += 1;
            return .{ .kind = .str, .text = self.src[start..self.pos] };
        }
        if (c == '(') {
            self.pos += 1;
            return .{ .kind = .lparen, .text = "(" };
        }
        if (c == ')') {
            self.pos += 1;
            return .{ .kind = .rparen, .text = ")" };
        }
        if (c == ',') {
            self.pos += 1;
            return .{ .kind = .comma, .text = "," };
        }

        // Opérateurs 3 chars
        if (self.pos + 2 < self.src.len) {
            const three = self.src[self.pos .. self.pos + 3];
            if (std.mem.eql(u8, three, ">>>")) {
                self.pos += 3;
                return .{ .kind = .op, .text = three };
            }
        }

        // Opérateurs 2 chars
        if (self.pos + 1 < self.src.len) {
            const two = self.src[self.pos .. self.pos + 2];
            const two_ops = [_][]const u8{ "==", "!=", "<=", ">=", "&&", "||" };
            for (two_ops) |o| {
                if (std.mem.eql(u8, two, o)) {
                    self.pos += 2;
                    return .{ .kind = .op, .text = two };
                }
            }
        }
        // Opérateurs 1 char
        const one_ops = "+-*/%^<>!";
        if (std.mem.indexOfScalar(u8, one_ops, c) != null) {
            const t = self.src[self.pos .. self.pos + 1];
            self.pos += 1;
            return .{ .kind = .op, .text = t };
        }
        return error.InvalidSyntax;
    }

    fn peek(self: *Lexer) NativeError!Tok {
        const saved = self.pos;
        defer self.pos = saved;
        return self.next();
    }
};

const NativeParser = struct {
    lex: *Lexer,
    allocator: Allocator,

    fn eq(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    fn prec(op: []const u8) u8 {
        if (eq(op, ">>>")) return 0xFE;
        if (eq(op, "||") or eq(op, "or")) return 1;
        if (eq(op, "&&") or eq(op, "and")) return 2;
        if (eq(op, "==") or eq(op, "!=")) return 3;
        if (eq(op, "<") or eq(op, ">") or eq(op, "<=") or eq(op, ">=")) return 4;
        if (eq(op, "+") or eq(op, "-")) return 5;
        if (eq(op, "*") or eq(op, "/") or eq(op, "%")) return 6;
        if (eq(op, "^")) return 8;
        return 0;
    }

    /// Pratt parser : précédence minimale min_prec.
    fn parseExpr(self: *NativeParser, min_prec: u8) NativeError![]u8 {
        var lhs = try self.parseUnary();
        while (true) {
            const t = try self.lex.peek();
            var op_text: []const u8 = undefined;
            var p: u8 = 0;
            switch (t.kind) {
                .op => {
                    op_text = t.text;
                    p = prec(t.text);
                    if (p == 0 or p < min_prec) break;
                },
                .ident => {
                    if (eq(t.text, "and")) {
                        op_text = "&&";
                        p = 2;
                    } else if (eq(t.text, "or")) {
                        op_text = "||";
                        p = 1;
                    } else break;
                    if (p < min_prec) break;
                },
                else => break,
            }
            _ = try self.lex.next(); // consommer l'opérateur
            // ^ right-assoc : min = p ; les autres : min = p+1
            const next_min: u8 = if (eq(op_text, "^")) p else p + 1;
            const rhs = try self.parseExpr(next_min);
            const sym = if (eq(op_text, "&&")) "and" else if (eq(op_text, "||")) "or" else op_text;
            lhs = try std.fmt.allocPrint(self.allocator, "({s} {s} {s})", .{ sym, lhs, rhs });
        }
        return lhs;
    }

    fn parseUnary(self: *NativeParser) NativeError![]u8 {
        const t = try self.lex.peek();
        if (t.kind == .op and eq(t.text, "-")) {
            _ = try self.lex.next();
            // Nombre négatif direct : -5
            const nxt = try self.lex.peek();
            if (nxt.kind == .num) {
                _ = try self.lex.next();
                return std.fmt.allocPrint(self.allocator, "-{s}", .{nxt.text});
            }
            const operand = try self.parseUnary();
            return std.fmt.allocPrint(self.allocator, "(- 0 {s})", .{operand});
        }
        if ((t.kind == .op and eq(t.text, "!")) or (t.kind == .ident and eq(t.text, "not"))) {
            _ = try self.lex.next();
            const operand = try self.parseUnary();
            return std.fmt.allocPrint(self.allocator, "(! {s})", .{operand});
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *NativeParser) NativeError![]u8 {
        const base = try self.parsePrimary();

        // Collecte les arguments en position juxtaposée ou parenthésée.
        // f(a, b) c d → (f a b c d)
        var args: std.ArrayListUnmanaged([]const u8) = .{};
        defer {
            for (args.items) |a| self.allocator.free(a);
            args.deinit(self.allocator);
        }

        while (true) {
            const t = try self.lex.peek();
            if (t.kind == .lparen) {
                _ = try self.lex.next(); // (
                const first = try self.lex.peek();
                if (first.kind == .rparen) {
                    _ = try self.lex.next();
                    continue;
                }
                while (true) {
                    const arg = try self.parseExpr(0);
                    try args.append(self.allocator, arg);
                    const sep = try self.lex.next();
                    if (sep.kind == .comma) continue;
                    if (sep.kind == .rparen) break;
                    return error.InvalidSyntax;
                }
            } else if (t.kind == .ident or t.kind == .num) {
                const arg = try self.parsePrimary();
                try args.append(self.allocator, arg);
            } else {
                break;
            }
        }

        if (args.items.len == 0) return base;

        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        try buf.append(self.allocator, '(');
        try buf.appendSlice(self.allocator, base);
        for (args.items) |a| {
            try buf.append(self.allocator, ' ');
            try buf.appendSlice(self.allocator, a);
        }
        try buf.append(self.allocator, ')');
        return try buf.toOwnedSlice(self.allocator);
    }

    fn parsePrimary(self: *NativeParser) NativeError![]u8 {
        const t = try self.lex.next();
        switch (t.kind) {
            .num, .ident, .str => return self.allocator.dupe(u8, t.text),
            .lparen => {
                const inner = try self.parseExpr(0);
                const close = try self.lex.next();
                if (close.kind != .rparen) return error.InvalidSyntax;
                return inner;
            },
            else => return error.InvalidSyntax,
        }
    }
};

/// Convertit la syntaxe native en S-expression (chaîne).
pub fn nativeToSExpr(input: []const u8, allocator: std.mem.Allocator) NativeError![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer{ .src = input };
    var p = NativeParser{ .lex = &lex, .allocator = a };

    const result = try p.parseExpr(0);
    const t = try lex.next();
    if (t.kind != .eof) return error.InvalidSyntax; // tokens en trop
    return allocator.dupe(u8, result); // copie hors de l'arène
}

/// Compte les occurrences d'un symbole `name` dans l'arbre d'AST `id`.
/// Gère le shadowing : un `lambda` ou un `bind` qui rebinde `name`
/// masque les occurrences dans son corps.
pub fn countSymUses(store: *const Store, id: Id, name: []const u8) usize {
    const node = store.get(id);
    switch (node.tag) {
        .sym => {
            const n = store.interner.resolve(node.payload);
            return if (std.mem.eql(u8, n, name)) 1 else 0;
        },
        .lit => return 0,
        .apply => {
            var total = countSymUses(store, node.payload, name);
            for (store.spanSliceConst(node.span_a)) |child| {
                total += countSymUses(store, child, name);
            }
            return total;
        },
        .lambda => {
            // Un paramètre de lambda masque le nom extérieur — comportement
            // correct pour le shadowing.
            const bound = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, bound, name)) return 0;
            var total: usize = 0;
            for (store.spanSliceConst(node.span_a)) |child| {
                total += countSymUses(store, child, name);
            }
            return total;
        },
        .bind => {
            // Si le nom du binding est celui qu'on cherche, tout ce qui suit
            // est masqué : aucune occurrence de `name` dans le corps n'est
            // une occurrence de la variable externe.
            const bound = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, bound, name)) return 0;

            var total: usize = 0;
            for (store.spanSliceConst(node.span_a)) |child| {
                total += countSymUses(store, child, name);
            }
            return total;
        },
        .relation => {
            var total: usize = 0;
            for (store.spanSliceConst(node.span_a)) |child| total += countSymUses(store, child, name);
            for (store.spanSliceConst(node.span_b)) |child| total += countSymUses(store, child, name);
            return total;
        },
        else => return 0,
    }
}

test "core invariant — lowered expression contains only six primitives" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);

    const expr = try store.binop("+", x, zero);

    const lowered = try store.lowerRec(expr);

    try store.assertCoreExpr(lowered);

    try std.testing.expect(
        store.get(lowered).tag.isPrimitive(),
    );
}

test "core structural hash distinguishes bind names" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const one = try store.int(1);

    const a = try store.bind("x", one);
    const b = try store.bind("y", one);

    try std.testing.expect(!structuralEql(&store, a, b));
    try std.testing.expect(nodeHash(&store, a) != nodeHash(&store, b));
}

test "core structural hash distinguishes lambda parameters" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const body = try store.int(1);

    const a = try store.lambda(&.{"x"}, body);
    const b = try store.lambda(&.{"y"}, body);

    try std.testing.expect(!structuralEql(&store, a, b));
    try std.testing.expect(nodeHash(&store, a) != nodeHash(&store, b));
}

test "core structural equality includes relation rhs" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const lhs = try store.int(1);
    const rhs_a = try store.int(2);
    const rhs_b = try store.int(3);

    const a = try store.relation(
        "R",
        &.{lhs},
        &.{rhs_a},
    );

    const b = try store.relation(
        "R",
        &.{lhs},
        &.{rhs_b},
    );

    try std.testing.expect(!structuralEql(&store, a, b));
}

test "core structural equality includes relation head" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const lhs = try store.int(1);
    const rhs = try store.int(2);

    const a = try store.relation(
        "R",
        &.{lhs},
        &.{rhs},
    );

    const b = try store.relation(
        "S",
        &.{lhs},
        &.{rhs},
    );

    try std.testing.expect(!structuralEql(&store, a, b));
}

test "core structural equality ignores source spans" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const one = try store.int(1);

    const a = try store.sym("x");
    const b = try store.sym("x");

    // Different NodeIds but identical semantic symbols.
    try std.testing.expect(a != b);
    try std.testing.expect(structuralEql(&store, a, b));
    try std.testing.expectEqual(
        nodeHash(&store, a),
        nodeHash(&store, b),
    );

    _ = one;
}

test "core structural equality is recursive for apply" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const f1 = try store.sym("f");
    const f2 = try store.sym("f");

    const x1 = try store.int(1);
    const x2 = try store.int(1);

    const a = try store.apply(f1, &.{x1});
    const b = try store.apply(f2, &.{x2});

    try std.testing.expect(structuralEql(&store, a, b));
    try std.testing.expectEqual(
        nodeHash(&store, a),
        nodeHash(&store, b),
    );
}

test "core expressions satisfy structural hash/equality contract" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const one = try store.int(1);
    const two = try store.int(2);
    const f = try store.sym("f");

    const expressions = [_]Id{
        one,
        two,
        f,
        try store.apply(f, &.{one}),
        try store.bind("x", one),
        try store.lambda(&.{"x"}, one),
        try store.relation("R", &.{one}, &.{two}),
    };

    for (expressions) |a| {
        try std.testing.expect(store.isCore(a));

        for (expressions) |b| {
            if (structuralEql(&store, a, b)) {
                try std.testing.expectEqual(
                    nodeHash(&store, a),
                    nodeHash(&store, b),
                );
            }
        }
    }
}

test "lowering is idempotent" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const one = try store.int(1);
    const two = try store.int(2);

    const expr = try store.binop("+", one, two);

    const lowered = try store.lowerRec(expr);
    const lowered_again = try store.lowerRec(lowered);

    try std.testing.expectEqual(lowered, lowered_again);
    try store.assertCoreExpr(lowered);
    try store.assertCoreExpr(lowered_again);
}

test "lowering preserves Core expressions" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    const one = try store.int(1);

    const f = try store.sym("f");
    const application = try store.apply(f, &.{one});

    const lowered = try store.lowerRec(application);

    try std.testing.expectEqual(application, lowered);
    try store.assertCoreExpr(lowered);
}

test "bindSym produces a valid bind node" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const s = try store.interner.intern("x");
    const val = try store.int(42);
    const node_id = try store.bindSym(s, val);

    const node = store.get(node_id);
    try std.testing.expectEqual(Tag.bind, node.tag);
    try std.testing.expectEqual(s, node.payload);

    const args = node.span_a.slice(store.pool.items);
    try std.testing.expectEqual(@as(usize, 2), args.len);
    try std.testing.expectEqual(val, args[0]);

    const body_node = store.get(args[1]);
    try std.testing.expectEqual(Tag.lit, body_node.tag);
    try std.testing.expect(store.lits.items[body_node.aux] == .unit);
}

test "bindSymWithBody stores both val and body" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const s = try store.interner.intern("x");
    const val = try store.int(1);
    const body = try store.int(2);
    const node_id = try store.bindSymWithBody(s, val, body);

    const node = store.get(node_id);
    try std.testing.expectEqual(Tag.bind, node.tag);
    try std.testing.expectEqual(s, node.payload);

    const args = node.span_a.slice(store.pool.items);
    try std.testing.expectEqual(@as(usize, 2), args.len);
    try std.testing.expectEqual(val, args[0]);
    try std.testing.expectEqual(body, args[1]);
}

test "countSymUses — bind masque le nom du binding" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.interner.intern("x");
    const y = try store.interner.intern("y");

    // body = (+ (+ y y) x)
    const y1 = try store.symId(y);
    const y2 = try store.symId(y);
    const inner_x = try store.symId(x);
    const body = try store.binop("+", try store.binop("+", y1, y2), inner_x);

    const b = try store.bindSymWithBody(x, try store.int(5), body);

    // "x" est masqué par le bind → 0 occurrence visible
    try std.testing.expectEqual(@as(usize, 0), countSymUses(&store, b, "x"));
    // "y" n'est pas masqué → 2 occurrences
    try std.testing.expectEqual(@as(usize, 2), countSymUses(&store, b, "y"));
}

test "countSymUses — shadowing via bind" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.interner.intern("x");
    const one = try store.int(1);
    const body_inner = try store.symId(x); // sym("x") référence le x interne
    const inner = try store.bindSymWithBody(x, try store.int(2), body_inner);
    const outer = try store.bindSymWithBody(x, one, inner);

    // On cherche "x" à l'extérieur : le nom est masqué par le bind extérieur,
    // donc 0 occurrence visible.
    try std.testing.expectEqual(@as(usize, 0), countSymUses(&store, outer, "x"));
}

test "countSymUses — bind n'affecte pas les autres noms" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const x = try store.interner.intern("x");
    const y = try store.interner.intern("y");

    // bind("x", [y, (+ y y)]) → deux occurrences de "y"
    const y1 = try store.symId(y);
    const y2 = try store.symId(y);
    const body = try store.binop("+", y1, y2);
    const b = try store.bindSymWithBody(x, try store.int(0), body);

    try std.testing.expectEqual(@as(usize, 2), countSymUses(&store, b, "y"));
    try std.testing.expectEqual(@as(usize, 0), countSymUses(&store, b, "x"));
}

test "evar — mkEvar crée des payloads uniques" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const e0 = try store.mkEvar();
    const e1 = try store.mkEvar();
    try std.testing.expect(e0 != e1);
    try std.testing.expect(store.isEvar(e0) != null);
    try std.testing.expect(store.isEvar(e1) != null);
    try std.testing.expectEqual(store.isEvar(e0).?, store.isEvar(e0).?);
    try std.testing.expect(store.isEvar(e0).? != store.isEvar(e1).?);
}

test "evar — structuralEql par identité" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const e0 = try store.mkEvar();
    const e1 = try store.mkEvar();

    // e0 == e0
    try std.testing.expect(structuralEql(&store, e0, e0));
    // e0 != e1 (identité, pas structure)
    try std.testing.expect(!structuralEql(&store, e0, e1));

    // evar != un symbole
    const s = try store.sym("x");
    try std.testing.expect(!structuralEql(&store, e0, s));
}

test "evar — isEvar rejette les non-evar" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();

    const s = try store.sym("x");
    try std.testing.expect(store.isEvar(s) == null);

    const i = try store.int(42);
    try std.testing.expect(store.isEvar(i) == null);
}
