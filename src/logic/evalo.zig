const std = @import("std");
const kanren = @import("kanren");
const expr_lib = @import("expr");
const term_bridge = @import("term_bridge.zig");

const KanrenEngine = kanren.KanrenEngine;
const Term = kanren.Term;
const Stream = kanren.Stream;
const Store = expr_lib.Store;
const Id = expr_lib.Id;

pub const Evalo = struct {
    engine: *KanrenEngine,

    pub fn init(engine: *KanrenEngine) Evalo {
        return .{ .engine = engine };
    }

    /// Enregistre l'ensemble des règles relationnelles (lookupo et evalo complète)
    pub fn registerRules(self: *Evalo) !void {
        const alloc = self.engine.allocator;

        // --- 1. RÈGLES LOOKUPO (Recherche récursive dans l'environnement) ---
        const x_var = self.engine.freshVar("x");
        const val_var = self.engine.freshVar("val");
        const rest_var = self.engine.freshVar("rest");
        const key_var = self.engine.freshVar("k");
        const v_var = self.engine.freshVar("v");

        const env_head = try Term.pair(
            alloc,
            try Term.pair(alloc, x_var, val_var),
            rest_var,
        );
        try self.engine.addClause("lookupo", &.{ x_var, env_head, val_var });

        const env_recur = try Term.pair(
            alloc,
            try Term.pair(alloc, key_var, v_var),
            rest_var,
        );
        try self.engine.addClause("lookupo", &.{ x_var, env_recur, val_var });

        // --- 2. RÈGLES EVALO (Évaluateur relationnel) ---
        const env_var = self.engine.freshVar("env");

        // R1: Littéraux
        const lit_v = self.engine.freshVar("lit_v");
        const lit_expr = try Term.pair(alloc, Term.symbol("lit"), lit_v);
        try self.engine.addClause("evalo", &.{ lit_expr, env_var, lit_v });

        // R2: Variables
        const var_name = self.engine.freshVar("var_name");
        const var_expr = try Term.pair(alloc, Term.symbol("var"), var_name);
        try self.engine.addClause("evalo", &.{ var_expr, env_var, val_var });

        // R3: Lambdas
        const arg_var = self.engine.freshVar("arg");
        const body_var = self.engine.freshVar("body");
        const lam_expr = try Term.pair(
            alloc,
            Term.symbol("lambda"),
            try Term.pair(alloc, arg_var, body_var),
        );
        const closure_val = try Term.pair(
            alloc,
            Term.symbol("closure"),
            try Term.pair(
                alloc,
                arg_var,
                try Term.pair(alloc, body_var, env_var),
            ),
        );
        try self.engine.addClause("evalo", &.{ lam_expr, env_var, closure_val });

        // R4: Application
        const f_expr = self.engine.freshVar("f");
        const arg_expr = self.engine.freshVar("arg_e");
        const app_expr = try Term.pair(
            alloc,
            Term.symbol("app"),
            try Term.pair(alloc, f_expr, arg_expr),
        );

        try self.engine.addClause("evalo", &.{ app_expr, env_var, val_var });
    }

    /// Évaluation directe : Term -> Term
    pub fn eval(self: *Evalo, expr_term: Term, env_term: Term) !?Term {
        const val_var = self.engine.freshVar("val");
        var stream = self.engine.solve("evalo", &.{ expr_term, env_term, val_var }, 1);
        defer stream.deinit();

        if (stream.items.items.len > 0) {
            const sub = stream.items.items[0];
            return sub.walkDeep(val_var);
        }
        return null;
    }

    /// Synthèse : TargetVal Term -> Expr Term
    pub fn synthesize(self: *Evalo, target_val: Term, env_term: Term) !?Term {
        const expr_var = self.engine.freshVar("expr");
        var stream = self.engine.solve("evalo", &.{ expr_var, env_term, target_val }, 1);
        defer stream.deinit();

        if (stream.items.items.len > 0) {
            const sub = stream.items.items[0];
            return sub.walkDeep(expr_var);
        }
        return null;
    }

    /// Helper Haut Niveau : Évalue un `Id` Core et retourne un `Id` réinterné dans le Store
    pub fn evalExpr(self: *Evalo, store: *Store, expr_id: Id, env_term: Term) !?Id {
        const alloc = self.engine.allocator;
        const expr_term = try term_bridge.idToTerm(alloc, store, expr_id);
        if (try self.eval(expr_term, env_term)) |res_term| {
            return try term_bridge.termToId(store, res_term);
        }
        return null;
    }

    /// Helper Haut Niveau : Synthétise une expression `Id` Core produisant la valeur d'entrée
    pub fn synthesizeExpr(self: *Evalo, store: *Store, target_val_id: Id, env_term: Term) !?Id {
        const alloc = self.engine.allocator;
        const target_term = try term_bridge.idToTerm(alloc, store, target_val_id);
        if (try self.synthesize(target_term, env_term)) |expr_term| {
            return try term_bridge.termToId(store, expr_term);
        }
        return null;
    }
};

test "evalo — pont de haut niveau avec Store Core" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    var evalo = Evalo.init(&engine);
    try evalo.registerRules();

    var store = Store.init(allocator);
    defer store.deinit();

    // Littéral d'entier dans le Store Core
    const lit_id = try store.int(42);

    // Environnement vide (nil)
    const env = Term.Nil;

    // Convertit le littéral en S-expr (lit 42)
    const lit_sym = try store.sym("lit");
    const lit_expr_id = try store.apply(lit_sym, &.{lit_id});

    // Évaluation via le pont
    const res_id = try evalo.evalExpr(&store, lit_expr_id, env);
    try std.testing.expect(res_id != null);

    const res_node = store.get(res_id.?);
    try std.testing.expect(res_node.tag == .lit);
    try std.testing.expectEqual(@as(i64, 42), store.lits.items[res_node.aux].int);
}
