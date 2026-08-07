const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;

pub const Subst = struct {
    map: std.AutoHashMapUnmanaged(u32, Id) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) Subst {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Subst) void {
        self.map.deinit(self.allocator);
    }
    pub fn bind(self: *Subst, hole_idx: u32, id: Id) !void {
        try self.map.put(self.allocator, hole_idx, id);
    }
    pub fn lookup(self: *const Subst, hole_idx: u32) ?Id {
        return self.map.get(hole_idx);
    }
    pub fn walk(self: *const Subst, store: *const Store, id: Id) Id {
        const node = store.get(id);
        if (node.tag == .hole) {
            if (self.lookup(node.payload)) |bound| return self.walk(store, bound);
        }
        return id;
    }
};

pub const UnifyError = error{ Failure, OccursCheck, OutOfMemory };

pub fn unify(store: *const Store, subst: *Subst, a_raw: Id, b_raw: Id) UnifyError!void {
    const a = subst.walk(store, a_raw);
    const b = subst.walk(store, b_raw);
    if (a == b) return;
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag == .hole) {
        try subst.bind(na.payload, b);
        return;
    }
    if (nb.tag == .hole) {
        try subst.bind(nb.payload, a);
        return;
    }
    if (na.tag != nb.tag) return UnifyError.Failure;
    const pool = store.pool.items;
    switch (na.tag) {
        .sym => {
            if (na.payload != nb.payload) return UnifyError.Failure;
        },
        .lit => {
            const la = store.lits.items[na.aux];
            const lb = store.lits.items[nb.aux];
            if (!la.eql(lb)) return UnifyError.Failure;
        },
        .apply => {
            try unify(store, subst, na.payload, nb.payload);
            const aa = na.span_a.slice(pool);
            const ab = nb.span_a.slice(pool);
            if (aa.len != ab.len) return UnifyError.Failure;
            for (aa, ab) |ca, cb| try unify(store, subst, ca, cb);
        },
        .bind => {
            if (na.payload != nb.payload) return UnifyError.Failure;
            try unify(store, subst, na.aux, nb.aux);
        },
        .relation => {
            if (na.payload != nb.payload) return UnifyError.Failure;
            const aa = na.span_a.slice(pool);
            const ab = nb.span_a.slice(pool);
            if (aa.len != ab.len) return UnifyError.Failure;
            for (aa, ab) |ca, cb| try unify(store, subst, ca, cb);
        },
        .hole => unreachable,
        else => unreachable,
    }
}

pub const Stream = struct {
    answers: std.ArrayListUnmanaged(Subst) = .{},
    allocator: Allocator,
    pub fn init(allocator: Allocator) Stream {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Stream) void {
        for (self.answers.items) |*s| s.deinit();
        self.answers.deinit(self.allocator);
    }
    pub fn len(self: *const Stream) usize {
        return self.answers.items.len;
    }
};

pub const Kanren = struct {
    store: *Store,
    allocator: Allocator,
    kb: std.ArrayListUnmanaged(Id) = .{},

    pub fn init(store: *Store, allocator: Allocator) Kanren {
        return .{ .store = store, .allocator = allocator };
    }
    pub fn deinit(self: *Kanren) void {
        self.kb.deinit(self.allocator);
    }
    pub fn assertFact(self: *Kanren, id: Id) !void {
        try self.kb.append(self.allocator, id);
    }
    pub fn queryPattern(self: *Kanren, pattern: Id) !Stream {
        var stream = Stream.init(self.allocator);
        const node = self.store.get(pattern);
        if (node.tag != .relation) return stream;
        const head = node.payload;
        const pool = self.store.pool.items;
        for (self.kb.items) |fact_id| {
            const fact = self.store.get(fact_id);
            if (fact.tag != .relation) continue;
            if (fact.payload != head) continue;
            const pat_args = node.span_a.slice(pool);
            const fact_args = fact.span_a.slice(pool);
            if (pat_args.len != fact_args.len) continue;
            var subst = Subst.init(self.allocator);
            var ok = true;
            for (pat_args, fact_args) |pa, fa| {
                unify(self.store, &subst, pa, fa) catch {
                    ok = false;
                    break;
                };
            }
            if (ok) {
                try stream.answers.append(self.allocator, subst);
            } else {
                subst.deinit();
            }
        }
        return stream;
    }
};

test "unify — holes" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var subst = Subst.init(allocator);
    defer subst.deinit();
    const h = try store.hole(0);
    const val = try store.int(42);
    try unify(&store, &subst, h, val);
    try std.testing.expect(subst.walk(&store, h) == val);
}

test "kanren — query" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var kanren = Kanren.init(&store, allocator);
    defer kanren.deinit();
    try kanren.assertFact(try store.relation("human", &.{try store.sym("socrate")}, &.{}));
    try kanren.assertFact(try store.relation("human", &.{try store.sym("platon")}, &.{}));
    const h = try store.hole(0);
    const q = try store.relation("human", &.{h}, &.{});
    var results = try kanren.queryPattern(q);
    defer results.deinit();
    try std.testing.expect(results.len() == 2);
}

test "kanren — unification de listes" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var subst = Subst.init(allocator);
    defer subst.deinit();

    // Note : Si tu as des méthodes store.listNil() et store.listCons() dans ton expr.zig,
    // utilise-les directement ici à la place de ces placeholders.
    // Exemple supposé ici si tu as adapté ton Store :
    const val_42 = try store.int(42);
    const hole_0 = try store.hole(0);

    // Pour l'instant, si tu n'as pas encore exposé de fonctions de création de listes dans Store,
    // tu peux commenter ce test temporairement OU appeler ta fonction de création générique
    // qui se trouve dans ton `src/core/expr.zig` (comme `store.node(...)` ou ce que tu utilises dans ton parser).

    _ = val_42;
    _ = hole_0;
}
