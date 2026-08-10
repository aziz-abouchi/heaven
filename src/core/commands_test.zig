//! Tests de non-régression pour Commands : fonctions et acteurs
const std = @import("std");
const testing = std.testing;
const expr = @import("expr");
const engine_expr = @import("engine_expr");
const matrix_bridge = @import("matrix_bridge");
const parse = @import("parse");
const transform = @import("transform");
const skill = @import("skill");
const proof_core = @import("proof_core");
const agent = @import("agent");
const math = @import("math");
const commands = @import("commands");
const platform = @import("platform");

const Store = expr.Store;
const Engine = engine_expr.Engine;
const Commands = commands.Commands;
const Language = platform.shell_parser_types.Language;

test "function definition and call persist" {
    //if (true) return error.SkipZigTest;
    // Arena : libère TOUT d'un coup à la fin, pas besoin de free chaque chaîne
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var engine = Engine{ .allocator = alloc };
    var store = Store.init(alloc);
    engine.store = &store;

    var env = engine_expr.Env.init(alloc);
    engine.env = &env;

    var bridge = matrix_bridge.MatrixBridge.init(&store, alloc);
    var parser = parse.Parser.init(&store, &engine, &env, alloc);
    var kb = transform.KnowledgeBase.init(alloc);
    var skills = skill.SkillRegistry.init(alloc);
    var qtt_env = std.StringHashMapUnmanaged(u2){};
    var proof_core_inst = proof_core.ProofCore.init(alloc);
    var agent_inst = agent.Agent.init(alloc);
    var active_theorem: ?[]const u8 = null;
    var pending_proof_request: ?[]const u8 = null;
    var math_inst = math.Math.init(&store, &engine, &bridge, &parser, alloc);

    defer env.deinit();

    var cmds = try Commands.init(
        &store,
        &engine,
        &env,
        &bridge,
        alloc,
        &parser,
        &math_inst,
        &kb,
        &skills,
        &qtt_env,
        &proof_core_inst,
        &agent_inst,
        &active_theorem,
        &pending_proof_request,
    );

    // Définir une fonction
    _ = try cmds.eval("double x = x * 2");

    // Vérifier qu'elle est enregistrée
    try testing.expect(cmds.engine.fns.get("double") != null);

    // Appeler la fonction
    const result = try cmds.eval("double 21");
    try testing.expectEqualStrings("42", result);
}

test "actor lifecycle: spawn, send, state" {
    if (true) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = Store.init(alloc);
    var engine = Engine{ .allocator = alloc };
    var env = engine_expr.Env.init(alloc);
    var bridge = matrix_bridge.MatrixBridge.init(&store, alloc);
    var parser = parse.Parser.init(&store, &engine, &env, alloc);
    var kb = transform.KnowledgeBase.init(alloc);
    var skills = skill.SkillRegistry.init(alloc);
    var qtt_env = std.StringHashMapUnmanaged(u2){};
    var proof_core_inst = proof_core.ProofCore.init(alloc);
    var agent_inst = agent.Agent.init(alloc);
    var active_theorem: ?[]const u8 = null;
    var pending_proof_request: ?[]const u8 = null;
    var math_inst = math.Math.init(&store, &engine, &bridge, &parser, alloc);

    defer env.deinit();

    var cmds = try Commands.init(
        &store,
        &engine,
        &env,
        &bridge,
        alloc,
        &parser,
        &math_inst,
        &kb,
        &skills,
        &qtt_env,
        &proof_core_inst,
        &agent_inst,
        &active_theorem,
        &pending_proof_request,
    );

    // Définir le handler
    _ = try cmds.eval("fn adderHandler(state, msg) = state + msg");
    try testing.expect(cmds.engine.fns.get("adderHandler") != null);

    // Créer l'acteur
    _ = try cmds.eval("let actor Adder = 0 with adderHandler");

    // Envoyer un message
    _ = try cmds.eval("send(Adder, 5)");

    // Vérifier l'état
    const state_result = try cmds.eval("state(Adder)");
    try testing.expectEqualStrings("5", state_result);
}

test "walrus operator := defines function correctly" {
    if (true) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var store = Store.init(alloc);
    var engine = Engine{ .allocator = alloc };
    var env = engine_expr.Env.init(alloc);
    var bridge = matrix_bridge.MatrixBridge.init(&store, alloc);
    var parser = parse.Parser.init(&store, &engine, &env, alloc);
    var kb = transform.KnowledgeBase.init(alloc);
    var skills = skill.SkillRegistry.init(alloc);
    var qtt_env = std.StringHashMapUnmanaged(u2){};
    var proof_core_inst = proof_core.ProofCore.init(alloc);
    var agent_inst = agent.Agent.init(alloc);
    var active_theorem: ?[]const u8 = null;
    var pending_proof_request: ?[]const u8 = null;
    var math_inst = math.Math.init(&store, &engine, &bridge, &parser, alloc);

    defer env.deinit();

    var cmds = try Commands.init(
        &store,
        &engine,
        &env,
        &bridge,
        alloc,
        &parser,
        &math_inst,
        &kb,
        &skills,
        &qtt_env,
        &proof_core_inst,
        &agent_inst,
        &active_theorem,
        &pending_proof_request,
    );

    // Définir avec := (devrait créer 1 pattern, pas 2)
    _ = try cmds.eval("triple x := x * 3");

    // Vérifier qu'il n'y a qu'UNE clause avec 1 pattern
    const fn_def = cmds.engine.fns.get("triple").?;
    try testing.expectEqual(@as(usize, 1), fn_def.num_clauses);

    // Vérifier l'évaluation
    const result = try cmds.eval("triple 21");
    try testing.expectEqualStrings("63", result);
}

test "parseFileWithLanguage detects language from extension" {
    // Tester la détection par extension
    try testing.expectEqual(Language.heaven, Language.fromExtension(".hvn").?);
    try testing.expectEqual(Language.pie, Language.fromExtension(".pie").?);
    try testing.expectEqual(Language.c, Language.fromExtension(".c").?);
    try testing.expectEqual(Language.zig, Language.fromExtension(".zig").?);
    try testing.expect(Language.fromExtension(".py") == null);

    // Tester toString
    try testing.expectEqualStrings("heaven", Language.heaven.toString());
    try testing.expectEqualStrings("c", Language.c.toString());
}
