//! Frontend Heaven - intégration du moteur de simplification EGraph
const std = @import("std");
const expr = @import("expr");
const hole_mod = @import("hole.zig");
const engine_expr = @import("engine_expr");
const types = @import("types");
const canon = @import("canon");
const pattern = @import("pattern");
const proof = @import("proof");
const platform = @import("platform");
const mir = @import("mir");

const simplify_engine_mod = @import("simplify_engine");
const transform_mod = @import("transform");
const egraph_mod = @import("egraph");

const matrix_bridge = @import("matrix_bridge");
const parse_mod = @import("parse");
const math_mod = @import("math");
const egraph_rewriter_mod = @import("egraph_rewriter");

const commands_mod = @import("commands");
const skill_lib = @import("skill");
const proof_core_mod = @import("proof_core");
const proof_state_mod = @import("proof_state");
const tactics_mod = @import("tactics");
const agent_mod = @import("agent");

const elab_mod = @import("elab");
const profiler_mod = @import("profiler");

const Store = expr.Store;
const Id = expr.Id;
const Sym = expr.Sym;

pub const HeavenError = error{
    ExtensionNotLowered,
    EvaluationFailed,
    OutOfMemory,
    InvalidInput,
    UnsupportedExpr,
    UnknownVariable,
    TypeMismatch,
    DependentListsNotImplemented,
    UnsupportedNode,
    TimerUnsupported,
    InvalidSyntax,
    TypeError,
    ArityMismatch,
    StackOverflow,
    NoSpaceLeft,
    NotSupported,
    InputOutput,
    SystemResources,
    IsDir,
    OperationAborted,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    WouldBlock,
    Canceled,
    AccessDenied,
    ProcessNotFound,
    LockViolation,
    Unexpected,
    FileTooBig,
    OpenError,
    NotALambda,
    InvalidPi,
    InvalidTypeAnn,
    CannotLowerFrontendTag,
    InvalidLambda,
    InvalidExpr,
    InvalidPatternId,
    InvalidBinding,
    UnsupportedDeriveOp,
    UnsupportedPowerVarExp,
    UnsupportedPowerType,
    LinearViolation,
    UnboundHole,
    UnknownHole,
} || std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine_expr.EvalError;

const MacroDef = struct {
    params: []const []const u8,
    body: Id,
};

pub const HoleInfo = struct {
    id: u32,
    /// Dernière expression racine où ce trou a été observé (pour l'affichage).
    seen_in: ?Id = null,
};

/// Handler IO par défaut (natif) : exécute réellement les effets.
/// Retourne `null` si le label n'est pas reconnu, ce qui laisse
/// `perform` retomber sur son comportement one-shot.
pub fn defaultIOHandler(
    store: *Store,
    label: []const u8,
    arg: ?expr.Id,
) engine_expr.EvalError!?expr.Id {
    if (std.mem.eql(u8, label, "Print")) {
        if (arg) |a| {
            const s = expr.toStringInfix(store, a, store.allocator) catch return null;
            defer store.allocator.free(s);
            platform.debug.print("{s}\n", .{s});
        }
        return try store.unitLit();
    }

    if (std.mem.eql(u8, label, "ReadFile")) {
        const path_id = arg orelse return null;
        const path = extractString(store, path_id) orelse return null;
        const content = platform.fs.cwd().readFileAlloc(
            store.allocator,
            path,
            1024 * 1024,
        ) catch return null;
        defer store.allocator.free(content);
        const sym = try store.interner.intern(content);
        return try store.lit(.{ .str = sym });
    }

    if (std.mem.eql(u8, label, "WriteFile")) {
        const pair_id = arg orelse return null;
        const pair_node = store.get(pair_id);
        if (pair_node.tag != .apply) return null;
        const children = store.spanSliceConst(pair_node.span_a);
        var path_id: ?expr.Id = null;
        var content_id: ?expr.Id = null;
        if (children.len == 2) {
            path_id = children[0];
            content_id = children[1];
        } else if (children.len == 3) {
            path_id = children[1];
            content_id = children[2];
        } else return null;

        const path = extractString(store, path_id.?) orelse return null;
        const content = extractString(store, content_id.?) orelse return null;

        const file = platform.fs.cwd().createFile(path, .{}) catch return null;
        defer file.close();
        file.writeAll(content) catch return null;
        return try store.unitLit();
    }

    if (std.mem.eql(u8, label, "ReadLine")) {
        const line = platform.readLine(store.allocator) catch return null;
        defer store.allocator.free(line);
        const sym = try store.interner.intern(line);
        return try store.lit(.{ .str = sym });
    }

    return null;
}

fn extractString(store: *Store, id: expr.Id) ?[]const u8 {
    if (id >= store.len()) return null;
    const node = store.get(id);
    if (node.tag != .lit) return null;
    const lit = store.lits.items[node.aux];
    if (lit != .str) return null;
    return store.interner.resolve(lit.str);
}

