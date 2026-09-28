pub const KnowledgeKind = enum {
    theorem,
    axiom,
    rewrite,
    ontology,
    proof,
};

pub const KnowledgeObject = struct {
    id: u64,
    kind: KnowledgeKind,
    name: []const u8,
    expr: ExprId,
};
