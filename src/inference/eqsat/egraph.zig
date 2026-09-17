const std = @import("std");
const Allocator = std.mem.Allocator;
const canon_mod = @import("canon");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const platform = @import("platform");
const types = @import("types");

pub const ClassId = u32;

// === Étape 5 : Preuves ===
pub const ProofStep = struct {
    rule_id: Id, // 0 pour β-réduction, sinon ID de la relation
    lhs: Id,
    rhs: Id,
    timestamp: u64,
};

pub const QttCost = struct {
    quantities: std.AutoHashMapUnmanaged(Id, u2) = .{}, // 0=zero, 1=one, 2=many

    pub fn deinit(self: *QttCost, allocator: Allocator) void {
        self.quantities.deinit(allocator);
    }

    pub fn nodeCost(self: *QttCost, store: *const Store, id: Id) u32 {
        const node = store.get(id);
        return switch (node.tag) {
            .lit => 1,
            .sym => if (self.quantities.get(id)) |q| switch (q) {
                0 => 0,
                1 => 0,
                2 => 1,
                else => 1,
            } else 1,
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag == .sym) {
                    const op_name = store.interner.resolve(func_node.payload);
                    if (std.mem.eql(u8, op_name, "+") or std.mem.eql(u8, op_name, "*")) return 2;
                    if (std.mem.eql(u8, op_name, "^")) return 4;
                }
                return 1;
            },
            else => 1,
        };
    }

    pub fn total(self: *QttCost, store: *const Store, id: Id) u32 {
        var c: u32 = self.nodeCost(store, id);
        const node = store.get(id);
        switch (node.tag) {
            .apply => {
                c += self.total(store, node.payload);
                for (node.span_a.slice(store.pool.items)) |child| c += self.total(store, child);
            },
            .bind => {
                const args = node.span_a.slice(store.pool.items);
                for (args) |a| c += self.total(store, a);
            },
            else => {},
        }
        return c;
    }
};

pub const CostModel = struct {
    pub fn nodeCost(store: *const Store, id: Id) u32 {
        const node = store.get(id);
        return switch (node.tag) {
            .lit => 1,
            .sym => 0,
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag == .sym) {
                    const op_name = store.interner.resolve(func_node.payload);
                    if (std.mem.eql(u8, op_name, "+") or std.mem.eql(u8, op_name, "*")) {
                        return 2;
                    }
                    if (std.mem.eql(u8, op_name, "^")) {
                        return 4;
                    }
                }
                return 1;
            },
            else => 1,
        };
    }

    pub fn total(store: *const Store, id: Id) u32 {
        const node = store.get(id);
        var c: u32 = nodeCost(store, id);
        switch (node.tag) {
            .apply => {
                c += total(store, node.payload);
                for (node.span_a.slice(store.pool.items)) |child| {
                    c += total(store, child);
                }
            },
            .bind => c += total(store, node.aux),
            else => {},
        }
        return c;
    }
};

pub const UnionFind = struct {
    parent: std.ArrayListUnmanaged(ClassId) = .{},
    rank: std.ArrayListUnmanaged(u8) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) UnionFind {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *UnionFind) void {
        self.parent.deinit(self.allocator);
        self.rank.deinit(self.allocator);
    }

    pub fn makeSet(self: *UnionFind) !ClassId {
        const id: ClassId = @intCast(self.parent.items.len);
        try self.parent.append(self.allocator, id);
        try self.rank.append(self.allocator, 0);
        return id;
    }

    pub fn find(self: *UnionFind, x: ClassId) ClassId {
        var current = x;
        while (self.parent.items[current] != current) {
            self.parent.items[current] = self.parent.items[self.parent.items[current]];
            current = self.parent.items[current];
        }
        return current;
    }

    pub fn merge(self: *UnionFind, a: ClassId, b: ClassId) ClassId {
        const ra = self.find(a);
        const rb = self.find(b);
        if (ra == rb) return ra;
        if (self.rank.items[ra] < self.rank.items[rb]) {
            self.parent.items[ra] = rb;
            return rb;
        } else if (self.rank.items[ra] > self.rank.items[rb]) {
            self.parent.items[rb] = ra;
            return ra;
        } else {
            self.parent.items[rb] = ra;
            self.rank.items[ra] += 1;
            return ra;
        }
    }
};