pub const Heaven = struct {
    allocator: std.mem.Allocator,
    store: *Store,
    env: engine_expr.Env,
    type_env: types.TypeEnv,
    engine: engine_expr.Engine,
    kb: *transform_mod.KnowledgeBase,
    simplify_eng: simplify_engine_mod.SimplifyEngine,
    proof_core: proof.ProofEnv,
    // Nouveaux champs pour les mathématiques
    bridge: *matrix_bridge.MatrixBridge,
    parser: *parse_mod.Parser,
    math: math_mod.Math,
    // Pile complète (actor/macro/fn/send) — lazy via ensureCommands
    commands: ?*commands_mod.Commands = null,
    // Dépendances pour Commands.init
    skills: ?*skill_lib.SkillRegistry = null,
    qtt_env: ?*std.StringHashMapUnmanaged(u2) = null,
    proof_core_inst: ?*proof_core_mod.ProofCore = null,
    agent_inst: ?*agent_mod.Agent = null,
    active_theorem: ?[]const u8 = null,
    pending_proof_request: ?[]const u8 = null,
    in_interp: bool = false,
    green_handler_defined: bool = false,
    hole_state: hole_mod.HoleState,
    last_root_expr: ?Id = null,

    pub fn init(allocator: std.mem.Allocator) !*Heaven {
        const self = try allocator.create(Heaven);
        errdefer allocator.destroy(self);
        const store = try allocator.create(Store);
        store.* = Store.init(allocator);
        const env = engine_expr.Env.init(allocator);
        const type_env = types.TypeEnv.init(allocator);

        // Créer le bridge et le parser (ils ne dépendent pas encore de l'engine)
        const bridge = try allocator.create(matrix_bridge.MatrixBridge);
        bridge.* = matrix_bridge.MatrixBridge.init(store, allocator);
        const parser = try allocator.create(parse_mod.Parser);
        // Le parser a besoin de l'engine, on le passera après

        // Créer une instance Heaven avec des champs temporaires
        self.* = .{
            .allocator = allocator,
            .store = store,
            .env = env,
            .type_env = type_env,
            .engine = undefined, // sera initialisé plus tard
            .kb = undefined,
            .simplify_eng = undefined,
            .proof_core = undefined,
            .pending_proof_request = null,
            .bridge = bridge,
            .parser = parser,
            .math = undefined,
            .hole_state = hole_mod.HoleState.init(allocator),
        };

        // Définir la vtable
        const heaven_vtable = engine_expr.HeavenVTable{
            .parse = parseHeavenExpr,
            .deriveId = deriveIdHeavenExpr,
            .simplify = simplifyHeavenExpr,
        };

        // Initialiser l'engine DANS self.engine (champ stable du heap)
        self.engine = engine_expr.Engine.init(allocator, store, &self.env, @ptrCast(self), &heaven_vtable);
        self.engine.io_handler = defaultIOHandler;

        // Tous les composants qui ont besoin de l'engine pointent sur self.engine,
        // pas sur une variable locale (sinon dangling pointer dès qu'init retourne).
        parser.* = parse_mod.Parser.init(store, &self.engine, &self.env, allocator);
        self.math = math_mod.Math.init(store, &self.engine, bridge, parser, allocator);

        // Initialiser kb, simplify_eng, proof_core
        const kb = try allocator.create(transform_mod.KnowledgeBase);
        kb.* = transform_mod.KnowledgeBase.init(allocator);
        self.kb = kb;

        self.simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, &self.engine, &self.env, kb, allocator);

        const proof_core = proof.ProofEnv.init(allocator);
        self.proof_core = proof_core;

        // Ajouter les règles par défaut
        try self.addDefaultRules();

        // Charger le noyau logique (bootstrap.hvn) dans le FunctionRegistry
        self.loadBootstrap();

        // Charger les wrappers IO (print, readFile, writeFile, readLine)
        // dans le FunctionRegistry de l'engine.
        self.loadStdIO();

        const ctors = [_]struct { name: []const u8, arity: u8 }{
            .{ .name = "zero", .arity = 0 },  .{ .name = "Zero", .arity = 0 },
            .{ .name = "nil", .arity = 0 },   .{ .name = "Nil", .arity = 0 },
            .{ .name = "true", .arity = 0 },  .{ .name = "True", .arity = 0 },
            .{ .name = "false", .arity = 0 }, .{ .name = "False", .arity = 0 },
            .{ .name = "unit", .arity = 0 },  .{ .name = "Unit", .arity = 0 },
            .{ .name = "succ", .arity = 1 },  .{ .name = "Succ", .arity = 1 },
        };

        for (ctors) |ctor| {
            const owned = try self.allocator.dupe(u8, ctor.name);
            const gop = try self.engine.fns.getOrPut(self.allocator, owned);
            if (gop.found_existing) {
                self.allocator.free(owned);
            } else {
                gop.value_ptr.* = .{
                    .clauses = undefined,
                    .num_clauses = 0,
                };
            }

            gop.value_ptr.ctor_arity = ctor.arity;
            //platform.dbg("[ctor-reg] {s} arity={d}\n", .{ ctor.name, ctor.arity });
        }

        //if (self.engine.fns.get("succ")) |def| {
        //platform.dbg("[ctor-verify] succ.ctor_arity = {?d}\n", .{def.ctor_arity});
        //}

        //platform.dbg("[ctor-check] fns registered:\n", .{});
        var it = self.engine.fns.iterator();
        while (it.next()) |e| {
            platform.dbg("  - '{s}' ({d} clauses)\n", .{ e.key_ptr.*, e.value_ptr.num_clauses });
        }

        return self;
    }

    fn loadBootstrap(self: *Heaven) void {
        const source = platform.fs.cwd().readFileAlloc(
            self.allocator,
            "core/bootstrap.hvn",
            64 * 1024,
        ) catch |err| {
            platform.dbg("[loadBootstrap] readFileAlloc failed: {}\n", .{err});
            return;
        };
        defer self.allocator.free(source);

        var tmp_registry = engine_expr.FunctionRegistry.init(self.allocator);
        defer tmp_registry.deinit();

        _ = elab_mod.elaborateSource(
            self.allocator,
            self.store,
            source,
            &tmp_registry,
        ) catch |err| {
            platform.dbg("[loadBootstrap] elaborateSource failed: {}\n", .{err});
            return;
        };

        platform.dbg("[loadBootstrap] elaboration ok, functions count = {d}\n", .{tmp_registry.functions.count()});

        // Transférer les clauses de tmp_registry vers self.engine.fns
        var it = tmp_registry.functions.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const def = entry.value_ptr.*;
            var i: u8 = 0;
            while (i < def.num_clauses) : (i += 1) {
                const clause = def.clauses[i];
                self.registerClause(name, clause.patterns[0..clause.num_patterns], clause.body) catch {};
            }
        }

        platform.dbg("[loadBootstrap] after transfer, engine.fns count = {d}\n", .{self.engine.fns.count()});

        // Pont majuscule → minuscule : Add/Mul/Zero/Succ → add/mul/zero/succ
        const aliases = [_][2][]const u8{
            .{ "Add", "add" },
            .{ "Mul", "mul" },
            .{ "Zero", "zero" },
            .{ "Succ", "succ" },
        };
        for (aliases) |pair| {
            if (self.engine.fns.getPtr(pair[1])) |def| {
                var i: u8 = 0;
                while (i < def.num_clauses) : (i += 1) {
                    const clause = def.clauses[i];
                    self.registerClause(
                        pair[0],
                        clause.patterns[0..clause.num_patterns],
                        clause.body,
                    ) catch {};
                }
            }
        }
    }

    /// Charge `core/io.hvn` dans le FunctionRegistry de l'engine,
    /// en évaluant chaque ligne via `evalEquation`. La fonction
    /// `print`, `readFile`, etc. deviennent ainsi accessibles au REPL.
    fn loadStdIO(self: *Heaven) void {
        const source = platform.fs.cwd().readFileAlloc(
            self.allocator,
            "core/io.hvn",
            64 * 1024,
        ) catch |err| {
            platform.dbg("[loadStdIO] readFileAlloc failed: {}\n", .{err});
            return;
        };
        defer self.allocator.free(source);

        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '#') continue;
            if (std.mem.startsWith(u8, trimmed, "--")) continue;
            if (std.mem.startsWith(u8, trimmed, ";;")) continue;

            const result = self.eval(trimmed) catch |err| {
                platform.dbg("[loadStdIO] '{s}' failed: {}\n", .{ trimmed, err });
                continue;
            };
            self.allocator.free(result);
        }
    }

    pub fn deinit(self: *Heaven) void {
        self.store.deinit();
        self.allocator.destroy(self.store);
        self.env.deinit();
        self.engine.deinit();
        self.type_env.deinit();
        self.kb.deinit(self.allocator);
        self.allocator.destroy(self.kb);
        self.proof_core.deinit();
        if (self.pending_proof_request) |req| self.allocator.free(req);

        // Libérer le bridge et le parser
        self.bridge.deinit(); // si MatrixBridge a un deinit, sinon self.bridge.* n'a pas besoin
        self.allocator.destroy(self.bridge);
        self.parser.deinit(); // si Parser a un deinit
        self.allocator.destroy(self.parser);
        // math n'a pas de ressources gérées par elle-même, mais on pourrait l'appeler si nécessaire
        if (self.commands) |c| {
            c.deinit();
            self.allocator.destroy(c);
        }
        if (self.skills) |s| {
            s.deinit();
            self.allocator.destroy(s);
        }
        if (self.qtt_env) |q| {
            q.deinit(self.allocator);
            self.allocator.destroy(q);
        }
        if (self.proof_core_inst) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
        if (self.agent_inst) |a| {
            a.deinit();
            self.allocator.destroy(a);
        }

        self.hole_state.deinit();
    }

    pub fn ensureInit(self: *Heaven) void {
        _ = self;
    }

    pub fn registerClause(self: *Heaven, name: []const u8, patterns: []const Id, body: Id) !void {
        const owned_key = try self.engine.allocator.dupe(u8, name);
        const result = try self.engine.fns.getOrPut(self.engine.allocator, owned_key);
        if (result.found_existing) {
            self.engine.allocator.free(owned_key); // ← clé redondante, getOrPut garde l'existante
        } else {
            result.value_ptr.* = .{ .clauses = undefined, .num_clauses = 0 };
        }
        result.value_ptr.addClause(patterns, body);
    }

    pub fn eval(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "");

        // ─── Formes spéciales du langage : type / green ───
        // Doivent être routées AVANT l'évaluation générique, sinon elles
        // tombent dans l'evaluator qui ne les connaît pas et renvoie l'entrée brute.
        if (std.mem.startsWith(u8, trimmed, "type ")) {
            const inner = std.mem.trim(u8, trimmed["type ".len..], " \t");
            return self.evalTypeExpr(inner);
        }
        if (std.mem.startsWith(u8, trimmed, "green ")) {
            const inner = std.mem.trim(u8, trimmed["green ".len..], " \t");
            return self.evalGreenExpr(inner);
        }

        // ─── Commandes REPL à ne PAS évaluer comme des expressions ───
        const is_command = std.mem.startsWith(u8, trimmed, "type ") or
            std.mem.startsWith(u8, trimmed, "green ") or
            std.mem.startsWith(u8, trimmed, "help") or
            std.mem.startsWith(u8, trimmed, "stats") or
            std.mem.startsWith(u8, trimmed, "theorems") or
            std.mem.startsWith(u8, trimmed, "axioms") or
            std.mem.startsWith(u8, trimmed, "meta") or
            std.mem.startsWith(u8, trimmed, "rules");

        if (is_command) {
            // Le shell va traiter ces commandes ; on ne les évalue pas ici.
            return self.allocator.dupe(u8, trimmed);
        }

        // Théorèmes / preuves / axiomes → chemin dédié (elab.zig + ProofCore)
        if (std.mem.startsWith(u8, trimmed, "theorem ")) {
            return self.evalTheorem(trimmed["theorem ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "prove ")) {
            return self.evalProve(trimmed["prove ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "skill ")) {
            return self.evalSkill(trimmed["skill ".len..]);
        }

        // ─── let <qtt?> <name> = <val> in <body> (natif, top-level) ───
        // Converti en S-expr puis routé vers interpForAssert (même chemin
        // que (let x 5 x) qui fonctionne déjà).
        if (std.mem.startsWith(u8, trimmed, "let ") and
            std.mem.indexOf(u8, trimmed, " in ") != null and
            std.mem.indexOf(u8, trimmed, ":=") == null)
        {
            const after_let = trimmed["let ".len..];
            var qtt_kw: ?[]const u8 = null;
            var rest_native = after_let;
            const kws = [_][]const u8{ "linear", "erased", "many" };
            for (kws) |kw| {
                if (std.mem.startsWith(u8, rest_native, kw) and
                    rest_native.len > kw.len and
                    (rest_native[kw.len] == ' ' or rest_native[kw.len] == '\t'))
                {
                    const after = std.mem.trimLeft(u8, rest_native[kw.len..], " \t");
                    if (after.len > 0 and after[0] != '=') {
                        qtt_kw = kw;
                        rest_native = after;
                        break;
                    }
                }
            }

            if (std.mem.indexOf(u8, rest_native, " in ")) |in_pos| {
                const binding = std.mem.trim(u8, rest_native[0..in_pos], " \t");
                const body = std.mem.trim(u8, rest_native[in_pos + 4 ..], " \t");

                if (std.mem.indexOfScalar(u8, binding, '=')) |eq| {
                    const name = std.mem.trim(u8, binding[0..eq], " \t:");
                    const val = std.mem.trim(u8, binding[eq + 1 ..], " \t");

                    var buf = std.ArrayListUnmanaged(u8){};
                    defer buf.deinit(self.allocator);
                    const head = if (qtt_kw) |kw|
                        try std.fmt.allocPrint(self.allocator, "let-{s}", .{kw})
                    else
                        try self.allocator.dupe(u8, "let");
                    defer self.allocator.free(head);
                    try buf.writer(self.allocator).print("({s} {s} {s} {s})", .{ head, name, val, body });

                    if (self.parseExpression(buf.items)) |id| {
                        // (à faire pour chaque parse réussi)
                        self.last_root_expr = id;
                        const result = self.interpForAssert(id) catch id;
                        return try expr.toStringInfix(self.store, result, self.allocator);
                    } else |err| switch (err) {
                        error.LinearViolation => return std.fmt.allocPrint(self.allocator, "linear violation: '{s}' declared {s}, used wrong number of times", .{ name, qtt_kw orelse "many" }),
                        else => return self.allocator.dupe(u8, "syntax error in let"),
                    }
                }
            }
        }

        // Les lignes mécanismes (actor/macro/fn/send/state) → Commands
        const is_mechanism = std.mem.startsWith(u8, trimmed, "let actor ") or
            std.mem.startsWith(u8, trimmed, "let macro ") or
            std.mem.startsWith(u8, trimmed, "fn ") or
            std.mem.startsWith(u8, trimmed, "send(") or
            std.mem.startsWith(u8, trimmed, "state(") or
            std.mem.startsWith(u8, trimmed, "spawn(") or
            std.mem.startsWith(u8, trimmed, "let ");

        if (is_mechanism) {
            if (self.ensureCommands()) |cmds| {
                return cmds.eval(src) catch |err| {
                    return switch (err) {
                        error.OutOfMemory => HeavenError.OutOfMemory,
                        else => HeavenError.EvaluationFailed,
                    };
                };
            }
            return self.allocator.dupe(u8, trimmed);
        }

        // Assertions sémantiques dans le REPL
        if (std.mem.startsWith(u8, trimmed, "(test ") or
            std.mem.startsWith(u8, trimmed, "(assert_eq ") or
            std.mem.startsWith(u8, trimmed, "(assert_err "))
        {
            return self.evalAssertion(trimmed);
        }

        // Assertions natives :
        //   test "name": lhs == rhs
        //   test "name": assert_err expr
        //   assert_eq lhs == rhs
        //   assert_err expr
        if (std.mem.startsWith(u8, trimmed, "test \"") or
            std.mem.startsWith(u8, trimmed, "assert_eq ") or
            std.mem.startsWith(u8, trimmed, "assert_err "))
        {
            return self.evalAssertionNative(trimmed);
        }

        // ROUTING S-EXPR : (let ...) / (lambda ...) / (+ 1 2) / toute S-expr pure
        if (trimmed.len > 0 and trimmed[0] == '(') {
            // let/lambda → interpForAssert (engine ne gère pas bind au top-level)
            if (std.mem.indexOf(u8, trimmed, "let ") != null or
                std.mem.indexOf(u8, trimmed, "lambda") != null)
            {
                if (self.bridge.importExpr(trimmed)) |id| {
                    const result = self.interpForAssert(id) catch id;
                    return try expr.toStringInfix(self.store, result, self.allocator);
                } else |_| {}
            }
            // Autres S-expr : parse + engine.eval direct
            if (self.bridge.importExpr(trimmed)) |id| {
                self.engine.fuel = 1_000_000;
                const evaluated = self.engine.eval(id) catch id;
                const result_str = try expr.toStringInfix(self.store, evaluated, self.allocator);
                return result_str;
            } else |_| {}
        }

        if (std.mem.startsWith(u8, trimmed, "(relation ")) {
            const inner = trimmed["(relation ".len .. trimmed.len - 1];
            return self.addRelation(inner);
        }

        if (std.mem.startsWith(u8, trimmed, "simplify ")) {
            const expr_str = std.mem.trim(u8, trimmed["simplify ".len..], " ");
            return self.simplify(expr_str);
        }

        if (std.mem.startsWith(u8, trimmed, "(simplify ")) {
            const inner = trimmed["(simplify ".len .. trimmed.len - 1];
            return self.simplify(inner);
        }

        if (std.mem.startsWith(u8, trimmed, "derive ")) {
            const rest = std.mem.trim(u8, trimmed["derive ".len..], " ");
            return self.derive(rest, "x");
        }
        if (std.mem.startsWith(u8, trimmed, "integrate ")) {
            const rest = std.mem.trim(u8, trimmed["integrate ".len..], " ");
            return self.integrate(rest, "x");
        }
        if (std.mem.startsWith(u8, trimmed, "solve ")) {
            const rest = std.mem.trim(u8, trimmed["solve ".len..], " ");
            return self.solve(rest, "x");
        }
        if (std.mem.startsWith(u8, trimmed, "expand ")) {
            const rest = std.mem.trim(u8, trimmed["expand ".len..], " ");
            return self.expand(rest);
        }
        if (std.mem.startsWith(u8, trimmed, "plot ")) {
            const rest = std.mem.trim(u8, trimmed["plot ".len..], " ");
            return self.plot(rest, "x");
        }
        if (std.mem.eql(u8, trimmed, "meta") or std.mem.eql(u8, trimmed, "rules")) {
            return self.listRules();
        }

        // ─── Formes spéciales : type <expr> ───
        if (std.mem.startsWith(u8, trimmed, "type ")) {
            const inner = std.mem.trim(u8, trimmed["type ".len..], " ");
            return self.evalTypeExpr(inner);
        }

        // ─── Formes spéciales : green <expr> ───
        if (std.mem.startsWith(u8, trimmed, "green ")) {
            const inner = std.mem.trim(u8, trimmed["green ".len..], " ");
            return self.evalGreenExpr(inner);
        }

        // ─── Déclaration de type : data Name params = C1 | C2 args | ... ───
        if (std.mem.startsWith(u8, trimmed, "data ")) {
            return self.evalDataDecl(trimmed["data ".len..]);
        }

        // ─── DÉFINITION DE FONCTION (syntaxe équationnelle) ───
        // Vérifier d'abord := (walrus) avant = pour éviter la confusion
        if (std.mem.indexOf(u8, trimmed, ":=")) |walrus_pos| {
            // := trouvé : convertir en = et traiter comme équation
            const before = trimmed[0..walrus_pos];
            const after = trimmed[walrus_pos + 2 ..];
            const converted = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ before, after });
            defer self.allocator.free(converted);
            // Re-parser la string convertie
            if (std.mem.indexOfScalar(u8, converted, '=')) |eq_pos| {
                const lhs = std.mem.trim(u8, converted[0..eq_pos], " ");
                const rhs = std.mem.trim(u8, converted[eq_pos + 1 ..], " ");
                if (!std.mem.startsWith(u8, lhs, "(") and lhs.len > 0 and rhs.len > 0) {
                    return self.evalEquation(lhs, rhs);
                }
            }
        } else if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            // Pas de :=, chercher = simple
            // Vérifier que ce n'est pas == ou !=
            if (eq_pos + 1 < trimmed.len and trimmed[eq_pos + 1] == '=') {
                // C'est ==, pas une définition
            } else {
                const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
                const rhs = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " ");
                if (!std.mem.startsWith(u8, lhs, "(") and lhs.len > 0 and rhs.len > 0) {
                    return self.evalEquation(lhs, rhs);
                }
            }
        }

        if (std.mem.startsWith(u8, trimmed, "latex ")) {
            const inner = std.mem.trim(u8, trimmed["latex ".len..], " \t");
            if (self.ensureCommands()) |cmds| {
                return cmds.evalLatex(inner) catch |err| switch (err) {
                    error.OutOfMemory => HeavenError.OutOfMemory,
                    else => HeavenError.EvaluationFailed,
                };
            }
            return self.allocator.dupe(u8, "✗ commands unavailable");
        }

        // ─── ÉVALUATION GÉNÉRIQUE (infixe + application) ───
        // 1. Essayer la conversion infixe → S‑expression (opérateurs binaires)
        if (expr.nativeToSExpr(trimmed, self.allocator)) |sexpr| {
            defer self.allocator.free(sexpr);
            if (sexpr.len > 0 and sexpr[0] == '(') {
                const id = try self.parseExpression(sexpr);
                // Utiliser engine.eval pour l'évaluation
                const evaluated = try self.engine.eval(id);
                return expr.toStringInfix(self.store, evaluated, self.allocator);
            }
        } else |_| {}

        // 2. Sinon, tenter comme une application de fonction (nom arg1 arg2 ...)
        var tokens = std.ArrayListUnmanaged([]const u8){};
        defer tokens.deinit(self.allocator);
        var start: usize = 0;
        var depth: usize = 0;
        var in_token = false;
        for (trimmed, 0..) |c, i| {
            if (c == '(') {
                if (depth == 0 and !in_token) {
                    start = i;
                    in_token = true;
                }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, trimmed[start .. i + 1]);
                    in_token = false;
                    start = i + 1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, trimmed[start..i]);
                    in_token = false;
                }
                start = i + 1;
            } else if (depth == 0 and !in_token) {
                start = i;
                in_token = true;
            }
        }
        if (in_token) try tokens.append(self.allocator, trimmed[start..]);

        if (tokens.items.len >= 2) {
            const func_name = tokens.items[0];
            const ops = [_][]const u8{ "+", "-", "*", "/", "^", "%", "==", "!=", "<", ">", "<=", ">=" };
            var is_op = false;
            for (ops) |op| {
                if (std.mem.eql(u8, func_name, op)) {
                    is_op = true;
                    break;
                }
            }
            if (!is_op) {
                var sexpr = std.ArrayListUnmanaged(u8){};
                defer sexpr.deinit(self.allocator);
                try sexpr.append(self.allocator, '(');
                try sexpr.appendSlice(self.allocator, func_name);
                for (tokens.items[1..]) |arg| {
                    try sexpr.append(self.allocator, ' ');
                    try sexpr.appendSlice(self.allocator, arg);
                }
                try sexpr.append(self.allocator, ')');
                const s = try sexpr.toOwnedSlice(self.allocator);
                defer self.allocator.free(s);
                const id = try self.parseExpression(s);
                // Utiliser engine.eval pour l'évaluation
                const evaluated = try self.engine.eval(id);
                return expr.toStringInfix(self.store, evaluated, self.allocator);
            }
        }
        // Atome nu : lookup dans l'env avant de retourner tel quel.
        // `x` doit résoudre vers la valeur liée par `let x := 5`.
        if (trimmed.len > 0 and trimmed[0] != '(' and
            std.mem.indexOfScalar(u8, trimmed, ' ') == null)
        {
            if (self.store.interner.lookup(trimmed)) |sym| {
                if (self.env.get(sym)) |val| {
                    return expr.toStringInfix(self.store, val, self.allocator);
                }
            }
        }
        return self.allocator.dupe(u8, trimmed);
    }

    fn evalDataDecl(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const eq_pos = std.mem.indexOfScalar(u8, src, '=') orelse
            return self.allocator.dupe(u8, "syntax error in data");
        const rhs = std.mem.trim(u8, src[eq_pos + 1 ..], " \t");

        var it = std.mem.splitScalar(u8, rhs, '|');
        var count: usize = 0;
        while (it.next()) |raw| {
            const ctor = std.mem.trim(u8, raw, " \t");
            if (ctor.len == 0) continue;

            // Nom = premier token
            var name_end: usize = 0;
            while (name_end < ctor.len and ctor[name_end] != ' ' and ctor[name_end] != '\t') : (name_end += 1) {}
            const name = ctor[0..name_end];

            // Compter les args en respectant les parenthèses
            var arity: u8 = 0;
            var i = name_end;
            while (i < ctor.len) {
                while (i < ctor.len and (ctor[i] == ' ' or ctor[i] == '\t')) : (i += 1) {}
                if (i >= ctor.len) break;
                if (ctor[i] == '(') {
                    var depth: usize = 1;
                    i += 1;
                    while (i < ctor.len and depth > 0) : (i += 1) {
                        if (ctor[i] == '(') depth += 1 else if (ctor[i] == ')') depth -= 1;
                    }
                } else {
                    while (i < ctor.len and ctor[i] != ' ' and ctor[i] != '\t') : (i += 1) {}
                }
                arity += 1;
            }

            const owned = try self.allocator.dupe(u8, name);
            const gop = try self.engine.fns.getOrPut(self.allocator, owned);
            if (gop.found_existing) {
                self.allocator.free(owned);
            } else {
                gop.value_ptr.* = .{ .clauses = undefined, .num_clauses = 0 };
            }
            gop.value_ptr.ctor_arity = arity;
            count += 1;
        }
        return std.fmt.allocPrint(self.allocator, "✓ data type registered ({d} constructors)", .{count});
    }

    fn evalEquation(self: *Heaven, lhs: []const u8, rhs: []const u8) HeavenError![]u8 {
        // Tokeniser le LHS avec gestion des parenthèses
        var tokens = std.ArrayListUnmanaged([]const u8){};
        defer tokens.deinit(self.allocator);

        var start: usize = 0;
        var depth: usize = 0;
        var in_token = false;
        for (lhs, 0..) |c, i| {
            if (c == '(') {
                if (depth == 0 and !in_token) {
                    start = i;
                    in_token = true;
                }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, lhs[start .. i + 1]);
                    in_token = false;
                    start = i + 1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, lhs[start..i]);
                    in_token = false;
                }
                start = i + 1;
            } else if (depth == 0 and !in_token) {
                start = i;
                in_token = true;
            }
        }
        if (in_token) try tokens.append(self.allocator, lhs[start..]);

        if (tokens.items.len == 0) return error.InvalidSyntax;

        const name = tokens.items[0];
        var patterns = std.ArrayListUnmanaged(Id){};
        defer patterns.deinit(self.allocator);

        for (tokens.items[1..]) |tok| {
            const id = try self.parseExpression(tok);
            try patterns.append(self.allocator, id);
        }

        const body = try self.parseExpression(rhs);
        try self.registerClause(name, patterns.items, body);

        return std.fmt.allocPrint(self.allocator, "✓ clause enregistrée pour '{s}'", .{name});
    }

    fn addRelation(self: *Heaven, input: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, input, " ");
        const arrow_pos = std.mem.indexOf(u8, trimmed, "=>") orelse
            return self.allocator.dupe(u8, "syntax error: expected lhs => rhs");
        const lhs_str = std.mem.trim(u8, trimmed[0..arrow_pos], " ");
        const rhs_str = std.mem.trim(u8, trimmed[arrow_pos + 2 ..], " ");

        const lhs = try self.parseExpression(lhs_str);
        const rhs = try self.parseExpression(rhs_str);

        const lhs_canon = try canon.canonicalize(self.store, self.allocator, lhs);
        const rhs_canon = try canon.canonicalize(self.store, self.allocator, rhs);

        const rule_id = try self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
        try self.kb.rules.append(self.allocator, rule_id);
        return self.allocator.dupe(u8, "✓ rule added");
    }

    pub fn simplify(self: *Heaven, input: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "");

        const raw_id = try self.parseExpression(trimmed);
        const id = try self.ensureLowered(raw_id);

        // Pipeline : simplifyBasic → E-Graph → simplifyBasic
        const after_basic = try self.math.simplifyBasic(id);
        const after_egraph = try self.simplify_eng.simplifyWithEGraph(after_basic, null, null);
        const final = try self.math.simplifyBasic(after_egraph);

        return expr.toStringInfix(self.store, final, self.allocator);
    }

    // ─── Parsing robuste ───
    pub fn importExpr(self: *Heaven, src: []const u8) HeavenError!Id {
        return self.parseExpression(src);
    }

    pub fn parseExpression(self: *Heaven, input: []const u8) HeavenError!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidInput;

        // ─── Trou : `_` seul ───
        if (std.mem.eql(u8, trimmed, "_")) {
            const hole_node = try self.freshHole();
            self.last_root_expr = hole_node;
            return hole_node;
        }

        // ─── Syntaxe courte lambda : `λx.body` ou `\x.body` ───
        // `λ` en UTF-8 fait 2 bytes (0xCE 0xBB) — comparer avec startsWith,
        // JAMAIS avec `trimmed[0] == 'λ'` (Zig interprète 'λ' comme codepoint u21,
        // pas comme byte).
        const is_unicode_lambda = std.mem.startsWith(u8, trimmed, "λ");
        const is_ascii_lambda = trimmed.len > 0 and trimmed[0] == '\\';
        if (is_unicode_lambda or is_ascii_lambda) {
            const prefix_len: usize = if (is_unicode_lambda) 2 else 1;
            const dot_pos = std.mem.indexOfScalar(u8, trimmed, '.') orelse
                return error.InvalidLambda;
            if (dot_pos <= prefix_len) return error.InvalidLambda;
            const param = trimmed[prefix_len..dot_pos];
            const body_str = std.mem.trim(u8, trimmed[dot_pos + 1 ..], " \t");
            if (param.len == 0 or body_str.len == 0) return error.InvalidLambda;
            const body_id = try self.parseExpression(body_str);
            return try self.store.lambdaNative(&.{param}, body_id);
        }

        // Unicode : x² → x^2
        if (expr.containsSuperscript(trimmed)) {
            const normalized = try expr.normalizeUnicodePowers(trimmed, self.allocator);
            defer self.allocator.free(normalized);
            return self.parseExpression(normalized);
        }

        // SYNTAXE NATIVE : tout ce qui ne commence pas par '('
        if (trimmed[0] != '(') {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const sexpr = expr.nativeToSExpr(trimmed, arena.allocator()) catch {
                // Fallback : "func arg1 arg2" non parsable en infixe → wrapper S-expr
                if (std.mem.indexOfScalar(u8, trimmed, ' ') != null) {
                    const wrapped = std.fmt.allocPrint(self.allocator, "({s})", .{trimmed}) catch
                        return self.store.sym(trimmed);
                    defer self.allocator.free(wrapped);
                    return self.parseExpression(wrapped) catch self.store.sym(trimmed);
                }
                return self.store.sym(trimmed);
            };
            if (sexpr.len > 0 and sexpr[0] == '(') {
                // Forme composée → re-parser en Lisp (récursion sûre)
                const owned = try self.allocator.dupe(u8, sexpr);
                defer self.allocator.free(owned);
                return self.parseExpression(owned);
            }
            // Atome (nombre, identifiant, string) — interner duplique la chaîne ✓
            if (std.fmt.parseInt(i64, sexpr, 10)) |val| {
                return self.store.int(val);
            } else |_| {}

            // Flottant : "3.14"
            if (std.fmt.parseFloat(f64, sexpr)) |val| {
                return self.store.float(val);
            } else |_| {}

            // Booléens : "true" / "false"
            if (std.mem.eql(u8, sexpr, "true")) return self.store.boolean(true);
            if (std.mem.eql(u8, sexpr, "false")) return self.store.boolean(false);

            // Chaîne : "..."
            if (sexpr.len >= 2 and sexpr[0] == '"' and sexpr[sexpr.len - 1] == '"') {
                const inner = sexpr[1 .. sexpr.len - 1];
                const s = try self.store.interner.intern(inner);
                return self.store.lit(.{ .str = s });
            }

            return self.store.sym(sexpr);
        }

        // 1. Entier
        if (std.fmt.parseInt(i64, trimmed, 10)) |val| {
            return self.store.int(val);
        } else |_| {}

        // 2. Si commence par '(' → S-expression
        if (trimmed[0] == '(') {
            var depth: usize = 0;
            var i: usize = 0;
            while (i < trimmed.len) {
                if (trimmed[i] == '(') {
                    depth += 1;
                } else if (trimmed[i] == ')') {
                    depth -= 1;
                    if (depth == 0) break;
                }
                i += 1;
            }
            if (i >= trimmed.len or trimmed[i] != ')') return error.InvalidSyntax;

            const trailing = std.mem.trim(u8, trimmed[i + 1 ..], " \t");
            if (trailing.len > 0) {
                // Cas opérateur infixe après parenthèses : (X)^Y, (X)+Y, ...
                // → déléguer au Pratt parser natif qui gère la précédence.
                const op_chars = "^*+-/<>=";
                if (std.mem.indexOfScalar(u8, op_chars, trailing[0]) != null) {
                    var arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer arena.deinit();
                    const sexpr = expr.nativeToSExpr(trimmed, arena.allocator()) catch {
                        return error.InvalidSyntax;
                    };
                    const owned = try self.allocator.dupe(u8, sexpr);
                    defer self.allocator.free(owned);
                    return self.parseExpression(owned);
                }

                // Fallback : juxtaposition ((X) Y Z) → groupement
                const wrapped = try std.fmt.allocPrint(self.allocator, "({s} {s})", .{ trimmed[0 .. i + 1], trailing });
                defer self.allocator.free(wrapped);
                return self.parseExpression(wrapped);
            }

            const inner = trimmed[1..i];
            return self.parseSExpr(inner);
        }

        // 3. NOUVEAU : Détecter les opérateurs infixes (^, +, -, *, /)
        // Priorité : ^ > * = / > + = -

        // Chercher ^ (puissance) - priorité la plus haute
        if (std.mem.indexOfScalar(u8, trimmed, '^')) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const pow_sym = try self.store.sym("^");
                return self.store.apply(pow_sym, &.{ lhs, rhs });
            }
        }

        // Chercher + ou - (binaire) - priorité la plus basse
        // Attention : ne pas confondre avec - unaire (ex: -5)
        var depth: usize = 0;
        var plus_pos: ?usize = null;
        var minus_pos: ?usize = null;
        var i: usize = 0;
        while (i < trimmed.len) {
            switch (trimmed[i]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '+', '-' => {
                    if (depth == 0 and i > 0) {
                        // Pas en début de chaîne (sinon c'est unaire)
                        if (trimmed[i] == '+') plus_pos = i else minus_pos = i;
                    }
                },
                else => {},
            }
            i += 1;
        }

        // Préférer + ou - le plus à droite (associativité à gauche)
        if (minus_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("-");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }
        if (plus_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("+");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }

        // Chercher * ou /
        depth = 0;
        i = 0;
        var mul_pos: ?usize = null;
        var div_pos: ?usize = null;
        while (i < trimmed.len) {
            switch (trimmed[i]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '*' => {
                    if (depth == 0) mul_pos = i;
                },
                '/' => {
                    if (depth == 0) div_pos = i;
                },
                else => {},
            }
            i += 1;
        }

        if (div_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("/");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }
        if (mul_pos) |pos| {
            const lhs_str = std.mem.trim(u8, trimmed[0..pos], " ");
            const rhs_str = std.mem.trim(u8, trimmed[pos + 1 ..], " ");
            if (lhs_str.len > 0 and rhs_str.len > 0) {
                const lhs = try self.parseExpression(lhs_str);
                const rhs = try self.parseExpression(rhs_str);
                const op_sym = try self.store.sym("*");
                return self.store.apply(op_sym, &.{ lhs, rhs });
            }
        }

        // 4. Sinon → symbole simple
        return self.store.sym(trimmed);
    }

    fn parseSExpr(self: *Heaven, inner: []const u8) HeavenError!Id {
        var tokens: std.ArrayListUnmanaged([]const u8) = .{};
        defer tokens.deinit(self.allocator);

        var depth: usize = 0;
        var start: usize = 0;
        var in_token = false;
        var in_str = false;
        for (inner, 0..) |ch, idx| {
            if (in_str) {
                if (ch == '"') in_str = false;
                continue;
            }
            switch (ch) {
                '"' => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                    in_str = true;
                },
                '(' => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                    depth += 1;
                },
                ')' => {
                    depth -= 1;
                    if (depth == 0 and in_token) {
                        try tokens.append(self.allocator, inner[start .. idx + 1]);
                        in_token = false;
                        start = idx + 1;
                    }
                },
                ' ' => {
                    if (depth == 0 and in_token) {
                        try tokens.append(self.allocator, inner[start..idx]);
                        in_token = false;
                        start = idx + 1;
                    }
                },
                else => {
                    if (depth == 0 and !in_token) {
                        start = idx;
                        in_token = true;
                    }
                },
            }
        }
        if (in_token and depth == 0) {
            try tokens.append(self.allocator, inner[start..]);
        }

        if (tokens.items.len == 0) return error.InvalidSyntax;

        const first = tokens.items[0];
        //platform.dbg("[parseSExpr] first token: '{s}' (len={d})\n", .{ first, first.len });

        // Un trou en position de tête : pas une application.
        if (std.mem.eql(u8, first, "_")) {
            if (tokens.items.len == 1) return self.freshHole();
            return error.InvalidSyntax;
        }

        // DÉTECTION INFIXE : un opérateur au milieu → syntaxe infixe
        // (x + 3) → apply(x, [+, 3]) serait faux → déléguer au parser natif
        if (tokens.items.len > 1) {
            for (tokens.items[1..]) |tok| {
                if (isInfixOp(tok)) {
                    var arena = std.heap.ArenaAllocator.init(self.allocator);
                    defer arena.deinit();
                    const sexpr = expr.nativeToSExpr(inner, arena.allocator()) catch {
                        return error.InvalidSyntax;
                    };
                    const owned = try self.allocator.dupe(u8, sexpr);
                    defer self.allocator.free(owned);
                    return self.parseExpression(owned);
                }
            }
        }

        // Cas 1 : le premier token est une sous‑expression entre parenthèses
        if (first.len > 0 and first[0] == '(') {
            const func_id = try self.parseExpression(first);
            var args = std.ArrayListUnmanaged(Id){};
            defer args.deinit(self.allocator);
            for (tokens.items[1..]) |arg_tok| {
                if (std.mem.eql(u8, arg_tok, "_")) {
                    try args.append(self.allocator, try self.freshHole());
                } else {
                    try args.append(self.allocator, try self.parseExpression(arg_tok));
                }
            }
            return self.store.apply(func_id, args.items);
        }

        // ─── Cas "λx.body" en un seul token (pas d'espace après λ) ───
        const is_unicode_lambda = std.mem.startsWith(u8, first, "λ");
        const is_ascii_lambda = first.len > 0 and first[0] == '\\';
        if ((is_unicode_lambda or is_ascii_lambda) and tokens.items.len == 1) {
            if (std.mem.indexOfScalar(u8, first, '.')) |dot_pos| {
                const prefix_len: usize = if (is_unicode_lambda) 2 else 1;
                if (dot_pos > prefix_len) {
                    const param = first[prefix_len..dot_pos];
                    const body_str = first[dot_pos + 1 ..];
                    if (param.len > 0 and body_str.len > 0) {
                        const body_id = try self.parseExpression(body_str);
                        return try self.store.lambdaNative(&.{param}, body_id);
                    }
                }
            }
        }

        // Cas 2 : lambda
        const is_lambda = std.mem.eql(u8, first, "λ") or
            std.mem.eql(u8, first, "\\") or
            std.mem.eql(u8, first, "lambda") or
            std.mem.eql(u8, first, "Lambda");

        if (is_lambda) {
            platform.dbg("[parseSExpr] detected lambda\n", .{});
            if (tokens.items.len < 3) return error.InvalidLambda;
            const body_str = tokens.items[tokens.items.len - 1];
            const body_id = try self.parseExpression(body_str);
            const params = tokens.items[1 .. tokens.items.len - 1];
            if (params.len == 0) return error.InvalidLambda;
            const param_name = params[0];
            const result = try self.store.lambdaNative(&.{param_name}, body_id);
            platform.dbg("[parseSExpr] created lambda id = {d}\n", .{result});
            return result;
        }

        // QTT : let avec multiplicité
        //   (let-linear x v b)       — 1 usage exact
        //   (let-erased x v b)       — 0 usage
        //   (let-many   x v b)       — aucune contrainte
        //   (let linear x = v in b)  — forme "native" injectée en S-expr
        //   (let erased x = v in b)
        //   (let many   x = v in b)
        {
            var kw: ?[]const u8 = null;
            var qtt_name: []const u8 = "";
            var qtt_val: []const u8 = "";
            var qtt_body: ?expr.Id = null;

            if (std.mem.eql(u8, first, "let-linear") and tokens.items.len == 4) {
                kw = "linear";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-erased") and tokens.items.len == 4) {
                kw = "erased";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-many") and tokens.items.len == 4) {
                kw = "many";
                qtt_name = tokens.items[1];
                qtt_val = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let") and tokens.items.len >= 7) {
                const k = tokens.items[1];
                const is_kw = std.mem.eql(u8, k, "linear") or std.mem.eql(u8, k, "erased") or std.mem.eql(u8, k, "many");
                if (is_kw and std.mem.eql(u8, tokens.items[3], "=") and std.mem.eql(u8, tokens.items[5], "in")) {
                    kw = k;
                    qtt_name = tokens.items[2];
                    qtt_val = tokens.items[4];

                    var body_buf = std.ArrayListUnmanaged(u8){};
                    defer body_buf.deinit(self.allocator);
                    for (tokens.items[6..], 0..) |t, i| {
                        if (i > 0) try body_buf.append(self.allocator, ' ');
                        try body_buf.appendSlice(self.allocator, t);
                    }
                    qtt_body = try self.parseExpression(body_buf.items);
                }
            }

            if (kw) |k| {
                const b = qtt_body.?;
                const uses = expr.countSymUses(self.store, b, qtt_name);

                const ok = if (std.mem.eql(u8, k, "linear"))
                    uses == 1
                else if (std.mem.eql(u8, k, "erased"))
                    uses == 0
                else
                    true; // many : aucune contrainte

                if (!ok) return error.LinearViolation;

                const val_id = try self.parseExpression(qtt_val);
                const name_sym = try self.store.interner.intern(qtt_name);
                // Représentation Core : bind(name, val, body)
                return try self.store.bindSymWithBody(name_sym, val_id, b);
            }
        }

        // Cas 3 : application normale
        const func_id = try self.store.sym(first);
        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);
        for (tokens.items[1..]) |arg_tok| {
            if (std.mem.eql(u8, arg_tok, "_")) {
                try args.append(self.allocator, try self.freshHole());
            } else {
                try args.append(self.allocator, try self.parseExpression(arg_tok));
            }
        }
        return self.store.apply(func_id, args.items);
    }

    // ─── Helpers ───
    fn ensureLowered(self: *Heaven, id: Id) HeavenError!Id {
        var current = id;
        var iterations: u32 = 0;
        while (iterations < 10) : (iterations += 1) {
            const node = self.store.get(current);
            if (node.tag.isPrimitive()) return current;
            current = try self.store.lowerRec(current);
        }
        return error.UnsupportedExpr;
    }

    // Stubs pour les autres méthodes (inchangés)
    pub fn typeOf(self: *Heaven, src: []const u8) HeavenError![]u8 {
        return self.allocator.dupe(u8, src);
    }
    pub fn evalSkill(self: *Heaven, src: []const u8) HeavenError![]u8 {
        var trimmed = std.mem.trim(u8, src, " \t");
        if (std.mem.startsWith(u8, trimmed, "skill ")) {
            trimmed = std.mem.trim(u8, trimmed["skill ".len..], " \t");
        }
        if (trimmed.len == 0)
            return self.allocator.dupe(u8, "usage: skill <name> [on <var>]");

        var name: []const u8 = trimmed;
        var var_name: []const u8 = "n";
        if (std.mem.indexOf(u8, name, " on ")) |pos| {
            var_name = std.mem.trim(u8, name[pos + 4 ..], " \t");
            name = std.mem.trim(u8, name[0..pos], " \t");
        }
        if (name.len == 0)
            return self.allocator.dupe(u8, "usage: skill <name> [on <var>]");

        const thm_name = self.active_theorem orelse
            return self.allocator.dupe(u8, "✗ no active theorem (tapez `theorem ...` d'abord)");

        _ = self.ensureCommands();
        const sk = self.skills orelse
            return self.allocator.dupe(u8, "✗ skills unavailable");
        const skill = sk.get(name) orelse
            return std.fmt.allocPrint(self.allocator, "✗ unknown skill: {s}", .{name});
        const body = skill.body;

        // Substitution {var}
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        var i: usize = 0;
        while (i < body.len) {
            if (std.mem.startsWith(u8, body[i..], "{var}")) {
                try buf.appendSlice(self.allocator, var_name);
                i += 5;
            } else {
                try buf.append(self.allocator, body[i]);
                i += 1;
            }
        }

        const session = try self.startProof(thm_name);
        defer session.deinit();

        const report = session.applyLine(buf.items) catch |err| {
            return std.fmt.allocPrint(self.allocator, "✗ skill error: {}", .{err});
        };
        defer self.allocator.free(report);

        const proved = try session.finish();
        if (proved) {
            return std.fmt.allocPrint(
                self.allocator,
                "✓ [{s}] '{s}' proved via skill\n{s}",
                .{ name, thm_name, report },
            );
        }
        return std.fmt.allocPrint(
            self.allocator,
            "✗ [{s}] '{s}' unproved\n{s}",
            .{ name, thm_name, report },
        );
    }
    // ═══ Tactics v1 ═══

    /// Construit un Goal à partir du statement textuel du théorème, parse
    /// un bloc de tactiques `t1; t2; ...`, l'applique, et retourne un
    /// rapport. Si tous les buts sont résolus, marque le théorème comme
    /// vérifié dans ProofCore.
    pub fn runTacticsBlock(
        self: *Heaven,
        theorem_name: []const u8,
        block_src: []const u8,
    ) HeavenError![]u8 {
        _ = self.ensureCommands();
        const pc = self.proof_core_inst orelse
            return error.Unexpected;
        const thm = pc.theorems.getPtr(theorem_name) orelse
            return error.UnknownVariable;

        // 1. Découper "lhs = rhs"
        const stmt = thm.statement;
        const eq_pos = std.mem.indexOf(u8, stmt, " = ") orelse
            return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " \t");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 3 ..], " \t");

        const lhs_id = try self.parseExpression(lhs_str);
        const rhs_id = try self.parseExpression(rhs_str);
        const eq_sym = try self.store.sym("=");
        const target = try self.store.apply(eq_sym, &.{ lhs_id, rhs_id });

        // 2. ProofState + aréna
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var state = proof_state_mod.ProofState.init(
            self.allocator, &arena, self.store, theorem_name,
        );
        defer state.deinit();

        try state.appendGoal(.{
            .hyps = try state.dupHyps(&.{}, ),
            .target = target,
            .label = try state.dupLabel("main"),
        });

        // 3. Parse + apply
        const tactic = tactics_mod.parseTacticsBlock(arena.allocator(), block_src) catch |err| {
            return std.fmt.allocPrint(self.allocator, "✗ tactic parse error: {}\n", .{err});
        };

        var ctx = tactics_mod.TacticCtx{
            .allocator = self.allocator,
            .store = self.store,
            .heaven = @ptrCast(self),
            .simplifyFn = tacticsSimplifyCb,
            .eqFn = tacticsEqCb,
            .peanoFn = tacticsPeanoCb,
            .substFn = tacticsSubstCb,
        };

        tactics_mod.applyTactic(&state, tactic, &ctx) catch |err| {
            const pp = try state.pp(self.allocator);
            defer self.allocator.free(pp);
            return std.fmt.allocPrint(self.allocator, "✗ tactic failed: {} — {d} goal(s) remaining:\n{s}", .{ err, state.goals.items.len, pp });
        };

        // 4. Vérifier
        if (state.solved()) {
            thm.verified = true;
            return std.fmt.allocPrint(self.allocator, "✓ [{s}] proved (tactics)\n", .{theorem_name});
        }
        const pp = try state.pp(self.allocator);
        defer self.allocator.free(pp);
        return std.fmt.allocPrint(self.allocator, "✗ {d} goal(s) remaining:\n{s}", .{ state.goals.items.len, pp });
    }

    // ─── Callbacks pour TacticCtx ───

    fn tacticsSimplifyCb(ctx: *tactics_mod.TacticCtx, input: []const u8) anyerror![]u8 {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return self.simplify(input);
    }

    fn tacticsEqCb(ctx: *tactics_mod.TacticCtx, a: Id, b: Id) anyerror!bool {
        if (a == b) return true;
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return expr.structuralEql(self.store, a, b);
    }

    fn tacticsPeanoCb(ctx: *tactics_mod.TacticCtx, k: i64) anyerror!Id {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        if (k <= 0) return self.store.sym("zero");
        const inner = try tacticsPeanoCb(ctx, k - 1);
        return self.store.call("succ", &.{inner});
    }

    fn tacticsSubstCb(
        ctx: *tactics_mod.TacticCtx,
        e: Id,
        name: []const u8,
        repl: Id,
    ) anyerror!Id {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return substSymByName(self.store, self.allocator, e, name, repl);
    }

    // ═══ REPL interactif de preuve (ProofSession) ═══

    pub const ProofSession = struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        state: proof_state_mod.ProofState,
        ctx: tactics_mod.TacticCtx,
        theorem_name: []const u8,
        heaven: *Heaven,

        pub fn deinit(self: *ProofSession) void {
            self.state.deinit();
            self.arena.deinit();
            self.allocator.destroy(self.arena);
            self.allocator.free(self.theorem_name);
            self.allocator.destroy(self);
        }

        /// Parse une ligne (peut contenir plusieurs tactiques séparées par `;`)
        /// et l'applique. Retourne un rapport formatté pour affichage.
        pub fn applyLine(self: *ProofSession, line: []const u8) ![]u8 {
            const tactic = tactics_mod.parseTacticsBlock(self.arena.allocator(), line) catch |err| {
                return std.fmt.allocPrint(self.allocator, "✗ parse error: {}\n", .{err});
            };
            tactics_mod.applyTactic(&self.state, tactic, &self.ctx) catch |err| {
                const state_pp = try self.state.pp(self.allocator);
                defer self.allocator.free(state_pp);
                return std.fmt.allocPrint(self.allocator, "✗ {}\n{s}", .{ err, state_pp });
            };
            if (self.state.solved()) {
                return self.allocator.dupe(u8, "✓ All goals solved. Tapez '}' ou 'qed' pour valider.\n");
            }
            const state_pp = try self.state.pp(self.allocator);
            defer self.allocator.free(state_pp);
            return std.fmt.allocPrint(self.allocator, "{s}", .{state_pp});
        }

        /// Vérifie que tous les buts sont résolus et marque le théorème.
        pub fn finish(self: *ProofSession) !bool {
            if (!self.state.solved()) return false;
            _ = self.heaven.ensureCommands();
            const pc = self.heaven.proof_core_inst orelse return false;
            const thm = pc.theorems.getPtr(self.theorem_name) orelse return false;
            thm.verified = true;
            return true;
        }

        pub fn pp(self: *ProofSession) ![]u8 {
            return self.state.pp(self.allocator);
        }
    };

    /// Démarre une session de preuve interactive pour un théorème déjà déclaré.
    /// L'appelant est responsable d'appeler session.deinit().
    pub fn startProof(self: *Heaven, theorem_name: []const u8) HeavenError!*ProofSession {
        _ = self.ensureCommands();
        const pc = self.proof_core_inst orelse return error.Unexpected;
        const thm = pc.theorems.getPtr(theorem_name) orelse return error.UnknownVariable;

        // Parse "lhs = rhs" (au premier " = ")
        const stmt = thm.statement;
        const eq_pos = std.mem.indexOf(u8, stmt, " = ") orelse return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " \t");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 3 ..], " \t");

        const lhs_id = try self.parseExpression(lhs_str);
        const rhs_id = try self.parseExpression(rhs_str);
        const eq_sym = try self.store.sym("=");
        const target = try self.store.apply(eq_sym, &.{ lhs_id, rhs_id });

        const session = try self.allocator.create(ProofSession);
        errdefer self.allocator.destroy(session);

        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);

        session.* = .{
            .allocator = self.allocator,
            .arena = arena,
            .state = proof_state_mod.ProofState.init(
                self.allocator, arena, self.store, theorem_name,
            ),
            .ctx = undefined,
            .theorem_name = try self.allocator.dupe(u8, theorem_name),
            .heaven = self,
        };
        errdefer self.allocator.free(session.theorem_name);

        try session.state.appendGoal(.{
            .hyps = try session.state.dupHyps(&.{}),
            .target = target,
            .label = try session.state.dupLabel("main"),
        });

        session.ctx = tactics_mod.TacticCtx{
            .allocator = self.allocator,
            .store = self.store,
            .heaven = @ptrCast(self),
            .simplifyFn = tacticsSimplifyCb,
            .eqFn = tacticsEqCb,
            .peanoFn = tacticsPeanoCb,
            .substFn = tacticsSubstCb,
        };

        return session;
    }

    pub fn evalProve(self: *Heaven, src: []const u8) HeavenError![]u8 {
        // ─── Tactics v1 : `prove <name> by { t1; t2; ... }` ───
        // Intercepté AVANT le chemin classique pour ne pas casser
        // `by simplify` / `by eval` / `by induction x` (compat).
        if (std.mem.indexOf(u8, src, " by {")) |pos| {
            const name = std.mem.trim(u8, src[0..pos], " \t");
            if (name.len == 0) return error.InvalidSyntax;
            const rest = src[pos + " by {".len ..];
            const close = std.mem.lastIndexOfScalar(u8, rest, '}') orelse
                return error.InvalidSyntax;
            const body = rest[0..close];
            return self.runTacticsBlock(name, body);
        }

        if (self.ensureCommands()) |cmds| {
            return cmds.evalProve(src) catch |err| {
                return switch (err) {
                    error.OutOfMemory => HeavenError.OutOfMemory,
                    else => HeavenError.EvaluationFailed,
                };
            };
        }
        return self.allocator.dupe(u8, "✗ commands unavailable");
    }
    pub fn dumpAst(self: *Heaven, src: []const u8) HeavenError![]u8 {
        return self.allocator.dupe(u8, src);
    }
    pub fn toLaTeXInline(self: *Heaven, id: Id) HeavenError![]u8 {
        _ = id;
        return self.allocator.dupe(u8, "");
    }
    pub fn explain(self: *Heaven, src: []const u8) HeavenError![]u8 {
        return self.allocator.dupe(u8, src);
    }
    pub fn describeKB(self: *Heaven) HeavenError![]u8 {
        return self.allocator.dupe(u8, "KB: stub");
    }
    pub fn toC(self: *Heaven, ids: []const Id) HeavenError![]u8 {
        _ = ids;
        return self.allocator.dupe(u8, "// stub");
    }
    pub fn derive(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        // Utiliser parseExpression (gère ^, *, +, -, /)
        const expr_id = try self.parseExpression(expr_str);
        // Récupérer le Sym de la variable
        const var_id = try self.store.sym(var_name);
        const var_node = self.store.get(var_id);
        const var_sym = var_node.payload;
        // Appeler deriveExpr directement
        const result = self.math.deriveExpr(expr_id, var_sym) catch |err| {
            switch (err) {
                error.UnsupportedPowerVarExp,
                error.UnsupportedPowerType,
                error.UnsupportedDeriveOp,
                => return error.UnsupportedExpr,
                else => return error.EvaluationFailed,
            }
        };
        // simplification directe
        const simplified = try self.math.simplifyBasic(result);
        return expr.toStringInfix(self.store, simplified, self.allocator);
    }
    pub fn deriveToId(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError!Id {
        const expr_id = try self.parseExpression(expr_str);
        const var_id = try self.store.sym(var_name);
        const var_node = self.store.get(var_id);
        const var_sym = var_node.payload;
        const result = try self.math.deriveExpr(expr_id, var_sym);
        return try self.math.simplifyBasic(result);
    }

    pub fn simplifyToId(self: *Heaven, input: []const u8) HeavenError!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidInput;
        const raw_id = try self.parseExpression(trimmed);
        const id = try self.ensureLowered(raw_id);
        const after_basic = try self.math.simplifyBasic(id);
        const after_egraph = try self.simplify_eng.simplifyWithEGraph(after_basic, null, null);
        return try self.math.simplifyBasic(after_egraph);
    }

    pub fn integrate(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        return self.math.integrate(expr_str, var_name);
    }
    pub fn solve(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        return self.math.solve(expr_str, var_name);
    }
    pub fn expand(self: *Heaven, expr_str: []const u8) HeavenError![]u8 {
        return self.math.expand(expr_str);
    }
    pub fn plot(self: *Heaven, expr_str: []const u8, var_name: []const u8) HeavenError![]u8 {
        return self.math.plot(expr_str, var_name);
    }
    pub fn evalTheorem(self: *Heaven, src: []const u8) HeavenError![]u8 {
        if (self.ensureCommands()) |cmds| {
            return cmds.evalTheorem(src) catch |err| {
                return switch (err) {
                    error.OutOfMemory => HeavenError.OutOfMemory,
                    else => HeavenError.EvaluationFailed,
                };
            };
        }
        return self.allocator.dupe(u8, "✗ commands unavailable");
    }
    pub fn substExpr(self: *Heaven, expression: []const u8, var_name: []const u8, val: []const u8) HeavenError![]u8 {
        _ = var_name;
        _ = val;
        return self.allocator.dupe(u8, expression);
    }

    pub fn listRules(self: *Heaven) HeavenError![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);

        _ = try buf.writer(self.allocator).print("=== Knowledge Base Rules ({d}) ===\n", .{self.kb.rules.items.len});

        for (self.kb.rules.items, 0..) |rule_id, i| {
            const rule = self.store.get(rule_id);

            // CORRECTION : utiliser spanSliceConst
            const span_a = self.store.spanSliceConst(rule.span_a);
            const span_b = self.store.spanSliceConst(rule.span_b);

            if (span_a.len >= 2) {
                const lhs_str = try expr.toStringInfix(self.store, span_a[0], self.allocator);
                defer self.allocator.free(lhs_str);
                const rhs_str = try expr.toStringInfix(self.store, span_a[1], self.allocator);
                defer self.allocator.free(rhs_str);
                _ = try buf.writer(self.allocator).print("[{d}] {s} => {s}\n", .{ i, lhs_str, rhs_str });
            } else if (span_a.len >= 1 and span_b.len >= 1) {
                const lhs_str = try expr.toStringInfix(self.store, span_a[0], self.allocator);
                defer self.allocator.free(lhs_str);
                const rhs_str = try expr.toStringInfix(self.store, span_b[0], self.allocator);
                defer self.allocator.free(rhs_str);
                _ = try buf.writer(self.allocator).print("[{d}] {s} => {s}\n", .{ i, lhs_str, rhs_str });
            } else {
                _ = try buf.writer(self.allocator).print("[{d}] (tag={s}, span_a.len={d}, span_b.len={d})\n", .{ i, @tagName(rule.tag), span_a.len, span_b.len });
            }
        }

        return buf.toOwnedSlice(self.allocator);
    }

    pub fn evalSExpr(self: *Heaven, src: []const u8) HeavenError![]u8 {
        return self.allocator.dupe(u8, src);
    }
    pub fn define(self: *Heaven, name: []const u8, val: []const u8) HeavenError![]u8 {
        _ = name;
        _ = val;
        return self.allocator.dupe(u8, "");
    }
    pub fn addRewrite(self: *Heaven, lhs: []const u8, rhs: []const u8) HeavenError![]u8 {
        _ = lhs;
        _ = rhs;
        return self.allocator.dupe(u8, "");
    }
    pub fn evaluateExpr(self: *Heaven, id: Id) HeavenError!Id {
        if (platform.target.is_debug and id == 0xAAAAAAAA) {
            @panic("poison Id at evaluate entry");
        }

        self.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(self.store, &self.env, &self.engine, id, 0) catch |err| {
            if (!self.in_interp and (err == error.UnboundVariable or err == error.UnknownSymbol)) {
                self.in_interp = true;
                defer self.in_interp = false;
                return self.interpForAssert(id) catch id;
            }
            return err;
        };
        return result;
    }

    fn evalSpecialExpr(self: *Heaven, id: Id) HeavenError!Id {
        const node = self.store.get(id);
        if (node.tag != .apply) {
            return self.evaluateExpr(id);
        }
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len == 0) return self.evaluateExpr(id);
        const func_node = self.store.get(args[0]);
        if (func_node.tag != .sym) {
            return self.evaluateExpr(id);
        }
        const func_name = self.store.interner.resolve(func_node.payload);

        // Log pour déboguer
        platform.dbg("[evalSpecialExpr] func_name='{s}'\n", .{func_name});

        if (std.mem.eql(u8, func_name, "derive")) {
            if (args.len < 2) return error.ArityMismatch;
            const arg_expr = args[1];
            // Variable par défaut "x"
            const var_sym = try self.store.interner.intern("x");
            const result = try self.math.deriveExpr(arg_expr, var_sym);
            return try self.math.simplifyBasic(result);
        }
        if (std.mem.eql(u8, func_name, "simplify")) {
            if (args.len < 2) return error.ArityMismatch;
            const arg_expr = args[1];
            const result = try self.math.simplifyBasic(arg_expr);
            // Optionnellement, on pourrait utiliser l'EGraph pour des simplifications plus avancées
            return result;
        }

        return self.evaluateExpr(id);
    }

    /// Interprète les commandes intégrées (derive, simplify...) DANS une expression
    /// d'assertion, car elles ne sont pas des fonctions évaluables par l'engine.
    fn interpForAssert(self: *Heaven, id: Id) HeavenError!Id {
        const node = self.store.get(id);

        // ─── Trou : résolu ou erreur ───
        if (node.tag == .hole) {
            if (self.hole_state.resolve(node.payload)) |resolved| {
                return resolved;
            }
            return error.UnboundHole;
        }

        // ─── Cas .bind Core : (bind name [val, body]) ───
        if (node.tag == .bind) {
            const args = self.store.spanSliceConst(node.span_a);
            if (args.len == 0) return id;
            const val = self.evaluateExpr(args[0]) catch args[0];
            try self.env.put(node.payload, val);
            defer self.env.delete(node.payload);
            if (args.len >= 2) {
                return self.interpForAssert(args[1]) catch id;
            }
            return val;
        }

        if (node.tag != .apply) {
            return self.evaluateExpr(id) catch id; // Fix 1 : syms nus évalués
        }

        const all = self.store.spanSliceConst(node.span_a);
        if (all.len < 1) return id;
        const args = all[1..];

        const fnode = self.store.get(node.payload);

        //platform.dbg("[preFix2] func_tag={s} args.len={d}\n", .{ @tagName(fnode.tag), args.len });

        // Fix 2a : FUNC = LAMBDA NODE (lambdaNative : payload=param, span_a=[body])
        if (fnode.tag == .lambda and args.len == 1) {
            const lam_span = self.store.spanSliceConst(fnode.span_a);
            if (lam_span.len == 1) {
                const param_sym = fnode.payload;
                const arg_val = self.evaluateExpr(args[0]) catch args[0];
                try self.env.put(param_sym, arg_val);
                defer self.env.delete(param_sym);
                return self.interpForAssert(lam_span[0]) catch id;
            }
        }

        // Fix 2b : FUNC = APPLY sym"lambda" (structure alternative du parser)
        if (fnode.tag == .apply and args.len == 1) {
            const inner_func = self.store.get(fnode.payload);
            if (inner_func.tag == .sym) {
                const inner_head = self.store.interner.resolve(inner_func.payload);
                if (std.mem.eql(u8, inner_head, "lambda")) {
                    const lam_args = self.store.spanSliceConst(fnode.span_a);
                    if (lam_args.len == 3) {
                        const param_node = self.store.get(lam_args[1]);
                        if (param_node.tag == .sym) {
                            const arg_val = self.evaluateExpr(args[0]) catch args[0];
                            try self.env.put(param_node.payload, arg_val);
                            defer self.env.delete(param_node.payload);
                            return self.interpForAssert(lam_args[2]) catch id;
                        }
                    }
                }
            }
        }

        // Fix 3 : FONCTION ENV-BOUND (f arg) où f est une lambda dans l'env
        // L'engine ne cherche l'env que pour les syms nus — pas les appels.
        {
            //platform.dbg("[fix3-enter] fnode.payload={d} env has: ", .{fnode.payload});
            if (self.env.get(fnode.payload)) |bound| {
                platform.dbg("YES bound.tag={s}\n", .{@tagName(self.store.get(bound).tag)});
                // bound = la valeur liée (peut être un nœud .lambda !)
                const bound_node = self.store.get(bound);

                // Cas .lambda : appliquer directement (payload=param, span_a=[body])
                if (bound_node.tag == .lambda and args.len == 1) {
                    const lam_span = self.store.spanSliceConst(bound_node.span_a);
                    if (lam_span.len == 1) {
                        const param_sym = bound_node.payload;
                        const arg_val = self.evaluateExpr(args[0]) catch args[0];
                        try self.env.put(param_sym, arg_val);
                        defer self.env.delete(param_sym);
                        return self.interpForAssert(lam_span[0]) catch id;
                    }
                }

                // Cas .apply sym"lambda" (structure alternative)
                if (bound_node.tag == .apply and args.len == 1) {
                    const inner_func = self.store.get(bound_node.payload);
                    if (inner_func.tag == .sym) {
                        const inner_head = self.store.interner.resolve(inner_func.payload);
                        if (std.mem.eql(u8, inner_head, "lambda")) {
                            const lam_args = self.store.spanSliceConst(bound_node.span_a);
                            if (lam_args.len == 3) {
                                const param_node = self.store.get(lam_args[1]);
                                if (param_node.tag == .sym) {
                                    const arg_val = self.evaluateExpr(args[0]) catch args[0];
                                    try self.env.put(param_node.payload, arg_val);
                                    defer self.env.delete(param_node.payload);
                                    return self.interpForAssert(lam_args[2]) catch id;
                                }
                            }
                        }
                    }
                }
            } else {
                platform.dbg("NO\n", .{});
            }
        }

        if (fnode.tag != .sym) {
            return self.evaluateExpr(id) catch id;
        }
        const head = self.store.interner.resolve(fnode.payload);

        // DUMP : la structure complète du nœud
        if (std.mem.eql(u8, head, "lambda") or args.len > 1) {
            const s = try expr.toStringInfix(self.store, id, self.allocator);
            defer self.allocator.free(s);
            platform.dbg("[dump] id={d} head='{s}' struct='{s}'\n", .{ id, head, s });
        }

        if (args.len == 1) {
            const arg_str = try expr.toStringInfix(self.store, args[0], self.allocator);
            defer self.allocator.free(arg_str);

            var result_str: ?[]u8 = null;
            defer if (result_str) |r| self.allocator.free(r);

            if (std.mem.eql(u8, head, "derive")) {
                result_str = try self.derive(arg_str, "x");
            } else if (std.mem.eql(u8, head, "simplify")) {
                result_str = try self.simplify(arg_str);
            } else if (std.mem.eql(u8, head, "expand")) {
                result_str = try self.expand(arg_str);
            } else if (std.mem.eql(u8, head, "integrate")) {
                result_str = try self.integrate(arg_str, "x");
            }
            if (result_str) |rs| {
                return self.parseExpression(rs);
            }
        }

        // ═══ 1. LET-INLINE : (let x val body) ═══
        if (node.tag == .bind) {
            if (args.len == 2) {
                const val = self.evaluateExpr(args[0]) catch args[0];
                try self.env.put(node.payload, val);
                defer self.env.delete(node.payload);
                return self.interpForAssert(args[1]) catch id;
            }
        }

        // ═══ 2. LAMBDA SYMBOLE : ((lambda x body) arg) — le func est apply(sym"lambda") ═══
        {
            const func_node = self.store.get(node.payload);
            if (func_node.tag == .apply) {
                const inner = self.store.get(func_node.payload);
                if (inner.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(inner.payload), "lambda")) {
                    const lam_args = self.store.spanSliceConst(func_node.span_a);
                    if (lam_args.len == 3) { // [lambda, param, body]
                        const param_node = self.store.get(lam_args[1]);
                        if (param_node.tag == .sym) {
                            const arg_val = self.evaluateExpr(args[0]) catch args[0];
                            try self.env.put(param_node.payload, arg_val);
                            defer self.env.delete(param_node.payload);
                            return self.interpForAssert(lam_args[2]) catch id;
                        }
                    }
                }
            }
        }

        // ═══ 3. FONCTION ENV-BOUND : (f arg) où f est une lambda dans l'env ═══
        // L'engine ne cherche l'env que pour les syms nus — pas les appels.
        // C'est ce qui fait marcher (fact 5) avec fact lié par let.
        {
            if (self.env.get(fnode.payload)) |bound| {
                const bound_node = self.store.get(bound);
                if (bound_node.tag == .lambda and args.len == 1) {
                    const lam_span = self.store.spanSliceConst(bound_node.span_a);
                    if (lam_span.len == 1) {
                        const param_sym = bound_node.payload;
                        const arg_val = self.evaluateExpr(args[0]) catch args[0];
                        try self.env.put(param_sym, arg_val);
                        defer self.env.delete(param_sym);
                        return self.interpForAssert(lam_span[0]) catch |err| {
                            platform.dbg("[recursion] body eval failed: {} — n={d}\n", .{ err, arg_val });
                            return id;
                        };
                    }
                }
            }
        }

        // 1. D'ABORD l'évaluation engine normale
        if (self.evaluateExpr(id)) |v| {
            return v;
        } else |_| {
            //platform.dbg("[interp-err] id={d} err={}\n", .{ id, err });
        }

        // 2. FALLBACK uniquement : macro/fonction user via la pile
        if (self.commands) |cmds| {
            const s = try expr.toStringInfix(self.store, id, self.allocator);
            defer self.allocator.free(s);
            if (cmds.eval(s)) |r| {
                defer self.allocator.free(r);
                // ⚠️ Commands.eval retourne des STRINGS d'erreur — les filtrer
                if (!std.mem.startsWith(u8, r, "eval error") and
                    !std.mem.startsWith(u8, r, "actor error") and
                    !std.mem.startsWith(u8, r, "parse error") and
                    !std.mem.startsWith(u8, r, "syntax error"))
                {
                    return self.parseExpression(r) catch id;
                }
            } else |_| {}
        }
        return id;
    }

    pub fn format(self: *Heaven, id: Id) HeavenError![]u8 {
        return expr.toString(self.store, id, self.allocator);
    }
    pub fn canonicalize(self: *Heaven, id: Id) HeavenError![]u8 {
        const lowered = try self.ensureLowered(id);
        const result = canon.canonicalizeAC(self.store, lowered) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
        };
        return try self.format(result);
    }
    pub fn matchPattern(self: *Heaven, pattern_id: Id, target: Id) HeavenError!bool {
        const p = try self.ensureLowered(pattern_id);
        const t = try self.ensureLowered(target);
        var bindings = pattern.Bindings.init(self.store.allocator);
        defer bindings.deinit();
        return pattern.match(self.store, p, t, &bindings) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
            error.MatchFailed => return false,
        };
    }
    pub fn provePeano(self: *Heaven, id: Id, axiom: proof.PeanoAxiom) HeavenError![]u8 {
        const lowered = try self.ensureLowered(id);
        const result = proof.rewritePeano(self.store, lowered, axiom) catch |err| switch (err) {
            error.OutOfMemory => return HeavenError.OutOfMemory,
            else => return HeavenError.EvaluationFailed,
        };
        return try self.format(result);
    }

    fn addRule(self: *Heaven, lhs: Id, rhs: Id) !void {
        const rule = try self.store.relation("rule", &.{lhs}, &.{rhs});
        try self.kb.rules.append(self.allocator, rule);
    }

    fn addDefaultRules(self: *Heaven) !void {
        const store = self.store;
        const x = try store.sym("?x");
        const a = try store.sym("?a");
        const b = try store.sym("?b");
        const c = try store.sym("?c");
        const zero = try store.int(0);
        const one = try store.int(1);
        const two = try store.int(2);

        // Identités
        try self.addRule(try store.binop("+", x, zero), x);
        try self.addRule(try store.binop("+", zero, x), x);
        try self.addRule(try store.binop("*", x, one), x);
        try self.addRule(try store.binop("*", one, x), x);
        try self.addRule(try store.binop("*", x, zero), zero);
        try self.addRule(try store.binop("*", zero, x), zero);
        try self.addRule(try store.binop("-", x, zero), x);
        try self.addRule(try store.binop("/", x, one), x);

        // Puissances
        try self.addRule(try store.binop("^", x, one), x);
        try self.addRule(try store.binop("^", x, zero), one);

        // Doublon non-linéaire : (+ ?x ?x) => (* 2 ?x)
        try self.addRule(try store.binop("+", x, x), try store.binop("*", two, x));

        // Carré : (* ?x ?x) => (^ ?x 2)
        try self.addRule(try store.binop("*", x, x), try store.binop("^", x, two));

        // Associativité (une seule direction)
        try self.addRule(
            try store.binop("+", try store.binop("+", a, b), c),
            try store.binop("+", a, try store.binop("+", b, c)),
        );

        // Distributivité / factorisation
        try self.addRule(
            try store.binop("*", a, try store.binop("+", b, c)),
            try store.binop("+", try store.binop("*", a, b), try store.binop("*", a, c)),
        );
        try self.addRule(
            try store.binop("+", try store.binop("*", a, b), try store.binop("*", a, c)),
            try store.binop("*", a, try store.binop("+", b, c)),
        );

        // Commutativité (une seule paire)
        try self.addRule(try store.binop("+", a, b), try store.binop("+", b, a));
        try self.addRule(try store.binop("*", a, b), try store.binop("*", b, a));
    }

    /// Découpe "a b" au premier espace de niveau 0 (respecte parenthèses et strings)
    fn splitTopLevel(inner: []const u8) ?struct { a: []const u8, b: []const u8 } {
        var depth: usize = 0;
        var in_str = false;
        for (inner, 0..) |c, i| {
            switch (c) {
                '"' => in_str = !in_str,
                '(' => {
                    if (!in_str) depth += 1;
                },
                ')' => {
                    if (!in_str and depth > 0) depth -= 1;
                },
                ' ' => {
                    if (!in_str and depth == 0) {
                        const a = std.mem.trim(u8, inner[0..i], " ");
                        const b = std.mem.trim(u8, inner[i + 1 ..], " ");
                        if (a.len > 0 and b.len > 0) return .{ .a = a, .b = b };
                    }
                },
                else => {},
            }
        }
        return null;
    }

    fn evalAssertion(self: *Heaven, input: []const u8) HeavenError![]u8 {
        if (std.mem.startsWith(u8, input, "(assert_eq ")) {
            const inner = input["(assert_eq ".len .. input.len - 1];
            const sp = splitTopLevel(inner) orelse
                return self.allocator.dupe(u8, "✗ syntax error in assert_eq");

            // Analyser la structure de lhs pour détecter derive/simplify
            const lhs = try self.parseExpression(sp.a);
            const rhs = try self.parseExpression(sp.b);

            // Interpréter les commandes intégrées AVANT de simplifier/comparer
            const ls = try self.interpForAssert(lhs);
            const rs = try self.interpForAssert(rhs);
            const ls_simp = try self.math.simplifyBasic(ls);
            const rs_simp = try self.math.simplifyBasic(rs);
            if (self.math.structuralEq(ls_simp, rs_simp)) {
                return self.allocator.dupe(u8, "✓ assert_eq passed");
            }
            // Égalité sémantique E-Graph
            if (self.egraphSemanticEq(ls_simp, rs_simp)) {
                return self.allocator.dupe(u8, "✓ assert_eq passed (e-graph)");
            }
            const l_str = try expr.toStringInfix(self.store, ls, self.allocator);
            defer self.allocator.free(l_str);
            const r_str = try expr.toStringInfix(self.store, rs, self.allocator);
            defer self.allocator.free(r_str);
            return std.fmt.allocPrint(self.allocator, "✗ assert_eq failed: {s} != {s}", .{ l_str, r_str });
        }

        if (std.mem.startsWith(u8, input, "(assert_err ")) {
            const inner = input["(assert_err ".len .. input.len - 1];

            // Un échec de parse compte comme un échec attendu (QTT : linear check
            // est fait au parsing, LinearViolation doit être capturée).
            if (self.parseExpression(inner)) |id| {
                _ = self.evaluateExpr(id) catch {
                    return self.allocator.dupe(u8, "✓ assert_err passed");
                };
                return self.allocator.dupe(u8, "✗ assert_err failed: expression evaluated successfully");
            } else |_| {
                return self.allocator.dupe(u8, "✓ assert_err passed");
            }
        }

        if (std.mem.startsWith(u8, input, "(test ")) {
            const inner = input["(test ".len .. input.len - 1];
            const sp = splitTopLevel(inner) orelse
                return self.allocator.dupe(u8, "✗ syntax error in test");
            var name = sp.a;
            if (name.len >= 2 and name[0] == '"' and name[name.len - 1] == '"')
                name = name[1 .. name.len - 1];
            if (std.mem.startsWith(u8, sp.b, "(assert")) {
                const res = try self.evalAssertion(sp.b);
                defer self.allocator.free(res);
                return std.fmt.allocPrint(self.allocator, "test {s}: {s}", .{ name, res });
            }
            const id = try self.parseExpression(sp.b);
            _ = self.evaluateExpr(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "✗ test {s} error: {}", .{ name, err });
            };
            return std.fmt.allocPrint(self.allocator, "✓ test {s} passed", .{name});
        }
        return self.allocator.dupe(u8, input);
    }

    /// Cherche ` == ` au niveau 0 (hors parenthèses et strings).
    fn splitTopLevelEq(inner: []const u8) ?struct { a: []const u8, b: []const u8 } {
        var depth: usize = 0;
        var in_str = false;
        var i: usize = 0;
        while (i + 3 < inner.len) : (i += 1) {
            const c = inner[i];
            if (c == '"') {
                in_str = !in_str;
                continue;
            }
            if (in_str) continue;
            if (c == '(') {
                depth += 1;
                continue;
            }
            if (c == ')') {
                if (depth > 0) depth -= 1;
                continue;
            }
            if (depth == 0 and c == ' ' and
                inner[i + 1] == '=' and inner[i + 2] == '=' and inner[i + 3] == ' ')
            {
                const a = std.mem.trim(u8, inner[0..i], " \t");
                const b = std.mem.trim(u8, inner[i + 4 ..], " \t");
                if (a.len > 0 and b.len > 0) return .{ .a = a, .b = b };
            }
        }
        return null;
    }

    fn evalAssertionNative(self: *Heaven, input: []const u8) HeavenError![]u8 {
        // ─── test "name": body ───
        if (std.mem.startsWith(u8, input, "test \"")) {
            const after_test = input["test \"".len..];
            const quote_end = std.mem.indexOfScalar(u8, after_test, '"') orelse
                return self.allocator.dupe(u8, "✗ test: quote manquante");
            const name = after_test[0..quote_end];
            const after_name = std.mem.trimLeft(u8, after_test[quote_end + 1 ..], " \t");
            if (after_name.len == 0 or after_name[0] != ':')
                return self.allocator.dupe(u8, "✗ test: ':' manquant après le nom");
            const body = std.mem.trim(u8, after_name[1..], " \t");

            // Sous-cas : test "name": assert_err expr
            if (std.mem.startsWith(u8, body, "assert_err ")) {
                const res = try self.evalAssertionNative(body);
                defer self.allocator.free(res);
                return std.fmt.allocPrint(self.allocator, "test {s}: {s}", .{ name, res });
            }

            // Cas principal : test "name": lhs == rhs
            const sp = splitTopLevelEq(body) orelse
                return std.fmt.allocPrint(self.allocator, "✗ test {s}: opérateur '==' manquant", .{name});

            const lhs = try self.parseOrDispatch(sp.a);
            const rhs = try self.parseOrDispatch(sp.b);
            const ls = try self.interpForAssert(lhs);
            const rs = try self.interpForAssert(rhs);
            const ls_simp = try self.math.simplifyBasic(ls);
            const rs_simp = try self.math.simplifyBasic(rs);
            if (self.math.structuralEq(ls_simp, rs_simp))
                return std.fmt.allocPrint(self.allocator, "test {s}: ✓ passed", .{name});
            if (self.egraphSemanticEq(ls_simp, rs_simp))
                return std.fmt.allocPrint(self.allocator, "test {s}: ✓ passed (e-graph)", .{name});
            const l_str = try expr.toStringInfix(self.store, ls, self.allocator);
            defer self.allocator.free(l_str);
            const r_str = try expr.toStringInfix(self.store, rs, self.allocator);
            defer self.allocator.free(r_str);
            return std.fmt.allocPrint(self.allocator, "✗ test {s}: {s} != {s}", .{ name, l_str, r_str });
        }

        // ─── assert_eq lhs == rhs ───
        if (std.mem.startsWith(u8, input, "assert_eq ")) {
            const body = std.mem.trim(u8, input["assert_eq ".len..], " \t");
            const sp = splitTopLevelEq(body) orelse
                return self.allocator.dupe(u8, "✗ assert_eq: '==' manquant");

            const lhs = try self.parseOrDispatch(sp.a);
            const rhs = try self.parseOrDispatch(sp.b);
            const ls = try self.interpForAssert(lhs);
            const rs = try self.interpForAssert(rhs);
            const ls_simp = try self.math.simplifyBasic(ls);
            const rs_simp = try self.math.simplifyBasic(rs);
            if (self.math.structuralEq(ls_simp, rs_simp))
                return self.allocator.dupe(u8, "✓ assert_eq passed");
            if (self.egraphSemanticEq(ls_simp, rs_simp))
                return self.allocator.dupe(u8, "✓ assert_eq passed (e-graph)");
            const l_str = try expr.toStringInfix(self.store, ls, self.allocator);
            defer self.allocator.free(l_str);
            const r_str = try expr.toStringInfix(self.store, rs, self.allocator);
            defer self.allocator.free(r_str);
            return std.fmt.allocPrint(self.allocator, "✗ assert_eq failed: {s} != {s}", .{ l_str, r_str });
        }

        // ─── assert_err expr ───
        if (std.mem.startsWith(u8, input, "assert_err ")) {
            const inner = std.mem.trim(u8, input["assert_err ".len..], " \t");
            if (self.parseExpression(inner)) |id| {
                _ = self.evaluateExpr(id) catch {
                    return self.allocator.dupe(u8, "✓ assert_err passed");
                };
                return self.allocator.dupe(u8, "✗ assert_err failed: expression evaluated successfully");
            } else |_| {
                return self.allocator.dupe(u8, "✓ assert_err passed");
            }
        }

        return self.allocator.dupe(u8, input);
    }

    /// Parse une sous-expression d'assertion. Si elle commence par une
    /// commande native (derive/simplify/expand/integrate/solve), l'exécute
    /// puis re-parse le résultat en Id.
    fn parseOrDispatch(self: *Heaven, s: []const u8) HeavenError!Id {
        // ─── type <expr> : retourne le type comme littéral string ───
        if (std.mem.startsWith(u8, s, "type ")) {
            const inner = std.mem.trim(u8, s["type ".len..], " \t");
            const ty_str = try self.evalTypeExpr(inner);
            defer self.allocator.free(ty_str);
            const sym = try self.store.interner.intern(ty_str);
            return try self.store.lit(.{ .str = sym });
        }

        const prefixes = [_]struct { p: []const u8, f: enum { derive, simplify, expand, integrate } }{
            .{ .p = "derive ", .f = .derive },
            .{ .p = "simplify ", .f = .simplify },
            .{ .p = "expand ", .f = .expand },
            .{ .p = "integrate ", .f = .integrate },
        };
        for (prefixes) |pfx| {
            if (std.mem.startsWith(u8, s, pfx.p)) {
                const inner = std.mem.trim(u8, s[pfx.p.len..], " \t");
                const result_str: []u8 = switch (pfx.f) {
                    .derive => try self.derive(inner, "x"),
                    .simplify => try self.simplify(inner),
                    .expand => try self.expand(inner),
                    .integrate => try self.integrate(inner, "x"),
                };
                defer self.allocator.free(result_str);
                return self.parseExpression(result_str);
            }
        }

        // Forme composée sans parenthèses : "handle (perform ...) logHandler"
        // On ne wrappe PAS si c'est déjà un littéral string (commence par ")
        // — sinon les strings avec espaces sont découpées.
        if (s.len > 0 and s[0] != '(' and s[0] != '"' and std.mem.indexOfScalar(u8, s, ' ') != null) {
            const wrapped = try std.fmt.allocPrint(self.allocator, "({s})", .{s});
            defer self.allocator.free(wrapped);
            return self.parseExpression(wrapped);
        }

        return self.parseExpression(s);
    }

    pub fn evalTypeExpr(self: *Heaven, src: []const u8) HeavenError![]u8 {
        // 1. Parser puis LOWER → l'inféreur n'accepte que les 6 primitives
        //    (sinon typeOf renvoie error.ExtensionNotLowered, cf. types.zig:323)
        const raw = try self.parseExpression(src);
        const id = try self.ensureLowered(raw);

        // 2. Inférence Hindley-Milner via Infer (pas TypeEnv)
        var inf = types.Infer.init(self.store, self.allocator);
        defer inf.deinit();

        const ty = inf.typeOf(id) catch |err| {
            return std.fmt.allocPrint(self.allocator, "type error: {}", .{err});
        };

        // 3. Rendu : Infer.typeStr gère ->, List, Π, _tN, ?
        return inf.typeStr(&inf.subst, ty, self.allocator);
    }

    pub fn evalGreenExpr(self: *Heaven, src: []const u8) HeavenError![]u8 {
        // 1. Parser l'expression
        const expr_id = try self.parseExpression(src);

        // 2. Handler green (idempotent — redéfinition à chaque appel, comme cmdGreen)
        if (!self.green_handler_defined) {
            const hres = self.eval("let greenHandler(v1, v2, cost) = (+ v1 v2)") catch |err| {
                return err;
            };
            self.allocator.free(hres);
            self.green_handler_defined = true;
        }

        // 3. Profiler matériel + activation du mode green
        var prof = profiler_mod.Profiler.start();
        self.engine.green_call_count = 0;
        self.engine.green_mode = true;
        defer self.engine.green_mode = false;

        // 4. Construire l'AST (handle <expr> greenHandler)
        const handle_op = try self.store.sym("handle");
        const handler_sym = try self.store.sym("greenHandler");
        var args_buf = [_]expr.Id{ expr_id, handler_sym };
        const handle_node = try self.store.apply(handle_op, &args_buf);

        // 5. Évaluer avec interception des effets
        self.engine.fuel = 1_000_000;
        const result = self.evaluateExpr(handle_node) catch |err| {
            _ = prof.stop(); // ne pas fuiter les métriques
            return err;
        };

        // 6. Arrêter le profiler
        const metrics = prof.stop();

        const result_str = try expr.toStringInfix(self.store, result, self.allocator);
        defer self.allocator.free(result_str);

        // 7. Sortie composable, une seule ligne
        return std.fmt.allocPrint(
            self.allocator,
            "{s} (green calls: {d}, cpu: {d}ns, wall: {d}ns, energy: {d:.3}J)",
            .{
                result_str,
                self.engine.green_call_count,
                metrics.cpu_time_ns,
                metrics.wall_time_ns,
                metrics.energy_joules,
            },
        );
    }

    /// Égalité sémantique : même e-class après saturation, OU intersection
    /// des formes pliées (foldConstants) des deux classes.
    fn egraphSemanticEq(self: *Heaven, a: Id, b: Id) bool {
        // Guard : arbre invalide = corruption en amont → échec propre + log
        if (a >= self.store.len() or b >= self.store.len()) {
            platform.dbg("[egraphSemanticEq] SKIP: id racine invalide a={d} b={d} (len={d})\n", .{ a, b, self.store.len() });
            return false;
        }
        if (!self.validExprTree(a)) {
            platform.dbg("[egraphSemanticEq] SKIP: arbre A invalide (id={d})\n", .{a});
            return false;
        }
        if (!self.validExprTree(b)) {
            platform.dbg("[egraphSemanticEq] SKIP: arbre B invalide (id={d})\n", .{b});
            return false;
        }
        var egraph = egraph_mod.EGraph.init(self.store, self.allocator);
        defer egraph.deinit();
        const ca = egraph.addExpr(a) catch return false;
        const cb = egraph.addExpr(b) catch return false;
        var rewriter = egraph_rewriter_mod.Rewriter.init(&egraph, self.store, self.allocator);
        defer rewriter.deinit();
        _ = rewriter.saturate(10000) catch return false;

        const ra = egraph.uf.find(ca);
        const rb = egraph.uf.find(cb);
        if (ra == rb) return true;

        // Intersection des formes pliées :
        // classe A contient (+ (* 2 3) (* 2 x)) — distributivité
        //   → plié en (+ 6 (* 2 x))
        // classe B contient (+ 6 (* 2 x)) — commutativité
        //   → INTERSECTION ✓
        for (egraph.classes.items, 0..) |*eca, ia| {
            if (egraph.uf.find(@intCast(ia)) != ra) continue;
            for (eca.nodes.items) |na| {
                const fa = self.math.foldConstants(na) catch continue;
                for (egraph.classes.items, 0..) |*ecb, ib| {
                    if (egraph.uf.find(@intCast(ib)) != rb) continue;
                    for (ecb.nodes.items) |nb| {
                        const fb = self.math.foldConstants(nb) catch continue;
                        if (self.math.structuralEq(fa, fb)) return true;
                    }
                }
            }
        }
        return false;
    }

    fn ensureCommands(self: *Heaven) ?*commands_mod.Commands {
        if (self.commands) |c| return c;

        const skills = self.allocator.create(skill_lib.SkillRegistry) catch return null;
        skills.* = skill_lib.SkillRegistry.init(self.allocator);
        self.skills = skills;

        const qtt_env = self.allocator.create(std.StringHashMapUnmanaged(u2)) catch return null;
        qtt_env.* = .{};
        self.qtt_env = qtt_env;

        const pc = self.allocator.create(proof_core_mod.ProofCore) catch return null;
        pc.* = proof_core_mod.ProofCore.init(self.allocator);
        self.proof_core_inst = pc;

        const agent = self.allocator.create(agent_mod.Agent) catch return null;
        agent.* = agent_mod.Agent.init(self.allocator);
        self.agent_inst = agent;

        // ⚠️ Piège : Commands.init écrase parser.* = Parser.init(...)
        // → le Heaven et le Commands partagent le MÊME parser pointé.
        // C'est OK (le parser est sans état), mais il faut passer un pointeur valide.
        const cmds = self.allocator.create(commands_mod.Commands) catch return null;
        cmds.* = commands_mod.Commands.init(
            self.store,
            &self.engine,
            &self.env,
            self.bridge,
            self.allocator,
            self.parser,
            &self.math,
            self.kb,
            skills,
            qtt_env,
            pc,
            agent,
            &self.active_theorem,
            &self.pending_proof_request,
        ) catch {
            self.allocator.destroy(cmds);
            return null;
        };
        self.commands = cmds;
        return cmds;
    }

    fn validExprTree(self: *Heaven, id: Id) bool {
        if (id >= self.store.len()) return false;
        const node = self.store.get(id);
        switch (node.tag) {
            .apply => {
                if (!self.validExprTree(node.payload)) return false;
                for (self.store.spanSliceConst(node.span_a)) |child| {
                    if (!self.validExprTree(child)) return false;
                }
            },
            .relation => {
                for (self.store.spanSliceConst(node.span_a)) |child| {
                    if (!self.validExprTree(child)) return false;
                }
                for (self.store.spanSliceConst(node.span_b)) |child| {
                    if (!self.validExprTree(child)) return false;
                }
            },
            .lambda => {
                for (self.store.spanSliceConst(node.span_a)) |child| {
                    if (!self.validExprTree(child)) return false;
                }
            },
            .bind => {
                if (node.aux < self.store.len()) {
                    if (!self.validExprTree(node.aux)) return false;
                }
            },
            else => {},
        }
        return true;
    }

    // ═══════════════════════════════════════════════════════════════
    // Holes — création, affichage, raffinement
    // ═══════════════════════════════════════════════════════════════

    pub fn freshHole(self: *Heaven) !Id {
        const id = try self.hole_state.fresh(self.store);
        self.hole_state.last_root_expr = self.last_root_expr;
        return id;
    }

    pub fn refineHole(self: *Heaven, hole_id: u32, expr_src: []const u8) !void {
        const expression = try self.parseExpression(expr_src);
        try self.hole_state.refine(hole_id, expression);
    }

    pub fn hasUnresolvedHoles(self: *Heaven, id: Id) bool {
        return self.hole_state.hasUnresolved(self.store, id);
    }

    fn findHoleParent(self: *Heaven, root: Id, hole_id: u32) ?Id {
        if (root >= self.store.len()) return null;
        const node = self.store.get(root);
        if (node.tag == .hole and node.payload == hole_id) return root;
        for (self.store.spanSliceConst(node.span_a)) |c| {
            if (self.findHoleParent(c, hole_id)) |p| return p;
        }
        for (self.store.spanSliceConst(node.span_b)) |c| {
            if (self.findHoleParent(c, hole_id)) |p| return p;
        }
        return null;
    }

    fn findParentOf(self: *Heaven, root: Id, target: Id) ?Id {
        if (root >= self.store.len()) return null;
        const node = self.store.get(root);
        const ca = self.store.spanSliceConst(node.span_a);
        const cb = self.store.spanSliceConst(node.span_b);
        for (ca) |c| if (c == target) return root;
        for (cb) |c| if (c == target) return root;
        for (ca) |c| if (self.findParentOf(c, target)) |p| return p;
        for (cb) |c| if (self.findParentOf(c, target)) |p| return p;
        return null;
    }

    fn inferHoleType(self: *Heaven, hole_id: u32) !?Id {
        const root = self.hole_state.last_root_expr orelse return null;
        const hole_node = self.findHoleParent(root, hole_id) orelse return null;
        const parent = self.findParentOf(root, hole_node) orelse return null;
        const pnode = self.store.get(parent);

        if (pnode.tag == .apply) {
            const fnode = self.store.get(pnode.payload);
            if (fnode.tag == .sym) {
                const op = self.store.interner.resolve(fnode.payload);
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or
                    std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or
                    std.mem.eql(u8, op, "%") or std.mem.eql(u8, op, "^"))
                {
                    return try self.store.sym("Int");
                }
                if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
                    std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">") or
                    std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">="))
                {
                    return try self.store.sym("Bool");
                }
            }
        }
        return null;
    }

    fn typeStrForId(self: *Heaven, ty: Id) ![]u8 {
        var inf = types.Infer.init(self.store, self.allocator);
        defer inf.deinit();
        return inf.typeStr(&inf.subst, ty, self.allocator);
    }

    pub fn describeHole(self: *Heaven, hole_id: u32) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        if (!self.hole_state.holes.contains(hole_id)) {
            try w.print("?{d} (unknown hole)\n", .{hole_id});
            return buf.toOwnedSlice(self.allocator);
        }

        if (try self.inferHoleType(hole_id)) |ty| {
            const ty_str = self.typeStrForId(ty) catch "?";
            defer if (ty_str.ptr != "?".ptr) self.allocator.free(ty_str);
            try w.print("?{d} : {s}\n", .{ hole_id, ty_str });
        } else {
            try w.print("?{d} : ?\n", .{hole_id});
        }

        if (self.hole_state.resolve(hole_id)) |resolved| {
            const r_str = expr.toStringInfix(self.store, resolved, self.allocator) catch "<expr>";
            defer if (r_str.ptr != "<expr>".ptr) self.allocator.free(r_str);
            try w.print("  refined to: {s}\n", .{r_str});
        } else {
            try w.writeAll("  not refined\n");
        }

        return buf.toOwnedSlice(self.allocator);
    }

    pub fn describeAllHoles(self: *Heaven) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        if (self.hole_state.holes.count() == 0) {
            try w.writeAll("(no holes)\n");
            return buf.toOwnedSlice(self.allocator);
        }

        const ids = try self.hole_state.listIds(self.allocator);
        defer self.allocator.free(ids);

        for (ids) |id| {
            const desc = try self.describeHole(id);
            defer self.allocator.free(desc);
            try w.writeAll(desc);
        }
        return buf.toOwnedSlice(self.allocator);
    }
};

