const std = @import("std");
const platform = @import("platform");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Tag = expr.Tag;
const Span = expr.Span;

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
        const is_op = std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "-") or
            std.mem.eql(u8, name, "*") or std.mem.eql(u8, name, "/") or
            std.mem.eql(u8, name, "%") or std.mem.eql(u8, name, "=") or
            std.mem.eql(u8, name, "<") or std.mem.eql(u8, name, ">") or
            std.mem.eql(u8, name, "if") or std.mem.eql(u8, name, "seq") or
            std.mem.eql(u8, name, "block") or std.mem.eql(u8, name, "tuple") or
            std.mem.eql(u8, name, "!") or std.mem.eql(u8, name, "&") or std.mem.eql(u8, name, "|");
        if (name.len > 0 and !is_op) {
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
    if (pattern_id >= store.len()) return pattern_id;
    const node = store.get(pattern_id);

    switch (node.tag) {
        .sym => {
            if (bindings.get(pattern_id)) |bound| return bound;
            if (bindings.get(node.payload)) |bound| return bound;
            return pattern_id;
        },
        .lit => return pattern_id,
        .apply => {
            const new_func = try substitutePattern(store, node.payload, bindings, allocator);
            const old_args = node.span_a.slice(store.pool.items);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(allocator);
            for (old_args) |arg| {
                try new_args.append(allocator, try substitutePattern(store, arg, bindings, allocator));
            }
            return store.apply(new_func, new_args.items);
        },
        .bind => {
            const new_val = try substitutePattern(store, node.aux, bindings, allocator);
            const span = try store.reserveSpan(2);
            store.pool.items[span.start] = new_val;
            store.pool.items[span.start + 1] = try store.unitLit();
            return store.addNode(.{
                .tag = .bind,
                .payload = node.payload,
                .aux = 0,
                .span_a = span,
                .span_b = Span.EMPTY,
            });
        },
        .lambda => {
            const bound_name = store.interner.resolve(node.payload);
            var shadowed = false;
            var it = bindings.iterator();
            while (it.next()) |entry| {
                if (entry.key_ptr.* < store.len()) {
                    const k_node = store.get(entry.key_ptr.*);
                    if (k_node.tag == .sym) {
                        const k_name = store.interner.resolve(k_node.payload);
                        if (std.mem.eql(u8, k_name, bound_name)) {
                            shadowed = true;
                            break;
                        }
                    }
                }
            }
            if (shadowed) return pattern_id;

            const old_body = node.span_a.slice(store.pool.items);
            var new_body: std.ArrayListUnmanaged(Id) = .{};
            defer new_body.deinit(allocator);
            for (old_body) |child| {
                try new_body.append(allocator, try substitutePattern(store, child, bindings, allocator));
            }
            const body_span = try store.pushSpan(new_body.items);
            return store.addNode(.{
                .tag = .lambda,
                .payload = node.payload,
                .aux = 0,
                .span_a = body_span,
                .span_b = Span.EMPTY,
            });
        },
        .relation => {
            const old_args = node.span_a.slice(store.pool.items);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(allocator);
            for (old_args) |arg| {
                try new_args.append(allocator, try substitutePattern(store, arg, bindings, allocator));
            }
            const span_a = try store.pushSpan(new_args.items);

            const old_args_b = node.span_b.slice(store.pool.items);
            var new_args_b: std.ArrayListUnmanaged(Id) = .{};
            defer new_args_b.deinit(allocator);
            for (old_args_b) |arg| {
                try new_args_b.append(allocator, try substitutePattern(store, arg, bindings, allocator));
            }
            const span_b = try store.pushSpan(new_args_b.items);

            return store.addNode(.{
                .tag = .relation,
                .payload = node.payload,
                .aux = 0,
                .span_a = span_a,
                .span_b = span_b,
            });
        },
        else => return pattern_id,
    }
}
