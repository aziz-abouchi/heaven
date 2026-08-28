//! Gestion et application des règles de réécriture pour Heaven
const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const pattern_mod = @import("pattern");

pub const Rule = struct {
    id: Id,
    lhs: Id,
    rhs: Id,

    /// Extrait une règle depuis un nœud `.relation` du Store.
    /// Prend en charge les deux encodages (span_a = [lhs, rhs] ou span_a = [lhs], span_b = [rhs]).
    pub fn fromNode(store: *const Store, rule_id: Id) ?Rule {
        if (rule_id >= store.len()) return null;
        const node = store.get(rule_id);
        if (node.tag != .relation) return null;

        const pool = store.pool.items;
        const span_a = node.span_a.slice(pool);
        const span_b = node.span_b.slice(pool);

        if (span_a.len == 2) {
            return .{
                .id = rule_id,
                .lhs = span_a[0],
                .rhs = span_a[1],
            };
        } else if (span_a.len == 1 and span_b.len == 1) {
            return .{
                .id = rule_id,
                .lhs = span_a[0],
                .rhs = span_b[0],
            };
        }
        return null;
    }

    /// Tente d'appliquer la règle sur l'expression `target`.
    /// Retourne le nouvel `Id` si le motif correspond, sinon `null`.
    pub fn apply(self: Rule, store: *Store, target: Id, allocator: Allocator) !?Id {
        var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
        defer bindings.deinit(allocator);

        if (pattern_mod.exprPatternMatch(store, self.lhs, target, &bindings, allocator)) {
            const new_id = pattern_mod.substitutePattern(store, self.rhs, &bindings, allocator) catch return null;
            if (new_id < store.len() and new_id != target) {
                return new_id;
            }
        }
        return null;
    }
};

pub const MatchResult = struct {
    new_id: Id,
    rule: Rule,
};

/// Applique la première règle de la liste qui matche avec `target`.
pub fn applyFirstRule(
    store: *Store,
    rules: []const Id,
    target: Id,
    allocator: Allocator,
) !?MatchResult {
    for (rules) |rule_id| {
        const rule = Rule.fromNode(store, rule_id) orelse continue;
        if (try rule.apply(store, target, allocator)) |new_id| {
            return .{ .new_id = new_id, .rule = rule };
        }
    }
    return null;
}
