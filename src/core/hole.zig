//! Hole management for Core expressions.
//!
//! Un "trou" est un placeholder dans un arbre d'expression, represente
//! par `Tag.hole` avec un identifiant u32 unique. Ce module gere :
//! - allocation d'ids frais
//! - raffinement (lier un trou a une expression)
//! - inspection (quels trous sont encore libres)
//! - affichage (but + contexte)
//!
//! Le module est autonome : il ne connait que `expr.Store` et un
//! allocator. Il peut etre embarque par `Heaven` ou par n'importe
//! quel autre conteneur.

const std = @import("std");
const expr = @import("expr");

const Store = expr.Store;
const Id = expr.Id;

pub const HoleInfo = struct {
    id: u32,
    seen_in: ?Id = null,
};

pub const Error = error{
    UnknownHole,
    OutOfMemory,
};

pub const HoleState = struct {
    allocator: std.mem.Allocator,
    next_id: u32 = 0,
    /// Tous les trous connus, indexes par id.
    holes: std.AutoHashMapUnmanaged(u32, HoleInfo) = .{},
    /// Trous raffines : id -> expression Core.
    subst: std.AutoHashMapUnmanaged(u32, Id) = .{},
    /// Derniere expression racine ayant servi a creer un trou.
    last_root_expr: ?Id = null,

    pub fn init(allocator: std.mem.Allocator) HoleState {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *HoleState) void {
        self.holes.deinit(self.allocator);
        self.subst.deinit(self.allocator);
    }

    /// Cree un nouveau noeud trou dans le store avec un id unique.
    pub fn fresh(self: *HoleState, store: *Store) Error!Id {
        const id = self.next_id;
        self.next_id += 1;
        const node_id = try store.hole(id);
        try self.holes.put(self.allocator, id, .{
            .id = id,
            .seen_in = self.last_root_expr,
        });
        return node_id;
    }

    /// Lie un trou a une expression.
    pub fn refine(self: *HoleState, hole_id: u32, expr_id: Id) Error!void {
        if (!self.holes.contains(hole_id)) return Error.UnknownHole;
        try self.subst.put(self.allocator, hole_id, expr_id);
    }

    pub fn isRefined(self: *const HoleState, hole_id: u32) bool {
        return self.subst.contains(hole_id);
    }

    pub fn resolve(self: *const HoleState, hole_id: u32) ?Id {
        return self.subst.get(hole_id);
    }

    /// Renvoie vrai si `id` contient un trou non raffine.
    pub fn hasUnresolved(self: *const HoleState, store: *const Store, id: Id) bool {
        if (id >= store.len()) return false;
        const node = store.get(id);
        if (node.tag == .hole) {
            return !self.subst.contains(node.payload);
        }
        switch (node.tag) {
            .apply => {
                if (self.hasUnresolved(store, node.payload)) return true;
                for (store.spanSliceConst(node.span_a)) |c| {
                    if (self.hasUnresolved(store, c)) return true;
                }
            },
            .lambda, .bind, .relation => {
                if (self.hasUnresolved(store, node.aux)) return true;
                for (store.spanSliceConst(node.span_a)) |c| {
                    if (self.hasUnresolved(store, c)) return true;
                }
                for (store.spanSliceConst(node.span_b)) |c| {
                    if (self.hasUnresolved(store, c)) return true;
                }
            },
            else => {},
        }
        return false;
    }

    /// Liste triee des ids de trous.
    pub fn listIds(self: *const HoleState, allocator: std.mem.Allocator) ![]u32 {
        var ids = try allocator.alloc(u32, self.holes.count());
        var i: usize = 0;
        var it = self.holes.iterator();
        while (it.next()) |e| : (i += 1) ids[i] = e.key_ptr.*;
        std.mem.sort(u32, ids, {}, std.sort.asc(u32));
        return ids;
    }
};

test "hole_state standalone no leak" {
    const allocator = std.testing.allocator;

    var hs = HoleState.init(allocator);
    defer hs.deinit();

    var store = expr.Store.init(allocator);
    defer store.deinit();

    _ = try hs.fresh(&store);
}
