const std = @import("std");
const kanren = @import("kanren");
const expr_lib = @import("expr");
const term_bridge = @import("term_bridge.zig");
const typeo_bridge = @import("typeo_bridge.zig");
const evalo_mod = @import("evalo.zig");

// On importe le rewriter déjà présent dans src/core/
const egraph_rewriter = @import("../core/egraph_rewriter.zig");
const saturation = @import("saturation.zig");
const extract = @import("extract.zig");

const Allocator = std.mem.Allocator;
const Store = expr_lib.Store;
const Id = expr_lib.Id;
const Term = kanren.Term;
const EGraph = egraph_rewriter.EGraph;
const RewriteEngine = egraph_rewriter.RewriteEngine;

pub const PipelineError = error{
    SynthesisFailed,
    OptimizationFailed,
    BridgeFailed,
    OutOfMemory,
};

pub const OptimizationPipeline = struct {
    allocator: Allocator,
    typeo: *typeo_bridge.typeo_mod.Typeo,
    evalo: *evalo_mod.Evalo,
    rewriter: *RewriteEngine,

    pub fn init(
        allocator: Allocator,
        typeo: *typeo_bridge.typeo_mod.Typeo,
        evalo: *evalo_mod.Evalo,
        rewriter: *RewriteEngine,
    ) OptimizationPipeline {
        return .{
            .allocator = allocator,
            .typeo = typeo,
            .evalo = evalo,
            .rewriter = rewriter,
        };
    }

    /// Synthétise une expression à partir d'un type donné, la sature dans l'E-Graph
    /// et extrait la forme canonique de coût minimal dans le Store Core.
    pub fn synthesizeAndOptimize(
        self: *OptimizationPipeline,
        store: *Store,
        target_type: Term,
        options: saturation.SaturationOptions,
    ) PipelineError!Id {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_alloc = arena.allocator();

        var egraph = EGraph.init(store, temp_alloc);
        defer egraph.deinit();

        // 1. Synthèse relationnelle via typeo
        const synth_res = typeo_bridge.synthesizeAndAddToEGraph(
            store,
            &egraph,
            self.typeo,
            target_type,
        ) catch return PipelineError.SynthesisFailed;

        // 2. Saturation d'égalité avec src/core/egraph_rewriter.zig
        var sat_engine = saturation.SaturationEngine.init(temp_alloc);
        _ = sat_engine.saturate(&egraph, self.rewriter, options) catch
            return PipelineError.OptimizationFailed;

        // 3. Extraction du meilleur terme selon le coût AST
        var extractor = extract.Extractor.init(temp_alloc);
        defer extractor.deinit();

        const best_term = extractor.extractBest(
            &egraph,
            synth_res.class,
            extract.defaultAstSizeCost,
        ) catch return PipelineError.OptimizationFailed;

        // 4. Ré-internement du terme optimal dans le Store Core
        return term_bridge.termToId(store, best_term) catch PipelineError.BridgeFailed;
    }
};

// ─────────────────────────────────────────────────────────────────
// Tests Pipeline
// ─────────────────────────────────────────────────────────────────

const testing = std.testing;

test "pipeline — synthèse et optimisation complète" {
    const allocator = testing.allocator;

    var engine = kanren.KanrenEngine.init(allocator);
    defer engine.deinit();

    var typeo = typeo_bridge.typeo_mod.Typeo.init(&engine);
    try typeo.registerRules();

    var evalo = evalo_mod.Evalo.init(&engine);
    try evalo.registerRules();

    var rewriter = RewriteEngine.init(allocator);
    defer rewriter.deinit();

    var store = Store.init(allocator);
    defer store.deinit();

    var pipeline = OptimizationPipeline.init(allocator, &typeo, &evalo, &rewriter);

    const res_id = try pipeline.synthesizeAndOptimize(
        &store,
        Term.sym("Bool"),
        .{ .max_iterations = 10 },
    );

    try testing.expect(store.isCore(res_id));
}
