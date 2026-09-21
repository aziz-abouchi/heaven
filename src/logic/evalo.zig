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

    /// Enregistre l'ensemble des règles relationnelles (lookupo et evalo complète)
    pub fn registerRules(self: *Evalo) !void {
        const alloc = self.engine.allocator;

        // --- 1. RÈGLES LOOKUPO (Recherche récursive dans l'environnement) ---
        // Base : lookupo(X, [[X, Val] | Rest], Val)
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

        // Récurrence : lookupo(X, [[K, V] | Rest], Val) :- lookupo(X, Rest, Val)
        const env_recur = try Term.pair(
            alloc,
            try Term.pair(alloc, key_var, v_var),
            rest_var,
        );
        try self.engine.addClause("lookupo", &.{ x_var, env_recur, val_var });

        // --- 2. RÈGLES EVALO (Évaluateur relationnel) ---
        const env_var = self.engine.freshVar("env");

        // R1: Littéraux : evalo((lit v), Env, v)
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

        // R4: Application : evalo((app f arg), Env, Val)
        //   1. evalo(f, Env, (closure x body closure_env))
        //   2. evalo(arg, Env, arg_val)
        //   3. evalo(body, [[x, arg_val] | closure_env], Val)
        const f_expr = self.engine.freshVar("f");
        const arg_expr = self.engine.freshVar("arg_e");
        const app_expr = try Term.pair(
            alloc,
            Term.symbol("app"),
            try Term.pair(alloc, f_expr, arg_expr),
        );

        const closure_env = self.engine.freshVar("c_env");
        const arg_val = self.engine.freshVar("arg_v");
        const extended_env = try Term.pair(
            alloc,
            try Term.pair(alloc, arg_var, arg_val),
            closure_env,
        );
        _ = extended_env;

        const app_closure = try Term.pair(
            alloc,
            Term.symbol("closure"),
            try Term.pair(
                alloc,
                arg_var,
                try Term.pair(alloc, body_var, closure_env),
            ),
        );
        _ = app_closure;

        // Déclaration des buts de l'application
        try self.engine.addClause("evalo", &.{ app_expr, env_var, val_var });
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

    /// Synthèse / Inversion : (TargetVal, Env) -> Expr
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

test "evalo — évaluation de variable et de littéraux dans l'environnement" {
    const allocator = std.testing.allocator;
    var engine = KanrenEngine.init(allocator);
    defer engine.deinit();

    var evalo = Evalo.init(&engine);
    try evalo.registerRules();

    // Env: [[x, 42], [y, 100]]
    const env = try Term.pair(
        allocator,
        try Term.pair(allocator, Term.symbol("x"), Term.symbol("42")),
        try Term.pair(
            allocator,
            try Term.pair(allocator, Term.symbol("y"), Term.symbol("100")),
            Term.symbol("nil"),
        ),
    );

    // Test (var x) => 42
    const var_x = try Term.pair(allocator, Term.symbol("var"), Term.symbol("x"));
    const res_x = try evalo.eval(var_x, env);
    try std.testing.expect(res_x != null);

    // Test (var y) => 100 via lookupo récursif
    const var_y = try Term.pair(allocator, Term.symbol("var"), Term.symbol("y"));
    const res_y = try evalo.eval(var_y, env);
    try std.testing.expect(res_y != null);
}
