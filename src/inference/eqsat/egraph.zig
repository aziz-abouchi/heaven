const std = @import("std");
const Allocator = std.mem.Allocator;
const canon_mod = @import("canon");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;

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

pub const EGraph = struct {
    store: *Store,
    allocator: Allocator,
    uf: UnionFind,
    classes: std.ArrayListUnmanaged(EClass) = .{},
    node_to_class: std.AutoHashMapUnmanaged(Id, ClassId) = .{},
    hashcons: std.AutoHashMapUnmanaged(u64, ClassId) = .{},
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
        self.hashcons.deinit(self.allocator);
        self.proofs.deinit(self.allocator);
    }

    pub fn addProof(self: *EGraph, step: ProofStep) !void {
        try self.proofs.append(self.allocator, step);
    }

    pub fn add(self: *EGraph, id: Id) !ClassId {
        const canonical = try canon_mod.canonicalize(self.store, self.allocator, id);
        if (self.node_to_class.get(canonical)) |class| {
            try self.node_to_class.put(self.allocator, id, class);
            return self.uf.find(class);
        }

        const h = expr.nodeHash(self.store, canonical);
        if (self.hashcons.get(h)) |existing| {
            const existing_class = self.uf.find(existing);
            try self.node_to_class.put(self.allocator, id, existing_class);
            try self.node_to_class.put(self.allocator, canonical, existing_class);
            try self.classes.items[existing_class].nodes.append(self.allocator, canonical);
            return existing_class;
        }

        const class = try self.uf.makeSet();
        var eclass = EClass.init(self.allocator);
        try eclass.nodes.append(self.allocator, canonical);
        try self.classes.append(self.allocator, eclass);
        try self.node_to_class.put(self.allocator, canonical, class);
        try self.node_to_class.put(self.allocator, id, class);
        try self.hashcons.put(self.allocator, h, class);
        return class;
    }

    pub fn addExpr(self: *EGraph, id: Id) !ClassId {
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        switch (node.tag) {
            .sym, .lit, .hole => {},
            .apply => {
                _ = try self.addExpr(node.payload);
                for (node.span_a.slice(pool)) |child| _ = try self.addExpr(child);
            },
            .bind => _ = try self.addExpr(node.aux),
            .relation => {
                for (node.span_a.slice(pool)) |child| _ = try self.addExpr(child);
                for (node.span_b.slice(pool)) |child| _ = try self.addExpr(child);
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

    pub fn extract(egraph: *EGraph, class: ClassId, qtt: ?*QttCost) ?Id {
        const canonical = egraph.uf.find(class);
        if (canonical >= egraph.classes.items.len) return null;
        const eclass = &egraph.classes.items[canonical];
        if (eclass.nodes.items.len == 0) return null;

        var best: Id = eclass.nodes.items[0];
        var best_cost: u32 = if (qtt) |q| q.total(egraph.store, best) else cost(egraph.store, best);
        for (eclass.nodes.items[1..]) |node_id| {
            const c = if (qtt) |q| q.total(egraph.store, node_id) else cost(egraph.store, node_id);
            if (c < best_cost) {
                best = node_id;
                best_cost = c;
            }
        }
        return best;
    }
};

pub fn cost(store: *const Store, id: Id) u32 {
    const node = store.get(id);
    var c: u32 = 1;
    switch (node.tag) {
        .lit => {},
        .sym => {},
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