pub const EClass = struct {
    nodes: std.ArrayListUnmanaged(Id) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) EClass {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EClass) void {
        self.nodes.deinit(self.allocator);
    }
};

// === Étape 6 : fonction de coût contextuelle ===
pub const CostFn = *const fn (store: *const Store, id: Id, context: ?*anyopaque) u32;

pub const MemoryCost = struct {
    type_env: *const types.TypeEnv,
    allocator: Allocator,
    cache: std.AutoHashMap(Id, types.Type),

    pub fn total(self: *MemoryCost, store: *const Store, id: Id) u32 {
        // Récupérer le type du nœud (via un cache ou inférence)
        const ty = self.cache.get(id) orelse return 1; // fallback
        return types.typeSize(self.allocator, store, ty);
    }
};

pub const EGraph = struct {
    store: *Store,
    allocator: Allocator,
    uf: UnionFind,
    classes: std.ArrayListUnmanaged(EClass) = .{},
    node_to_class: std.AutoHashMapUnmanaged(Id, ClassId) = .{},
    /// Hash-consing index.
    ///
    /// A hash maps to one or more candidate classes. The hash is only a
    /// prefilter. `expr.structuralEql()` is the final identity check.
    hashcons: std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(ClassId)) = .{},
    merge_count: u64 = 0,
    // Étape 5
    proofs: std.ArrayListUnmanaged(ProofStep) = .{},

    pub fn init(store: *Store, allocator: Allocator) EGraph {
        return .{
            .store = store,
            .allocator = allocator,
            .uf = UnionFind.init(allocator),
        };
    }

    pub fn deinit(self: *EGraph) void {
        for (self.classes.items) |*c| c.deinit();
        self.classes.deinit(self.allocator);
        self.uf.deinit();
        self.node_to_class.deinit(self.allocator);
        var hash_it = self.hashcons.valueIterator();
        while (hash_it.next()) |candidates| {
            candidates.deinit(self.allocator);
        }
        self.hashcons.deinit(self.allocator);
        self.proofs.deinit(self.allocator);
    }

    pub fn addProof(self: *EGraph, step: ProofStep) !void {
        try self.proofs.append(self.allocator, step);
    }

    pub fn add(self: *EGraph, id: Id) !ClassId {
        try self.store.assertCoreExpr(id);

        const canonical = try canon_mod.canonicalize(
            self.store,
            self.allocator,
            id,
        );

        if (self.node_to_class.get(canonical)) |class| {
            try self.node_to_class.put(
                self.allocator,
                id,
                class,
            );
            return self.uf.find(class);
        }

        const h = expr.nodeHash(self.store, canonical);

        if (self.hashcons.get(h)) |candidates| {
            for (candidates.items) |candidate| {
                const class = self.uf.find(candidate);

                for (self.classes.items[class].nodes.items) |existing_id| {
                    if (expr.structuralEql(
                        self.store,
                        existing_id,
                        canonical,
                    )) {
                        try self.node_to_class.put(
                            self.allocator,
                            id,
                            class,
                        );
                        try self.node_to_class.put(
                            self.allocator,
                            canonical,
                            class,
                        );
                        return class;
                    }
                }
            }
        }

        const class = try self.uf.makeSet();

        var eclass = EClass.init(self.allocator);
        try eclass.nodes.append(
            self.allocator,
            canonical,
        );

        try self.classes.append(
            self.allocator,
            eclass,
        );

        try self.node_to_class.put(
            self.allocator,
            canonical,
            class,
        );

        try self.node_to_class.put(
            self.allocator,
            id,
            class,
        );

        const gop = try self.hashcons.getOrPut(
            self.allocator,
            h,
        );

        if (!gop.found_existing) {
            gop.value_ptr.* = .{};
        }

        try gop.value_ptr.append(
            self.allocator,
            class,
        );

        return class;
    }

    pub fn addExpr(self: *EGraph, id: Id) !ClassId {
        if (id >= self.store.nodes.items.len) {
            platform.dbg(
                "[EGraph] INVALID ID={d} store.len={d}\n",
                .{ id, self.store.nodes.items.len },
            );
            return error.InvalidExpr;
        }
        const node = self.store.get(id);

        if (node.tag == .apply) {
            platform.dbg(
                "[EGraph] addExpr apply id={d} payload={d} span_a={d}..{d}\n",
                .{
                    id,
                    node.payload,
                    node.span_a.start,
                    node.span_a.start + node.span_a.len,
                },
            );
        }

        if (!node.tag.isPrimitive()) {
            platform.dbg(
                "[EGraph] extension non lowered: {s}\n",
                .{@tagName(node.tag)},
            );
            return error.ExtensionNotLowered;
        }

        switch (node.tag) {
            .sym, .lit, .hole => {},
            .apply => {
                platform.dbg("[EGraph] apply id={d} payload={d}\n", .{ id, node.payload });

                _ = try self.addExpr(node.payload);

                // Snapshot AVANT tout addExpr récursif
                const span_raw = self.store.spanSliceConst(node.span_a);
                const span = try self.store.allocator.dupe(expr.Id, span_raw);
                defer self.store.allocator.free(span);

                if (span.len > 1) {
                    for (span[1..]) |child| {
                        platform.dbg("[EGraph] apply arg={d}\n", .{child});
                        _ = try self.addExpr(child);
                    }
                }
            },
            .bind => {
                const span_a = try self.store.allocator.dupe(
                    expr.Id,
                    self.store.spanSliceConst(node.span_a),
                );
                defer self.store.allocator.free(span_a);

                const span_b = try self.store.allocator.dupe(
                    expr.Id,
                    self.store.spanSliceConst(node.span_b),
                );
                defer self.store.allocator.free(span_b);

                for (span_a) |child| {
                    _ = try self.addExpr(child);
                }

                for (span_b) |child| {
                    _ = try self.addExpr(child);
                }
            },
            .lambda => {
                const span_a = try self.store.allocator.dupe(
                    expr.Id,
                    self.store.spanSliceConst(node.span_a),
                );
                defer self.store.allocator.free(span_a);

                for (span_a) |child| {
                    _ = try self.addExpr(child);
                }

                const span_b = try self.store.allocator.dupe(
                    expr.Id,
                    self.store.spanSliceConst(node.span_b),
                );
                defer self.store.allocator.free(span_b);

                for (span_b) |child| {
                    _ = try self.addExpr(child);
                }
            },
            .relation => {
                // Snapshot les DEUX spans avant les addExpr récursifs
                const span_a = try self.store.allocator.dupe(expr.Id, self.store.spanSliceConst(node.span_a));
                defer self.store.allocator.free(span_a);
                const span_b = try self.store.allocator.dupe(expr.Id, self.store.spanSliceConst(node.span_b));
                defer self.store.allocator.free(span_b);

                for (span_a) |child| _ = try self.addExpr(child);
                for (span_b) |child| _ = try self.addExpr(child);
            },
            else => return 0,
        }
        return self.add(id);
    }

    pub fn merge(self: *EGraph, a: ClassId, b: ClassId) !ClassId {
        const ra = self.uf.find(a);
        const rb = self.uf.find(b);
        if (ra == rb) return ra;
        self.merge_count += 1;
        const new_rep = self.uf.merge(ra, rb);
        const old = if (new_rep == ra) rb else ra;

        if (old < self.classes.items.len) {
            const old_nodes = self.classes.items[old].nodes.items;
            for (old_nodes) |node_id| {
                try self.classes.items[new_rep].nodes.append(self.allocator, node_id);
                try self.node_to_class.put(self.allocator, node_id, new_rep);
            }
        }
        return new_rep;
    }

    pub fn find(self: *EGraph, id: Id) ?ClassId {
        if (self.node_to_class.get(id)) |class| return self.uf.find(class);
        return null;
    }

    pub fn areEqual(self: *EGraph, a: Id, b: Id) bool {
        const ca = self.find(a) orelse return false;
        const cb = self.find(b) orelse return false;
        return ca == cb;
    }

    pub fn extractWithCost(egraph: *EGraph, class: ClassId, qtt: *QttCost) ?Id {
        const canonical = egraph.uf.find(class);
        if (canonical >= egraph.classes.items.len) return null;
        const eclass = &egraph.classes.items[canonical];
        if (eclass.nodes.items.len == 0) return null;

        var best: Id = eclass.nodes.items[0];
        var best_cost = qtt.total(egraph.store, best);
        for (eclass.nodes.items[1..]) |node_id| {
            const c = qtt.total(egraph.store, node_id);
            if (c < best_cost) {
                best = node_id;
                best_cost = c;
            }
        }
        return best;
    }

    // === Étape 6 : Extraction avec contexte ===
    pub fn extractWithContext(
        egraph: *EGraph,
        class: ClassId,
        cost_fn: CostFn,
        context: ?*anyopaque,
    ) ?Id {
        const canonical = egraph.uf.find(class);
        if (canonical >= egraph.classes.items.len) return null;
        const eclass = &egraph.classes.items[canonical];
        if (eclass.nodes.items.len == 0) return null;

        var best: Id = eclass.nodes.items[0];
        var best_cost = cost_fn(egraph.store, best, context);
        for (eclass.nodes.items[1..]) |node_id| {
            const c = cost_fn(egraph.store, node_id, context);
            if (c < best_cost) {
                best = node_id;
                best_cost = c;
            }
        }
        return best;
    }

    fn isWellFormed(store: *const Store, id: Id) bool {
        if (id >= store.len()) return false;
        const node = store.get(id);
        switch (node.tag) {
            .lit, .sym => return true,
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag != .sym) return false;
                const args = node.span_a.slice(store.pool.items);
                for (args) |arg| {
                    if (!isWellFormed(store, arg)) return false;
                }
                return true;
            },
            // Ignorer les autres tags (lambda, bind, relation…) pour l'extraction arithmétique
            else => return false,
        }
    }

    pub fn extract(egraph: *EGraph, class: ClassId, qtt: ?*QttCost) ?Id {
        const canonical = egraph.uf.find(class);
        if (canonical >= egraph.classes.items.len) return null;
        const eclass = &egraph.classes.items[canonical];
        if (eclass.nodes.items.len == 0) return null;

        var best: ?Id = null;
        var best_cost: u32 = std.math.maxInt(u32);

        for (eclass.nodes.items) |node_id| {
            // Ignorer les nœuds mal formés
            if (!isWellFormed(egraph.store, node_id)) continue;

            const c = if (qtt) |q| q.total(egraph.store, node_id) else cost(egraph.store, node_id);
            if (c < best_cost or (c == best_cost and (best == null or node_id > best.?))) {
                best = node_id;
                best_cost = c;
            }
        }

        return best orelse eclass.nodes.items[0]; // fallback
    }

    pub fn classForHash(self: *EGraph, h: u64) ?ClassId {
        const candidates = self.hashcons.get(h) orelse return null;

        var found: ?ClassId = null;

        for (candidates.items) |class| {
            const canonical = self.uf.find(class);

            if (found) |existing| {
                if (existing != canonical) {
                    return null;
                }
            } else {
                found = canonical;
            }
        }

        return found;
    }
};