fn substSymByName(
    store: *Store,
    allocator: std.mem.Allocator,
    e: expr.Id,
    name: []const u8,
    repl: expr.Id,
) !expr.Id {
    if (e >= store.len()) return e;
    const node = store.get(e);
    switch (node.tag) {
        .sym => {
            const s = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, s, name)) return repl;
            return e;
        },
        .apply => {
            const new_func = try substSymByName(store, allocator, node.payload, name, repl);
            const all = store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try allocator.dupe(expr.Id, all[1..]);
            defer allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(expr.Id) = .{};
            defer new_args.deinit(allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try substSymByName(store, allocator, a, name, repl);
                try new_args.append(allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return store.apply(new_func, new_args.items);
        },
        else => return e,
    }
}

fn isInfixOp(tok: []const u8) bool {
    const ops = [_][]const u8{ "+", "-", "*", "/", "^", "%", "==", "!=", "<", ">", "<=", ">=", ">>>" };
    for (ops) |o| {
        if (std.mem.eql(u8, tok, o)) return true;
    }
    return false;
}

fn parseHeavenExpr(ctx: *anyopaque, input: []const u8) engine_expr.EvalError!expr.Id {
    const heaven = @as(*Heaven, @ptrCast(@alignCast(ctx)));
    return heaven.parseExpression(input) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TypeError,
    };
}

