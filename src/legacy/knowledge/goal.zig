pub const GoalKind = enum {
    prove,
    discover,
    simplify,
    solve,
};

pub const Goal = struct {
    id: u64,
    kind: GoalKind,
    expr: ExprId,
};
