const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;

pub fn exprStructuralEq(store: *const Store, a: Id, b: Id) bool {
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != nb.tag) return false;

    return switch (na.tag) {
        .sym => na.payload == nb.payload,
        .lit => {
            const la = store.lits.items[na.aux];
            const lb = store.lits.items[nb.aux];
            return la.eql(lb);
        },
        .apply => {
            if (na.payload != nb.payload) return false;
            const pool = store.pool.items;
            const ca = na.span_a.slice(pool);
            const cb = nb.span_a.slice(pool);
            if (ca.len != cb.len) return false;
            for (ca, cb) |xa, xb| {
                if (!exprStructuralEq(store, xa, xb)) return false;
            }
            return true;
        },
        .bind => {
            if (na.payload != nb.payload) return false;
            const pool = store.pool.items;
            const ca = na.span_a.slice(pool);
            const cb = nb.span_a.slice(pool);
            if (ca.len != cb.len) return false;
            for (ca, cb) |xa, xb| {
                if (!exprStructuralEq(store, xa, xb)) return false;
            }
            return true;
        },
        .lambda => {
            if (na.payload != nb.payload) return false;
            const pool = store.pool.items;
            const ca = na.span_a.slice(pool);
            const cb = nb.span_a.slice(pool);
            if (ca.len != cb.len) return false;
            for (ca, cb) |xa, xb| {
                if (!exprStructuralEq(store, xa, xb)) return false;
            }
            return true;
        },
        .relation => {
            const pool = store.pool.items;
            const ca = na.span_a.slice(pool);
            const cb = nb.span_a.slice(pool);
            if (ca.len != cb.len) return false;
            for (ca, cb) |xa, xb| {
                if (!exprStructuralEq(store, xa, xb)) return false;
            }
            return true;
        },
        .hole => false,
        else => false,
    };
}

pub const MatchError = error{ OutOfMemory, MatchFailed };

pub const Bindings = struct {
    map: std.AutoHashMapUnmanaged(Sym, Id),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Bindings {
        return .{ .map = .{}, .allocator = allocator };
    }
    pub fn deinit(self: *Bindings) void {
        self.map.deinit(self.allocator);
    }
    pub fn get(self: *const Bindings, s: expr.Sym) ?Id {
        return self.map.get(s);
    }
    pub fn put(self: *Bindings, s: expr.Sym, id: Id) !void {
        try self.map.put(self.allocator, s, id);
    }
};

const Sym = expr.Sym;
const Allocator = std.mem.Allocator;

pub fn match(store: *const Store, pattern: Id, target: Id, bindings: *Bindings) MatchError!bool {
    const p = store.get(pattern);
    const t = store.get(target);

    if (p.tag == .sym) {
        const name = store.interner.resolve(p.payload);
        if (name.len > 0 and (name[0] == '_' or std.ascii.isUpper(name[0]))) {
            if (bindings.get(p.payload)) |bound| {
                return exprStructuralEq(store, bound, target);
            }
            try bindings.put(p.payload, target);
            return true;
        }
    }

    if (p.tag != t.tag) return false;

    return switch (p.tag) {
        .lit => {
            const la = store.lits.items[p.aux];
            const lb = store.lits.items[t.aux];
            return la.eql(lb);
        },
        .sym => p.payload == t.payload,
        .apply, .bind, .lambda, .relation => {
            if (p.payload != t.payload) return false;
            const pool = store.pool.items;
            const pa = p.span_a.slice(pool);
            const ta = t.span_a.slice(pool);
            if (pa.len != ta.len) return false;
            for (pa, ta) |pi, ti| {
                if (!try match(store, pi, ti, bindings)) return false;
            }
            const pb = p.span_b.slice(pool);
            const tb = t.span_b.slice(pool);
            if (pb.len != tb.len) return false;
            for (pb, tb) |pi, ti| {
                if (!try match(store, pi, ti, bindings)) return false;
            }
            return true;
        },
        .hole => true,
        else => false,
    };
}

pub fn exprPatternMatch(store: *const Store, pattern: Id, target: Id, bindings: *std.AutoHashMapUnmanaged(u32, Id), allocator: Allocator) bool {
    var b = Bindings.init(allocator);
    defer b.deinit();
    const result = match(store, pattern, target, &b) catch return false;
    if (result) {
        var it = b.map.iterator();
        while (it.next()) |entry| {
            bindings.put(allocator, entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
    }
    return result;
}

pub fn substitutePattern(store: *Store, pattern_id: Id, bindings: anytype, allocator: std.mem.Allocator) !Id {
    _ = store;
    _ = pattern_id;
    _ = bindings;
    _ = allocator;
    return 0; // Stub temporaire
}