fn deriveIdHeavenExpr(ctx: *anyopaque, input: []const u8, var_name: []const u8) engine_expr.EvalError!expr.Id {
    const heaven = @as(*Heaven, @ptrCast(@alignCast(ctx)));
    return heaven.deriveToId(input, var_name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TypeError,
    };
}

fn simplifyHeavenExpr(ctx: *anyopaque, input: []const u8) engine_expr.EvalError![]const u8 {
    const heaven = @as(*Heaven, @ptrCast(@alignCast(ctx)));
    const result = heaven.simplify(input) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TypeError,
    };
    return result;
}

test "parseExpression — lambda courte λx.x" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("(λx.x)");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.lambda, node.tag);
    try std.testing.expectEqualStrings("x", heaven.store.interner.resolve(node.payload));
}

test "parseExpression — application sur lambda courte" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("((λx.x) 42)");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.apply, node.tag);
}

test "tactics v1.5 — rewrite a=b dans la cible" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(
        allocator, &arena, heaven.store, "rewrite_test",
    );
    defer state.deinit();

    // H : a = b
    const a = try heaven.store.sym("a");
    const b = try heaven.store.sym("b");
    const eq_sym = try heaven.store.sym("=");
    const h_ty = try heaven.store.apply(eq_sym, &.{ a, b });

    // Cible : Eq(f a, f b)
    const f = try heaven.store.sym("f");
    const fa = try heaven.store.apply(f, &.{a});
    const fb = try heaven.store.apply(f, &.{b});
    const target = try heaven.store.apply(eq_sym, &.{ fa, fb });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .rewrite = h_name }, &ctx);
    try tactics_mod.applyTactic(&state, .reflexivity, &ctx);

    try std.testing.expect(state.solved());
}

