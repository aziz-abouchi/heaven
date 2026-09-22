//! ProofState — état de preuve interactif à la Rocq/Lean.
//!
//! Un ProofState contient une liste de buts. Chaque but a un contexte
//! (hypothèses) et une cible. Une tactique consomme le premier but et
//! produit 0, 1, ou N sous-buts.
//!
//! Modèle d'allocation : `hyps` et `label` sont alloués dans un aréna
//! fourni par l'appelant. ProofState ne libère PAS ces slices
//! individuellement — c'est l'aréna qui s'en charge. Conséquence : on
//! peut déplacer un Goal d'une liste à une autre sans risque de
//! double-free. C'est essentiel pour les combinateurs (seq, repeat).

const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Id = expr.Id;
const Store = expr.Store;

pub const Hypothesis = struct {
    name: []const u8,
    ty: Id,
};

pub const Goal = struct {
    hyps: []const Hypothesis,
    target: Id,
    label: []const u8 = "",
};

pub const ProofState = struct {
    allocator: Allocator,
    arena: *std.heap.ArenaAllocator,
    store: *Store,
    goals: std.ArrayListUnmanaged(Goal),
    theorem_name: []const u8,

    pub fn init(
        allocator: Allocator,
        arena: *std.heap.ArenaAllocator,
        store: *Store,
        theorem_name: []const u8,
    ) ProofState {
        return .{
            .allocator = allocator,
            .arena = arena,
            .store = store,
            .goals = .{},
            .theorem_name = theorem_name,
        };
    }

    /// Libère uniquement les buffers gérés par l'allocator — pas l'aréna.
    pub fn deinit(self: *ProofState) void {
        self.goals.deinit(self.allocator);
    }

    pub fn solved(self: *const ProofState) bool {
        return self.goals.items.len == 0;
    }

    pub fn currentGoal(self: *ProofState) ?*Goal {
        if (self.goals.items.len == 0) return null;
        return &self.goals.items[0];
    }

    pub fn popGoal(self: *ProofState) ?Goal {
        if (self.goals.items.len == 0) return null;
        return self.goals.orderedRemove(0);
    }

    pub fn appendGoal(self: *ProofState, goal: Goal) !void {
        try self.goals.append(self.allocator, goal);
    }

    /// Duplique un label dans l'aréna.
    pub fn dupLabel(self: *ProofState, s: []const u8) ![]const u8 {
        return try self.arena.allocator().dupe(u8, s);
    }

    /// Duplique un slice d'hypothèses dans l'aréna (deep copy des noms).
    pub fn dupHyps(self: *ProofState, hyps: []const Hypothesis) ![]const Hypothesis {
        const a = self.arena.allocator();
        const out = try a.alloc(Hypothesis, hyps.len);
        for (hyps, 0..) |h, i| {
            out[i] = .{ .name = try a.dupe(u8, h.name), .ty = h.ty };
        }
        return out;
    }

    /// Ajoute une hypothèse à un slice existant (alloue dans l'aréna).
    pub fn extendHyps(
        self: *ProofState,
        base: []const Hypothesis,
        extra: Hypothesis,
    ) ![]const Hypothesis {
        const a = self.arena.allocator();
        const out = try a.alloc(Hypothesis, base.len + 1);
        for (base, 0..) |h, i| {
            out[i] = .{ .name = try a.dupe(u8, h.name), .ty = h.ty };
        }
        out[base.len] = .{ .name = try a.dupe(u8, extra.name), .ty = extra.ty };
        return out;
    }

    pub fn pp(self: *ProofState, allocator: Allocator) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);
        const w = buf.writer(allocator);

        if (self.goals.items.len == 0) {
            try w.writeAll("✓ No goals remaining.\n");
            return buf.toOwnedSlice(allocator);
        }

        const n = self.goals.items.len;
        for (self.goals.items, 0..) |g, i| {
            if (n > 1) try w.print("Goal {d}/{d}\n", .{ i + 1, n });
            if (g.label.len > 0) try w.print("  [{s}]\n", .{g.label});

            if (g.hyps.len > 0) {
                try w.writeAll("  ── Hypotheses ──\n");
                for (g.hyps) |h| {
                    const ty_str = expr.toString(self.store, h.ty, allocator) catch "?";
                    defer allocator.free(ty_str);
                    try w.print("    {s} : {s}\n", .{ h.name, ty_str });
                }
            }
            const tgt = expr.toString(self.store, g.target, allocator) catch "?";
            defer allocator.free(tgt);
            try w.print("  ── Target ──\n    {s}\n\n", .{tgt});
        }
        return buf.toOwnedSlice(allocator);
    }
};
