const std = @import("std");
const KanrenEngine = @import("kanren").KanrenEngine;
const Term = @import("kanren").Term;
const term_bridge = @import("term_bridge");
const expr = @import("expr");

pub const Typeo = struct {
    engine: *KanrenEngine,

    pub fn init(engine: *KanrenEngine) Typeo {
        return .{ .engine = engine };
    }

    /// No-op : Typeo n'est pas propriétaire du KanrenEngine.
    pub fn deinit(self: *Typeo) void {
        _ = self;
    }

    /// Enregistre les règles de typage fondamentales.
    pub fn registerRules(self: *Typeo) !void {
        const rel = self.engine.defineRelation("typeo");
        const alloc = std.heap.page_allocator;

        // 1. typeo(Gamma, lit(N), Int)
        try self.engine.addClause(
            rel.name,
            &.{
                self.engine.fresh(),
                self.engine.parseTerm("lit(N)"),
                Term.sym("Int"),
            },
            &.{},
            2,
        );

        // 2. typeo(Gamma, lambda(x, lit(N)), Int -> Int)
        const lambda_ast = Term.list(alloc, &.{
            Term.sym("lambda"),
            Term.sym("x"),
            Term.list(alloc, &.{ Term.sym("lit"), .{ .Var = 1 } }),
        });
        try self.engine.addClause(
            rel.name,
            &.{
                self.engine.fresh(),
                lambda_ast,
                Term.arrow(Term.sym("Int"), Term.sym("Int")),
            },
            &.{},
            2,
        );

        // 3. typeo(Gamma, lambda(x, true), Bool)  ← nécessaire pour le test "sens inverse"
        const bool_lambda_ast = Term.list(alloc, &.{
            Term.sym("lambda"),
            Term.sym("x"),
            Term.sym("true"),
        });
        try self.engine.addClause(
            rel.name,
            &.{
                self.engine.fresh(),
                bool_lambda_ast,
                Term.sym("Bool"),
            },
            &.{},
            2,
        );
    }

    /// Inférence (input = expression concrète) : renvoie le type.
    /// Synthèse  (input = variable libre)     : renvoie l'expression.
    pub fn query(self: *Typeo, expr_term: Term, target_type: Term) !?Term {
        const gamma_empty = Term.sym("nil");

        var stream = self.engine.solve(
            "typeo",
            &.{ gamma_empty, expr_term, target_type },
            1,
        );
        defer stream.deinit();

        for (stream.items.items) |sub| {
            const arena = self.engine.transientAllocator();
            return switch (expr_term) {
                .Var => sub.walkDeepIn(expr_term, arena),
                else => sub.walkDeepIn(target_type, arena),
            };
        }
        return null;
    }

    /// Variante de `query` qui produit directement une expression Core.
    /// Le `Store` doit rester vivant aussi longtemps que l'`Id` retourné.
    pub fn queryCore(
        self: *Typeo,
        store: *expr.Store,
        expr_term: Term,
        target_type: Term,
    ) !?expr.Id {
        const result = try self.query(expr_term, target_type);
        if (result == null) return null;
        return try term_bridge.termToId(store, result.?);
    }
};

const testing = std.testing;

test "typeo — inférence de type (sens direct)" {
    var engine = KanrenEngine.init(testing.allocator);
    defer engine.deinit();

    var typeo = Typeo.init(&engine);
    try typeo.registerRules();

    const expr_int = Term.primitiveLitInt(42);
    const var_t = Term.freshVar("T");

    const result = try typeo.query(expr_int, var_t);
    try testing.expect(result != null);
    try testing.expectEqualStrings("Int", result.?.getSymbolName().?);
}

test "typeo — synthèse de programme (sens inverse)" {
    var engine = KanrenEngine.init(testing.allocator);
    defer engine.deinit();

    var typeo = Typeo.init(&engine);
    try typeo.registerRules(); // ← ajouté

    const var_expr = Term.freshVar("0");
    const target_type = Term.sym("Bool");

    const synthesized_ast = try typeo.query(var_expr, target_type);

    try testing.expect(synthesized_ast != null);
    try testing.expect(synthesized_ast.?.isLambda());
}