test "tactics v1.5 — apply P->Q crée un sous-but P" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(
        allocator, &arena, heaven.store, "apply_test",
    );
    defer state.deinit();

    // H : P -> Q
    const P = try heaven.store.sym("P");
    const Q = try heaven.store.sym("Q");
    const arrow = try heaven.store.sym("->");
    const h_ty = try heaven.store.apply(arrow, &.{ P, Q });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = Q,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .apply = h_name }, &ctx);

    try std.testing.expectEqual(@as(usize, 1), state.goals.items.len);
    try std.testing.expect(state.goals.items[0].target == P);
}

test "ProofSession — interactif pas à pas" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    // Déclare un théorème
    const stmt_res = try heaven.eval("theorem t_repl_test : x + 0 = x");
    defer allocator.free(stmt_res);

    // Démarre la session
    var session = try heaven.startProof("t_repl_test");
    defer session.deinit();

    // Une ligne de tactique
    const report1 = try session.applyLine("simplify");
    defer allocator.free(report1);
    try std.testing.expect(std.mem.indexOf(u8, report1, "solved") != null or
        std.mem.indexOf(u8, report1, "✓") != null);

    // Fin
    try std.testing.expect(try session.finish());
}

test "tactics v3 — assumption matche une hypothèse" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "assum_test");
    defer state.deinit();

    // H : P ; cible : P
    const P = try heaven.store.sym("P");
    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = P };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = P,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, .assumption, &ctx);
    try std.testing.expect(state.solved());
}

