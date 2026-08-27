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
            //if (na.payload != nb.payload) return false;
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
        .sym => {
            const p_name = store.interner.resolve(p.payload);
            const t_name = store.interner.resolve(t.payload);
            return std.mem.eql(u8, p_name, t_name);
        },
        .apply, .bind, .lambda, .relation => {
            // Comparaison des payloads en tenant compte des noms de symboles
            const p_payload_node = store.get(p.payload);
            const t_payload_node = store.get(t.payload);
            var payload_match = false;
            if (p_payload_node.tag == .sym and t_payload_node.tag == .sym) {
                const p_name = store.interner.resolve(p_payload_node.payload);
                const t_name = store.interner.resolve(t_payload_node.payload);
                payload_match = std.mem.eql(u8, p_name, t_name);
            } else {
                payload_match = p.payload == t.payload;
            }
            if (!payload_match) return false;

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

/// Un symbole est une variable de pattern s'il commence par '?'
fn isPatternVar(store: *Store, payload: u32) bool {
    const name = store.interner.resolve(payload);
    return name.len > 0 and name[0] == '?';
}

/// Égalité structurelle (pour les patterns non-linéaires comme (+ ?x ?x))
fn sameTerm(store: *Store, a: Id, b: Id) bool {
    if (a == b) return true;
    if (a >= store.len() or b >= store.len()) return false;
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != nb.tag) return false;
    return switch (na.tag) {
        .sym => na.payload == nb.payload,
        .lit => store.lits.items[na.aux].eql(store.lits.items[nb.aux]),
        .apply => blk: {
            if (!sameTerm(store, na.payload, nb.payload)) break :blk false;
            const aa = na.span_a.slice(store.pool.items);
            const ab = nb.span_a.slice(store.pool.items);
            if (aa.len != ab.len) break :blk false;
            for (aa, ab) |x, y_| {
                if (!sameTerm(store, x, y_)) break :blk false;
            }
            break :blk true;
        },
        else => false,
    };
}

/// Matching structural : `?x` se lie à n'importe quel sous-terme
/// (cohérence vérifiée entre occurrences), les autres symboles exigent l'égalité.
pub fn exprPatternMatch(store: *Store, pattern_id: Id, target_id: Id, bindings: anytype, allocator: std.mem.Allocator) bool {
    if (pattern_id >= store.len() or target_id >= store.len()) return false;

    const p = store.get(pattern_id);
    const t = store.get(target_id);

    switch (p.tag) {
        .sym => {
            if (isPatternVar(store, p.payload)) {
                // Déjà liée ? (patterns non-linéaires : (+ ?x ?x))
                if (bindings.get(p.payload)) |bound| return sameTerm(store, bound, target_id);
                bindings.put(allocator, p.payload, target_id) catch return false;
                return true;
            }
            // Symbole littéral : égalité exacte
            if (t.tag != .sym) return false;
            return p.payload == t.payload;
        },
        .lit => {
            if (t.tag != .lit) return false;
            return store.lits.items[p.aux].eql(store.lits.items[t.aux]);
        },
        .apply => {
            if (t.tag != .apply) return false;
            if (!exprPatternMatch(store, p.payload, t.payload, bindings, allocator)) return false;
            const p_args = p.span_a.slice(store.pool.items);
            const t_args = t.span_a.slice(store.pool.items);
            if (p_args.len != t_args.len) return false;
            for (p_args, t_args) |pa, ta| {
                if (!exprPatternMatch(store, pa, ta, bindings, allocator)) return false;
            }
            return true;
        },
        else => return pattern_id == target_id,
    }
}

pub fn substitutePattern(store: *Store, pattern_id: Id, bindings: anytype, allocator: std.mem.Allocator) !Id {
    // Un Id hors store est un bug appelant → erreur explicite, pas de relayage
    if (pattern_id >= store.len()) return error.InvalidPatternId;
    const node = store.get(pattern_id);

    switch (node.tag) {
        .sym => {
            // Uniquement les clés Sym (?x etc.) — jamais d'Id de nœud
            if (bindings.get(node.payload)) |bound| {
                if (bound >= store.len()) return error.InvalidBinding;
                return bound;
            }
            return pattern_id;
        },
        .lit => return pattern_id,
        .apply => {
            const new_func = try substitutePattern(store, node.payload, bindings, allocator);
            const old_args = node.span_a.slice(store.pool.items);
            var new_args: std.ArrayListUnmanaged(Id) = .{};
            defer new_args.deinit(allocator);
            // span_a[0] == func (déjà substitué via node.payload) — SAUTER
            if (old_args.len > 1) {
                for (old_args[1..]) |arg| {
                    try new_args.append(allocator, try substitutePattern(store, arg, bindings, allocator));
                }
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
