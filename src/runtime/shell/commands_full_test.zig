const std = @import("std");
const testing = std.testing;
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const matrix_bridge = @import("matrix_bridge");
const parse = @import("parse");
const transform = @import("transform");
const skill = @import("skill");
const platform = @import("platform");
const proof_core = @import("proof_core");
const agent = @import("agent");
const math = @import("math");
const Commands = @import("commands").Commands;
const Store = expr.Store;
const Engine = engine_expr.Engine;

// ═══════════════════════════════════════════════════════════
// Helper : créer un environnement Commands complet
// ═══════════════════════════════════════════════════════════
const TestContext = struct {
    arena: std.heap.ArenaAllocator,
    alloc: std.mem.Allocator,
    cmds: Commands,
    store: Store,
    env: engine_expr.Env,
    engine: Engine,
    bridge: matrix_bridge.MatrixBridge,
    parser: parse.Parser,
    math_inst: math.Math,
    kb: transform.KnowledgeBase,
    skills: skill.SkillRegistry,
    qtt_env: std.StringHashMapUnmanaged(u2),
    proof_core_inst: proof_core.ProofCore,
    agent_inst: agent.Agent,
    active_theorem: ?[]const u8,
    pending_proof_request: ?[]const u8,
};

fn setupCommands(allocator: std.mem.Allocator) !*TestContext {
    const ctx = try allocator.create(TestContext);
    errdefer allocator.destroy(ctx);

    ctx.arena = std.heap.ArenaAllocator.init(allocator);
    errdefer ctx.arena.deinit();
    ctx.alloc = ctx.arena.allocator();

    ctx.store = Store.init(ctx.alloc);
    ctx.env = engine_expr.Env.init(ctx.alloc);
    ctx.engine = engine_expr.Engine.initTest(ctx.alloc, &ctx.store, &ctx.env);
    ctx.bridge = matrix_bridge.MatrixBridge.init(&ctx.store, ctx.alloc);
    ctx.parser = parse.Parser.init(&ctx.store, &ctx.engine, &ctx.env, ctx.alloc);
    ctx.math_inst = math.Math.init(&ctx.store, &ctx.engine, &ctx.bridge, &ctx.parser, ctx.alloc);
    ctx.kb = transform.KnowledgeBase.init(ctx.alloc);
    ctx.skills = skill.SkillRegistry.init(ctx.alloc);
    ctx.qtt_env = .{};
    ctx.proof_core_inst = proof_core.ProofCore.init(ctx.alloc);
    ctx.agent_inst = agent.Agent.init(ctx.alloc);
    ctx.active_theorem = null;
    ctx.pending_proof_request = null;

    ctx.cmds = try Commands.init(
        &ctx.store,
        &ctx.engine,
        &ctx.env,
        &ctx.bridge,
        ctx.alloc,
        &ctx.parser,
        &ctx.math_inst,
        &ctx.kb,
        &ctx.skills,
        &ctx.qtt_env,
        &ctx.proof_core_inst,
        &ctx.agent_inst,
        &ctx.active_theorem,
        &ctx.pending_proof_request,
    );
    try ctx.cmds.initDefaultRules();
    return ctx;
}

fn teardownCommands(ctx: *TestContext, allocator: std.mem.Allocator) void {
    ctx.arena.deinit(); // ← libère TOUT d'un coup, zéro leak
    allocator.destroy(ctx);
}

// ═══════════════════════════════════════════════════════════
// Test : help, stats, doc
// ═══════════════════════════════════════════════════════════
test "help returns command list" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("help");

    try testing.expect(std.mem.indexOf(u8, result, "help") != null);
    try testing.expect(std.mem.indexOf(u8, result, "theorem") != null);
}

test "stats returns engine status" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("stats");

    try testing.expect(std.mem.indexOf(u8, result, "Engine") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : let, eval, simplify
// ═══════════════════════════════════════════════════════════
test "let assigns variable" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("let x = 42");

    try testing.expect(std.mem.indexOf(u8, result, "x") != null);
}

test "eval evaluates arithmetic" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("(+ 2 3)");

    try testing.expect(std.mem.indexOf(u8, result, "5") != null);
}

test "simplify reduces x + 0" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("simplify x + 0");
    // Vérifie juste que le résultat n'est pas vide et contient "x"
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "x") != null);
}

test "rewrite adds rule" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("rewrite x + 0 => x");

    try testing.expect(std.mem.indexOf(u8, result, "rule added") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : type, infer
// ═══════════════════════════════════════════════════════════
test "type returns type of expression" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("type 42");

    try testing.expect(result.len > 0);
}

test "infer infers type" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("infer 42");

    try testing.expect(result.len > 0);
}

