//! Frontend Heaven - intégration du moteur de simplification EGraph
const std = @import("std");
const expr = @import("expr");
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
} || std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine_expr.EvalError;

const MacroDef = struct {
    params: []const []const u8,
    body: Id,
};

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
        };

        // Définir la vtable
        const heaven_vtable = engine_expr.HeavenVTable{
            .parse = parseHeavenExpr,
            .deriveId = deriveIdHeavenExpr,
            .simplify = simplifyHeavenExpr,
        };

        // Initialiser l'engine
        var eng = engine_expr.Engine.init(allocator, store, &self.env, @ptrCast(self), &heaven_vtable);
        self.engine = eng;

        // Initialiser le parser avec l'engine maintenant disponible
        parser.* = parse_mod.Parser.init(store, &eng, &self.env, allocator);

        // Initialiser math
        self.math = math_mod.Math.init(store, &eng, bridge, parser, allocator);

        // Initialiser kb, simplify_eng, proof_core
        const kb = try allocator.create(transform_mod.KnowledgeBase);
        kb.* = transform_mod.KnowledgeBase.init(allocator);
        self.kb = kb;

        const simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, &eng, &self.env, kb, allocator);
        self.simplify_eng = simplify_eng;

        const proof_core = proof.ProofEnv.init(allocator);
        self.proof_core = proof_core;

        // Ajouter les règles par défaut
        try self.addDefaultRules();

        // Charger le noyau logique (bootstrap.hvn) dans le FunctionRegistry
        self.loadBootstrap();

        return self;
    }

    fn loadBootstrap(self: *Heaven) void {
        const source = platform.fs.cwd().readFileAlloc(
            self.allocator, "core/bootstrap.hvn", 64 * 1024,
        ) catch |err| {
            platform.dbg("[loadBootstrap] readFileAlloc failed: {}\n", .{err});
            return;
        };
        defer self.allocator.free(source);

        var tmp_registry = engine_expr.FunctionRegistry.init(self.allocator);
        defer tmp_registry.deinit();

        _ = elab_mod.elaborateSource(
            self.allocator, self.store, source, &tmp_registry,
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
    }

    pub fn ensureInit(self: *Heaven) void {
        _ = self;
    }

    pub fn registerClause(self: *Heaven, name: []const u8, patterns: []const Id, body: Id) !void {
        const owned_key = try self.engine.allocator.dupe(u8, name);
        const result = try self.engine.fns.getOrPut(self.engine.allocator, owned_key);
        if (result.found_existing) {
            self.engine.allocator.free(owned_key);   // ← clé redondante, getOrPut garde l'existante
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
                const body    = std.mem.trim(u8, rest_native[in_pos + 4 ..], " \t");

                if (std.mem.indexOfScalar(u8, binding, '=')) |eq| {
                    const name = std.mem.trim(u8, binding[0..eq], " \t:");
                    const val  = std.mem.trim(u8, binding[eq + 1 ..], " \t");

                    var buf = std.ArrayListUnmanaged(u8){};
                    defer buf.deinit(self.allocator);
                    const head = if (qtt_kw) |kw|
                        try std.fmt.allocPrint(self.allocator, "let-{s}", .{kw})
                    else
                        try self.allocator.dupe(u8, "let");
                    defer self.allocator.free(head);
                    try buf.writer(self.allocator).print("({s} {s} {s} {s})",
                        .{ head, name, val, body });

                    if (self.parseExpression(buf.items)) |id| {
                        const result = self.interpForAssert(id) catch id;
                        return try expr.toStringInfix(self.store, result, self.allocator);
                    } else |err| switch (err) {
                        error.LinearViolation => return std.fmt.allocPrint(self.allocator,
                            "linear violation: '{s}' declared {s}, used wrong number of times",
                            .{ name, qtt_kw orelse "many" }),
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

        // ✅ ROUTING S-EXPR : (let ...) / (lambda ...) / (+ 1 2) / toute S-expr pure
        if (trimmed.len > 0 and trimmed[0] == '(') {
            // let/lambda → interpForAssert (engine ne gère pas bind au top-level)
            if (std.mem.indexOf(u8, trimmed, "let ") != null or
                std.mem.indexOf(u8, trimmed, "lambda") != null)
            {
                if (self.parseExpression(trimmed)) |id| {
                    const result = self.interpForAssert(id) catch id;
                    return try expr.toStringInfix(self.store, result, self.allocator);
                } else |_| {}
            }
            // Autres S-expr : parse + engine.eval direct
            if (self.parseExpression(trimmed)) |id| {
                self.engine.fuel = 1_000_000;
                const evaluated = self.engine.eval(id) catch id;
                return try expr.toStringInfix(self.store, evaluated, self.allocator);
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

        // ─── DÉFINITION DE FONCTION (syntaxe équationnelle) ───
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
            const rhs = std.mem.trim(u8, trimmed[eq_pos+1..], " ");
            if (!std.mem.startsWith(u8, lhs, "(") and lhs.len > 0 and rhs.len > 0) {
                return self.evalEquation(lhs, rhs);
            }
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
                if (depth == 0 and !in_token) { start = i; in_token = true; }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, trimmed[start..i+1]);
                    in_token = false;
                    start = i+1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, trimmed[start..i]);
                    in_token = false;
                }
                start = i+1;
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
                if (std.mem.eql(u8, func_name, op)) { is_op = true; break; }
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
        return self.allocator.dupe(u8, trimmed);
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
                if (depth == 0 and !in_token) { start = i; in_token = true; }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, lhs[start..i+1]);
                    in_token = false;
                    start = i+1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, lhs[start..i]);
                    in_token = false;
                }
                start = i+1;
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
                // Fallback : atome simple (ex: "+", identifiant exotique)
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
            if (i + 1 < trimmed.len and std.mem.trim(u8, trimmed[i + 1 ..], " ").len > 0)
                return error.InvalidSyntax;

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
        for (inner, 0..) |ch, idx| {
            switch (ch) {
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
        platform.dbg("[parseSExpr] first token: '{s}' (len={d})\n", .{ first, first.len });

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
                const arg_id = try self.parseExpression(arg_tok);
                try args.append(self.allocator, arg_id);
            }
            return self.store.apply(func_id, args.items);
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
            var qtt_val:  []const u8 = "";
            var qtt_body: ?expr.Id = null;

            if (std.mem.eql(u8, first, "let-linear") and tokens.items.len == 4) {
                kw = "linear";
                qtt_name = tokens.items[1];
                qtt_val  = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-erased") and tokens.items.len == 4) {
                kw = "erased";
                qtt_name = tokens.items[1];
                qtt_val  = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let-many") and tokens.items.len == 4) {
                kw = "many";
                qtt_name = tokens.items[1];
                qtt_val  = tokens.items[2];
                qtt_body = try self.parseExpression(tokens.items[3]);
            } else if (std.mem.eql(u8, first, "let") and tokens.items.len >= 7) {
                const k = tokens.items[1];
                const is_kw = std.mem.eql(u8, k, "linear")
                        or std.mem.eql(u8, k, "erased")
                        or std.mem.eql(u8, k, "many");
                if (is_kw and std.mem.eql(u8, tokens.items[3], "=")
                        and std.mem.eql(u8, tokens.items[5], "in"))
                {
                    kw = k;
                    qtt_name = tokens.items[2];
                    qtt_val  = tokens.items[4];

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
                    true;   // many : aucune contrainte

                if (!ok) return error.LinearViolation;

                const val_id = try self.parseExpression(qtt_val);
                const let_sym  = try self.store.sym("let");
                const name_sym = try self.store.sym(qtt_name);
                var args = [_]expr.Id{ name_sym, val_id, b };
                return self.store.apply(let_sym, &args);
            }
        }

        // Cas 3 : application normale
        const func_id = try self.store.sym(first);
        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);
        for (tokens.items[1..]) |arg_tok| {
            const arg_id = try self.parseExpression(arg_tok);
            try args.append(self.allocator, arg_id);
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
        return self.allocator.dupe(u8, src);
    }
    pub fn evalProve(self: *Heaven, src: []const u8) HeavenError![]u8 {
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
        if (node.tag != .apply) {
            return self.evaluateExpr(id) catch id;   // ✅ Fix 1 : syms nus évalués
        }

        const all = self.store.spanSliceConst(node.span_a);
        if (all.len < 1) return id;
        const args = all[1..];

        const fnode = self.store.get(node.payload);

        platform.dbg("[preFix2] func_tag={s} args.len={d}\n", .{ @tagName(fnode.tag), args.len });

        // ✅ Fix 2a : FUNC = LAMBDA NODE (lambdaNative : payload=param, span_a=[body])
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

        // ✅ Fix 2b : FUNC = APPLY sym"lambda" (structure alternative du parser)
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

        // ✅ Fix 3 : FONCTION ENV-BOUND (f arg) où f est une lambda dans l'env
        // L'engine ne cherche l'env que pour les syms nus — pas les appels.
        {
            platform.dbg("[fix3-enter] fnode.payload={d} env has: ", .{fnode.payload});
            if (self.env.get(fnode.payload)) |bound| {
                platform.dbg("YES bound.tag={s}\n", .{@tagName(self.store.get(bound).tag)});
                // bound = la valeur liée (peut être un nœud .lambda !)
                const bound_node = self.store.get(bound);
                
                // ✅ Cas .lambda : appliquer directement (payload=param, span_a=[body])
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
                
                // ✅ Cas .apply sym"lambda" (structure alternative)
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

        if (fnode.tag != .sym) return id;
        const head = self.store.interner.resolve(fnode.payload);

        // ✅ DUMP : la structure complète du nœud
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
        if (std.mem.eql(u8, head, "let") and args.len == 3) {
            const val = self.evaluateExpr(args[1]) catch args[1];
            const var_node = self.store.get(args[0]);
            if (var_node.tag == .sym) {
                try self.env.put(var_node.payload, val);
                defer self.env.delete(var_node.payload);
                // ✅ RÉCURSIF : le body peut contenir d'autres let/lambdas
                return self.interpForAssert(args[2]) catch id;
            }
        }

        // ═══ 2. LAMBDA SYMBOLE : ((lambda x body) arg) — le func est apply(sym"lambda") ═══
        {
            const func_node = self.store.get(node.payload);
            if (func_node.tag == .apply) {
                const inner = self.store.get(func_node.payload);
                if (inner.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(inner.payload), "lambda")) {
                    const lam_args = self.store.spanSliceConst(func_node.span_a);
                    if (lam_args.len == 3) {   // [lambda, param, body]
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
                platform.dbg("[interp3] head='{s}' bound.tag={s}\n", .{ head, @tagName(self.store.get(bound).tag) });
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
        } else |_| {}

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
        const handle_op   = try self.store.sym("handle");
        const handler_sym = try self.store.sym("greenHandler");
        var args_buf = [_]expr.Id{ expr_id, handler_sym };
        const handle_node = try self.store.apply(handle_op, &args_buf);

        // 5. Évaluer avec interception des effets
        self.engine.fuel = 1_000_000;
        const result = self.evaluateExpr(handle_node) catch |err| {
            _ = prof.stop();     // ne pas fuiter les métriques
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
        // ✅ Guard : arbre invalide = corruption en amont → échec propre + log
        if (a >= self.store.len() or b >= self.store.len()) {
            platform.dbg("[egraphSemanticEq] SKIP: id racine invalide a={d} b={d} (len={d})\n",
                .{ a, b, self.store.len() });
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
};


fn isInfixOp(tok: []const u8) bool {
    const ops = [_][]const u8{ "+", "-", "*", "/", "^", "%", "==", "!=", "<", ">", "<=", ">=" };
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