pub fn cost(store: *const Store, id: Id) u32 {
    const node = store.get(id);
    var c: u32 = switch (node.tag) {
        .lit => 1,
        .sym => 1,
        .apply => 3,
        .lambda => 2,
        .bind => 2,
        .relation => 2,
        else => 1,
    };
    switch (node.tag) {
        .apply => {
            const args = node.span_a.slice(store.pool.items);
            for (args) |a| c += cost(store, a);
        },
        .bind => {
            const args = node.span_a.slice(store.pool.items);
            for (args) |a| c += cost(store, a);
        },
        .lambda => {
            const args = node.span_a.slice(store.pool.items);
            for (args) |a| c += cost(store, a);
        },
        .relation => {
            const args = node.span_a.slice(store.pool.items);
            for (args) |a| c += cost(store, a);
        },
        else => {},
    }
    return c;
}

// ═══════════════════════════════════════════════════ // Tests // ═══════════════════════════════════════════════════

test "egraph — add and find" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const a = try store.int(1);
    const b = try store.int(2);
    const ca = try egraph.addExpr(a);
    const cb = try egraph.addExpr(b);
    try std.testing.expect(ca != cb);
    try std.testing.expect(!egraph.areEqual(a, b));
}

test "egraph — merge" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const two = try store.int(2);
    const three = try store.int(3);
    const five = try store.int(5);
    const sum = try store.binop("+", two, three);
    const c_sum = try egraph.addExpr(sum);
    const c_five = try egraph.addExpr(five);
    _ = try egraph.merge(c_sum, c_five);
    try std.testing.expect(egraph.areEqual(sum, five));
}