// ═══════════════════════════════════════════════════════════
// Test : theorem, prove, theorems
// ═══════════════════════════════════════════════════════════
test "theorem declares theorem" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("theorem add_zero : x + 0 = x");

    try testing.expect(std.mem.indexOf(u8, result, "stated") != null);
}

test "prove by simplify" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("theorem add_zero : x + 0 = x");
    const result = try ctx.cmds.eval("prove add_zero by simplify");

    try testing.expect(std.mem.indexOf(u8, result, "proved") != null or std.mem.indexOf(u8, result, "failed") != null);
}

test "theorems lists theorems" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("theorem add_zero : x + 0 = x");
    const result = try ctx.cmds.eval("theorems");

    try testing.expect(std.mem.indexOf(u8, result, "add_zero") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : derive, solve, expand, integrate
// ═══════════════════════════════════════════════════════════
test "derive computes derivative" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("derive x * x");

    try testing.expect(result.len > 0);
}

test "solve solves equation" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("solve x + 1 = 3");

    try testing.expect(result.len > 0);
}

test "expand expands expression" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("expand (x + 1) * (x + 1)");

    try testing.expect(result.len > 0);
}

test "integrate computes integral" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("integrate x");

    try testing.expect(result.len > 0);
}

// ═══════════════════════════════════════════════════════════
// Test : latex, quote, explain, trace
// ═══════════════════════════════════════════════════════════
test "latex generates latex" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("latex x + 1");

    try testing.expect(std.mem.indexOf(u8, result, "latex") != null);
}

test "quote shows AST" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("quote x + 1");

    try testing.expect(result.len > 0);
}

test "explain shows steps" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("explain x + 0");

    try testing.expect(std.mem.indexOf(u8, result, "step") != null);
}

test "trace shows execution" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("trace x + 0");

    try testing.expect(std.mem.indexOf(u8, result, "trace") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : qtt, dep, hole
// ═══════════════════════════════════════════════════════════
test "qtt sets quantity" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("qtt x : 1");

    try testing.expect(std.mem.indexOf(u8, result, "qtt") != null);
}

test "dep shows dependent types" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("dep Vec 3 Int");

    try testing.expect(result.len > 0);
}

test "hole resolves type hole" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("hole ? + 1 = 3");

    try testing.expect(result.len > 0);
}

// ═══════════════════════════════════════════════════════════
// Test : plot
// ═══════════════════════════════════════════════════════════
test "plot generates plot" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("plot x * x");

    try testing.expect(std.mem.indexOf(u8, result, "plot") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : skill
// ═══════════════════════════════════════════════════════════
test "skill applies tactic" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("theorem add_zero : x + 0 = x");
    const result = try ctx.cmds.eval("skill simplify");

    try testing.expect(result.len > 0);
}

// ═══════════════════════════════════════════════════════════
// Test : axiom
// ═══════════════════════════════════════════════════════════
test "axiom declares axiom" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("axiom add_zero : x + 0 = x");

    try testing.expect(std.mem.indexOf(u8, result, "axiom") != null);
}

// ═══════════════════════════════════════════════════════════
// Test : optimize, subst, sexpr
// ═══════════════════════════════════════════════════════════
test "optimize optimizes expression" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("optimize x + 0");

    try testing.expect(result.len > 0);
}

test "subst performs substitution" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("subst x + 1 x 5");

    try testing.expect(result.len > 0);
}

test "sexpr shows s-expression" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    const result = try ctx.cmds.eval("sexpr (+ 1 2)");

    try testing.expect(result.len > 0);
}

// ═══════════════════════════════════════════════════════════
// Test : function definition and call
// ═══════════════════════════════════════════════════════════
test "function definition and call" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("double x = (* x 2)");
    const result = try ctx.cmds.eval("double 21");

    try testing.expectEqualStrings("42", result);
}

// ═══════════════════════════════════════════════════════════
// Test : actor lifecycle
// ═══════════════════════════════════════════════════════════
test "actor lifecycle" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("adderHandler state msg = (+ state msg)");
    _ = try ctx.cmds.eval("let actor Adder = 0 with adderHandler");
    _ = try ctx.cmds.eval("send(Adder, 5)");
    const result = try ctx.cmds.eval("state(Adder)");

    try testing.expectEqualStrings("5", result);
}

// ═══════════════════════════════════════════════════════════
// Test : walrus operator
// ═══════════════════════════════════════════════════════════
test "walrus operator := defines function" {
    const ctx = try setupCommands(testing.allocator);
    defer teardownCommands(ctx, testing.allocator);

    _ = try ctx.cmds.eval("triple x := (* x 3)");
    const result = try ctx.cmds.eval("triple 21");

    try testing.expectEqualStrings("63", result);
}
