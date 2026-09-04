//! core_lower.zig - Lowering sémantique : HIR (syntax/ast.zig) -> Core (core/expr.zig)
//! 
//! Cet outil est responsable de la traduction de l'arbre syntaxique de haut niveau (HIR)
//! en expressions composées exclusivement des 6 primitives fondamentales de Heaven :
//! (lit, sym, apply, bind, lambda, relation).
//!
//! Propriété garantie : aucune construction "frontend" ou extension syntaxique n'atteint
//! le noyau logique après ce passage.

const std = @import("std");
const ast = @import("ast.zig");
const expr = @import("expr");

const Store = expr.Store;
const Id = expr.Id;

pub const LowerError = error{
    UnsupportedPatternInEquation,
    UnsupportedItem,
    UnsupportedExpr,
    OutOfMemory,
};

pub const CoreLowerer = struct {
    allocator: std.mem.Allocator,
    store: *Store,

    pub fn init(allocator: std.mem.Allocator, store: *Store) CoreLowerer {
        return .{
            .allocator = allocator,
            .store = store,
        };
    }

    /// Traduit une expression de haut niveau (ast.Expr) en expression primitive du noyau.
    pub fn lowerExpr(self: *CoreLowerer, e: ast.Expr) anyerror!Id {
        switch (e) {
            .identifier => |name| {
                return try self.store.sym(name);
            },
            .int => |val| {
                return try self.store.int(val);
            },
            .float => |val| {
                return try self.store.float(val);
            },
            .string => |s| {
                const interned = try self.store.interner.intern(s);
                return try self.store.lit(.{ .str = interned });
            },
            .boolean => |val| {
                return try self.store.boolean(val);
            },
            .parenthesized => |inner| {
                return try self.lowerExpr(inner.*);
            },
            .unary => |un| {
                const op_sym = try self.store.sym(un.op);
                const operand_id = try self.lowerExpr(un.operand.*);
                return try self.store.apply(op_sym, &.{operand_id});
            },
            .binary => |bin| {
                const lhs_id = try self.lowerExpr(bin.lhs.*);
                const rhs_id = try self.lowerExpr(bin.rhs.*);
                return try self.store.binop(bin.op, lhs_id, rhs_id);
            },
            .call => |c| {
                const callee_id = try self.lowerExpr(c.callee.*);
                var args_ids: std.ArrayListUnmanaged(Id) = .empty;
                defer args_ids.deinit(self.allocator);
                for (c.args) |arg| {
                    try args_ids.append(self.allocator, try self.lowerExpr(arg));
                }
                return try self.store.apply(callee_id, args_ids.items);
            },
            .application => |apps| {
                if (apps.len == 0) return try self.store.unitLit();
                const head_id = try self.lowerExpr(apps[0]);
                var args_ids: std.ArrayListUnmanaged(Id) = .empty;
                defer args_ids.deinit(self.allocator);
                for (apps[1..]) |arg| {
                    try args_ids.append(self.allocator, try self.lowerExpr(arg));
                }
                return try self.store.apply(head_id, args_ids.items);
            },
        }
    }

    /// Traduit une équation `name p1 p2 ... = body` en bind(name, lambda([p1, p2, ...], body)).
    /// Gère nativement la curryfication des paramètres via `Store.lambda`.
    pub fn lowerEquation(self: *CoreLowerer, eq: ast.Equation) anyerror!Id {
        var params: std.ArrayListUnmanaged([]const u8) = .empty;
        defer params.deinit(self.allocator);

        for (eq.patterns) |pat| {
            switch (pat) {
                .variable => |name| {
                    try params.append(self.allocator, name);
                },
                else => {
                    // Pour le jalon initial, on impose que les motifs de fonctions de base soient des variables libres.
                    // Le filtrage de motif complet sera abaissé ultérieurement.
                    return LowerError.UnsupportedPatternInEquation;
                },
            }
        }

        const body_id = try self.lowerExpr(eq.body);
        const fn_val = if (params.items.len > 0)
            try self.store.lambda(params.items, body_id)
        else
            body_id;

        return try self.store.bind(eq.name, fn_val);
    }

    /// Traduit un élément HIR global en primitive équivalente du Core.
    pub fn lowerItem(self: *CoreLowerer, item: ast.Item) anyerror!Id {
        switch (item) {
            .equation => |eq| {
                return try self.lowerEquation(eq);
            },
            .fn_decl => |fd| {
                const body_id = try self.lowerExpr(fd.body);
                const fn_val = if (fd.params.len > 0)
                    try self.store.lambda(fd.params, body_id)
                else
                    body_id;
                return try self.store.bind(fd.name, fn_val);
            },
            .theorem_decl => |td| {
                // Convergence d'un théorème vers la primitive "relation" du noyau
                const name_sym = try self.store.sym(td.name);
                const prop_id = try self.lowerTypeExpr(td.proposition);
                return try self.store.relation("theorem", &.{name_sym}, &.{prop_id});
            },
            .axiom_decl => |ad| {
                // Convergence d'un axiome vers la primitive "relation" du noyau
                const name_sym = try self.store.sym(ad.name);
                const prop_id = try self.lowerTypeExpr(ad.proposition);
                return try self.store.relation("axiom", &.{name_sym}, &.{prop_id});
            },
            else => return LowerError.UnsupportedItem,
        }
    }

    /// Traduit un type-expression de haut niveau vers l'expression correspondante.
    pub fn lowerTypeExpr(self: *CoreLowerer, te: ast.TypeExpr) anyerror!Id {
        switch (te) {
            .named => |name| {
                return try self.store.sym(name);
            },
            .arrow => |arr| {
                const from_id = try self.lowerTypeExpr(arr.from.*);
                const to_id = try self.lowerTypeExpr(arr.to.*);
                const op_arrow = try self.store.sym("->");
                return try self.store.apply(op_arrow, &.{from_id, to_id});
            },
            .generic => |g| {
                return try self.lowerGenericOrApplied(g.name, g.args);
            },
            .applied => |a| {
                return try self.lowerGenericOrApplied(a.name, a.args);
            },
            .forall => |fa| {
                // forall (x: A) (y: B). C -> apply(sym("forall"), [bind(x, A), bind(y, B), C])
                var binders: std.ArrayListUnmanaged(Id) = .empty;
                defer binders.deinit(self.allocator);
                for (fa.binders) |b| {
                    const ty_id = try self.lowerTypeExpr(b.ty);
                    const b_id = try self.store.bind(b.name, ty_id);
                    try binders.append(self.allocator, b_id);
                }
                const body_id = try self.lowerTypeExpr(fa.body.*);
                try binders.append(self.allocator, body_id);

                const forall_sym = try self.store.sym("forall");
                return try self.store.apply(forall_sym, binders.items);
            },
        }
    }

    fn lowerGenericOrApplied(self: *CoreLowerer, name: []const u8, args: []const ast.TypeExpr) anyerror!Id {
        const head_id = try self.store.sym(name);
        var args_ids: std.ArrayListUnmanaged(Id) = .empty;
        defer args_ids.deinit(self.allocator);
        for (args) |arg| {
            try args_ids.append(self.allocator, try self.lowerTypeExpr(arg));
        }
        return try self.store.apply(head_id, args_ids.items);
    }
};