test "egraph — extraction" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const x = try store.sym("x");
    const one = try store.int(1);
    const mul = try store.binop("*", x, one);
    const c_mul = try egraph.addExpr(mul);
    const c_x = try egraph.addExpr(x);
    _ = try egraph.merge(c_mul, c_x);

    const best = egraph.extract(c_x, null).?;
    try std.testing.expect(cost(&store, best) == 1);
}

test "egraph — structurally equal nodes share a class" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const x = try store.sym("x");
    const y = try store.sym("x");

    try std.testing.expect(x != y);
    try std.testing.expect(expr.structuralEql(&store, x, y));

    const cx = try egraph.addExpr(x);
    const cy = try egraph.addExpr(y);

    try std.testing.expectEqual(cx, cy);
    try std.testing.expect(egraph.areEqual(x, y));
}

test "egraph — structurally different relation rhs do not collide" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const lhs = try store.int(1);
    const rhs1 = try store.int(2);
    const rhs2 = try store.int(3);

    const a = try store.relation(
        "R",
        &.{lhs},
        &.{rhs1},
    );

    const b = try store.relation(
        "R",
        &.{lhs},
        &.{rhs2},
    );

    const ca = try egraph.addExpr(a);
    const cb = try egraph.addExpr(b);

    try std.testing.expect(ca != cb);
    try std.testing.expect(!egraph.areEqual(a, b));
}

test "egraph — structurally different lambda parameters do not collide" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const body = try store.int(1);

    const a = try store.lambda(&.{"x"}, body);
    const b = try store.lambda(&.{"y"}, body);

    const ca = try egraph.addExpr(a);
    const cb = try egraph.addExpr(b);

    try std.testing.expect(ca != cb);
    try std.testing.expect(!egraph.areEqual(a, b));
}

test "egraph — merge establishes explicit equivalence" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = EGraph.init(&store, allocator);
    defer egraph.deinit();

    const a = try store.int(1);
    const b = try store.int(2);

    const ca = try egraph.addExpr(a);
    const cb = try egraph.addExpr(b);

    try std.testing.expect(!egraph.areEqual(a, b));

    _ = try egraph.merge(ca, cb);

    try std.testing.expect(egraph.areEqual(a, b));
}