test "hole — fresh hole has unique id" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const h0 = try heaven.freshHole();
    const h1 = try heaven.freshHole();

    try std.testing.expect(h0 != h1);
    try std.testing.expectEqual(@as(u32, 2), heaven.hole_state.next_id);
}

test "hole — _ parses to a hole node" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("_");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.hole, node.tag);
}

test "hole — refine and describe" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const hole_node_id = try heaven.freshHole();
    const hole_id = heaven.store.get(hole_node_id).payload;

    try heaven.refineHole(hole_id, "42");

    const desc = try heaven.describeHole(hole_id);
    defer allocator.free(desc);

    try std.testing.expect(std.mem.indexOf(u8, desc, "refined to: 42") != null);
}

test "hole — hasUnresolvedHoles" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const h = try heaven.freshHole();
    const h_id = heaven.store.get(h).payload;
    const one = try heaven.store.int(1);

    // (+ _ 1) contient un trou non raffiné
    const op = try heaven.store.sym("+");
    const expr_with_hole = try heaven.store.apply(op, &.{ h, one });
    try std.testing.expect(heaven.hasUnresolvedHoles(expr_with_hole));

    // Après raffinement, plus de trou non raffiné
    try heaven.refineHole(h_id, "42");
    try std.testing.expect(!heaven.hasUnresolvedHoles(expr_with_hole));
}
