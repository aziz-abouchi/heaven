const std = @import("std");
const kanren = @import("kanren");
const expr_lib = @import("expr");

const KanrenEngine = kanren.KanrenEngine;
const Term = kanren.Term;
const Stream = kanren.Stream;
const Expr = expr_lib.Expr;

pub const Evalo = struct {
    engine: *KanrenEngine,

    pub fn init(engine: *KanrenEngine) Evalo {
        return .{ .engine = engine };
    }

    /// Enregistre les règles de déduction relationnelles (lookupo et evalo)
    pub fn registerRules(self: *Evalo) !void {
        const alloc = self.engine.allocator;

        // --- 1. RÈGLES LOOKUPO (Recherche dans l'environnement) ---
        // lookupo(X, [[X, Val] | Rest], Val)
        const x_var = self.engine.freshVar("x");
        const val_var = self.engine.freshVar("val");
        const rest_var = self.engine.freshVar("rest");
        const key_var = self.engine.freshVar("k");

        const env_head = try Term.pair(
            alloc,
            try Term.pair(alloc, x_var, val_var),
            rest_var,
        );
        try self.engine.addClause("lookupo", &.{ x_var, env_head, val_var });

        // lookupo(X, [[K, V] | Rest], Val) :- X != K
        const env_recur = try Term.pair(
            alloc,
            try Term.pair(alloc, key_var, self.engine.freshVar("v")),
            rest_var,
        );
        try self.engine.addClause("lookupo", &.{ x_var, env_recur, val_var });

        // --- 2. RÈGLES EVALO (Évaluateur relationnel) ---
        const env_var = self.engine.freshVar("env");

        // R1: Littéraux constants : evalo((lit v), Env, v)
        const lit_v = self.engine.freshVar("lit_v");
        const lit_expr = try Term.pair(alloc, Term.symbol("lit"), lit_v);
        try self.engine.addClause("evalo", &.{ lit_expr, env_var, lit_v });

        // R2: Variables : evalo((var x), Env, Val) :- lookupo(x, Env, Val)
        const var_name = self.engine.freshVar("var_name");
        const var_expr = try Term.pair(alloc, Term.symbol("var"), var_name);
        try self.engine.addClause("evalo", &.{ var_expr, env_var, val_var });

        // R3: Lambdas : evalo((lambda arg body), Env, (closure arg body Env))
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
    }

    /// Évaluation directe : (Expr, Env) -> Val
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

    /// Synthèse de programme / Inversion : (TargetVal, Env) -> Expr
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
};

test "evalo — évaluation et synthèse de base" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    var evalo = Evalo.init(&engine);
    try evalo.registerRules();

    // Test 1: Évaluation d'un littéral
    const lit_term = try Term.pair(allocator, Term.symbol("lit"), Term.symbol("42"));
    const env_empty = Term.symbol("nil");

    const result = try evalo.eval(lit_term, env_empty);
    try std.testing.expect(result != null);
}
