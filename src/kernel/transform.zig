// src/kernel/transform.zig
const strategy = @import("strategy.zig");

fn buildPlan(allocator: std.mem.Allocator, source: TTA, target: TTA, kb: *KnowledgeBase, tracer: *Tracer) ?strategy.Plan {
    for (strategy.REGISTRY) |strat| {
        if (strat.match(source, target, kb)) {
            return strat.build(allocator, source, target) catch null;
        }
    }
    return null;
}

pub const Provenance = union(enum) {
    Axiom: []const u8,
    Rule: []const u8,
    // ...
};

pub const TraceStep = struct {
    source: Provenance,
    engine: EngineType, // EGraph, CAS, Prolog, etc.
    operation: []const u8,
    timestamp: u64,
};

pub const TransformResult = union(enum) {
    success: struct { result: Proof, certificate: ArrayList(TraceStep) },
    failure: struct { error_msg: []const u8, certificate: ArrayList(TraceStep) },
};

pub fn transform(
    allocator: std.mem.Allocator,
    source: TTA,
    target: TTA,
    kb: *KnowledgeBase,
) !TransformResult {
    var tracer = TraceTracer.init(allocator);
    defer tracer.deinit();

    // 1. Analyse et Planification (Le "Compilateur")
    const plan = try buildPlan(allocator, source, target, kb, &tracer);
    if (plan == null) {
        return .{ .failure = .{ .error_msg = "NoDispatch", .certificate = tracer.steps } };
    }

    // 2. Exécution du plan
    for (plan.steps) |step| {
        const res = try executeStep(allocator, step, kb);
        try tracer.append(step, res);
        
        if (res.is_err) {
            return .{ .failure = .{ .error_msg = res.err, .certificate = tracer.steps } };
        }
    }

    return .{ .success = .{ .result = plan.extractProof(), .certificate = tracer.steps } };
}
