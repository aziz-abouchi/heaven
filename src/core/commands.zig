//! Commandes shell et évaluation pour Heaven
//! Extrait de heaven_expr.zig pour modularité

const std = @import("std");
const expr = @import("expr");
const ShellParser = @import("shell_parser").ShellParser;
const proofs_ops = @import("proofs_ops");
const parse_ops = @import("parse_ops");
const cas_ops = @import("cas_ops");
const defs_ops = @import("defs_ops");

const Allocator = std.mem.Allocator;
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
const bridge_expr = @import("bridge_expr");
const Engine = engine_expr.Engine;
const codegen_c = @import("codegen_expr_c");
const codegen_js = @import("codegen_expr_js");
const codegen_latex = @import("codegen_expr_latex");
const matrix_bridge_mod = @import("matrix_bridge");
const types_mod = @import("types");
const egraph_mod = @import("egraph");
const canon_mod = @import("canon");
const proof_lib = @import("proof");
const skill_lib = @import("skill");
const mir = @import("mir");
const x86_64 = @import("x86_64");
const proof_core = @import("proof_core");
const platform = @import("platform");
const transform_mod = @import("transform");
const pattern_mod = @import("pattern");
const elab_mod = @import("elab");
const agent_mod = @import("agent");
const parse_mod = @import("parse");
const math_mod = @import("math");
const proof_helpers_mod = @import("proof_helpers");
const simplify_engine_mod = @import("simplify_engine");
const rules_mod = @import("rules");

const debug = platform.getenv("HEAVEN_DEBUG") != null;
// HEAVEN_DEBUG=1 ./heaven pour activer les logs.

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
} || std.mem.Allocator.Error || mir.MirError || engine_expr.EvalError;

pub const Commands = struct {
    store: *Store,
    engine: *Engine,
    env: *engine_expr.Env,
    bridge: *matrix_bridge_mod.MatrixBridge,
    allocator: Allocator,
    parser: *parse_mod.Parser,
    math: *math_mod.Math,
    kb: *transform_mod.KnowledgeBase,
    skills: *skill_lib.SkillRegistry,
    qtt_env: *std.StringHashMapUnmanaged(u2),
    proof_core: *proof_core.ProofCore,
    agent: *agent_mod.Agent,
    active_theorem: *?[]const u8,
    pending_proof_request: *?[]const u8,
    proof_helpers: proof_helpers_mod.ProofHelpers,
    simplify_eng: simplify_engine_mod.SimplifyEngine,
    shell_parser: ShellParser,

    pub fn init(
        store: *Store,
        engine: *Engine,
        env: *engine_expr.Env,
        bridge: *matrix_bridge_mod.MatrixBridge,
        allocator: Allocator,
        parser: *parse_mod.Parser,
        math: *math_mod.Math,
        kb: *transform_mod.KnowledgeBase,
        skills: *skill_lib.SkillRegistry,
        qtt_env: *std.StringHashMapUnmanaged(u2),
        proof_core_: *proof_core.ProofCore,
        agent: *agent_mod.Agent,
        active_theorem: *?[]const u8,
        pending_proof_request: *?[]const u8,
    ) !Commands {
        const shell_parser = try ShellParser.init(allocator);
        parser.* = parse_mod.Parser.init(store, engine, env, allocator);
        return .{
            .store = store,
            .engine = engine,
            .env = env,
            .bridge = bridge,
            .allocator = allocator,
            .parser = parser,
            .math = math,
            .kb = kb,
            .skills = skills,
            .qtt_env = qtt_env,
            .proof_core = proof_core_,
            .agent = agent,
            .active_theorem = active_theorem,
            .pending_proof_request = pending_proof_request,
            .proof_helpers = proof_helpers_mod.ProofHelpers.init(store, allocator),
            .simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, engine, env, kb, allocator),
            .shell_parser = shell_parser,
        };
    }

    pub fn deinit(self: *Commands) void {
        if (self.active_theorem.*) |th| {
            self.allocator.free(th);
            self.active_theorem.* = null;
        }

        self.shell_parser.deinit();
    }

    pub fn initDefaultRules(self: *Commands) !void {
        const rules = [_]struct { op: []const u8, a_is_var: bool, b_val: i64, result_is_var: bool }{
            .{ .op = "+", .a_is_var = true, .b_val = 0, .result_is_var = true },
            .{ .op = "+", .a_is_var = false, .b_val = 0, .result_is_var = true },
            .{ .op = "*", .a_is_var = true, .b_val = 1, .result_is_var = true },
            .{ .op = "*", .a_is_var = false, .b_val = 1, .result_is_var = true },
            .{ .op = "*", .a_is_var = true, .b_val = 0, .result_is_var = false },
            .{ .op = "*", .a_is_var = false, .b_val = 0, .result_is_var = false },
        };

        for (rules) |r| {
            const x = try self.store.sym("x");
            const val = try self.store.int(r.b_val);
            const lhs = if (r.a_is_var)
                try self.store.binop(r.op, x, val)
            else
                try self.store.binop(r.op, val, x);
            const rhs = if (r.result_is_var) x else val;
            const rule = try self.store.relation("=>", &.{ lhs, rhs }, &.{});
            try self.kb.rules.append(self.allocator, rule);
        }
        {
            const x = try self.store.sym("x");
            const zero = try self.store.int(0);
            const lhs = try self.store.binop("-", x, zero);
            const rule = try self.store.relation("=>", &.{ lhs, x }, &.{});
            try self.kb.rules.append(self.allocator, rule);
        }
    }

    /// Pipeline canonique de simplification : parse → lower →
    /// basic → EGRAPH → basic. Délègue à Heaven.simplifyToId
    /// (heaven_expr.zig:2162) — la voie REPL éprouvée.
    ///
    /// Contexte soundness : « theorem a = b » était prouvé via
    /// l'ancienne voie textuelle de verifyBySimplify (comparaison
    /// de chaînes normalisant l'ordre des opérandes). Ce pipeline
    /// structurel sur Id remplace toute comparaison de chaînes.
    pub fn simplifyToId(self: *Commands, input: []const u8) !Id {
        return cas_ops.simplifyToId(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }

    pub fn eval(self: *Commands, input: []const u8) HeavenError![]u8 {
        const trimmed0 = std.mem.trim(u8, input, " \t\r\n");
        const actual = if (trimmed0.len > 0 and trimmed0[0] == ':') trimmed0[1..] else trimmed0;
        const trimmed = std.mem.trim(u8, actual, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "module ") or
            std.mem.startsWith(u8, trimmed, "data ") or
            std.mem.startsWith(u8, trimmed, "zero :") or
            std.mem.startsWith(u8, trimmed, "succ :"))
        {
            return try self.allocator.dupe(u8, "()");
        }

        // Let : tout ce qui commence par "let " passe par un dispatch unifié.
        // - let actor X = ... with H
        // - let macro name(...) = ...
        // - let [linear|erased|many] x = v in b
        // - let x = v in b
        // - let x := v
        if (std.mem.startsWith(u8, trimmed, "let ")) {
            const after = trimmed["let ".len..];
            if (std.mem.startsWith(u8, after, "actor ")) {
                return self.evalActorDef(after["actor ".len..], self.env);
            }
            if (std.mem.startsWith(u8, after, "macro ")) {
                return self.evalMacroDef(after["macro ".len..]);
            }
            // let x = v in b, let linear x = v in b, let x := v
            if (std.mem.indexOf(u8, after, " in ") != null or
                std.mem.indexOf(u8, after, ":=") != null)
            {
                return self.evalLet(after);
            }
        }

        // === INTERCEPTION (simplify ...) avec parenthèses ===
        if (std.mem.startsWith(u8, trimmed, "(simplify ")) {
            const inner = trimmed["(simplify ".len .. trimmed.len - 1];
            return self.evalSimplify(inner);
        }

        if (std.mem.startsWith(u8, trimmed, "(test ") or std.mem.startsWith(u8, trimmed, "(assert_eq ")) {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch id;
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        if (std.mem.startsWith(u8, trimmed, "(handle ") or std.mem.startsWith(u8, trimmed, "(perform ")) {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch id;
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        // Dispatch spécial pour (let ...) et (letrec ...)
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
            if (std.mem.startsWith(u8, inner, "let ") or std.mem.startsWith(u8, inner, "letrec ")) {
                const id = try self.parser.parseSExpr(trimmed);
                self.engine.fuel = 1_000_000;
                const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch id;
                return expr.toStringInfix(self.store, result, self.allocator);
            }
        }
        
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const id = try self.bridge.importExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "eval error: {s}", .{@errorName(err)});
            };
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        if (std.mem.indexOf(u8, trimmed, ":=") != null) {
            const walrus_pos = std.mem.indexOf(u8, trimmed, ":=") orelse unreachable;
            const lhs = std.mem.trim(u8, trimmed[0..walrus_pos], " ");

            // Détecter si c'est une définition de fonction (LHS avec paramètres)
            var token_count: usize = 0;
            var tok_it = std.mem.tokenizeScalar(u8, lhs, ' ');
            while (tok_it.next()) |_| token_count += 1;

            if (token_count >= 2 or std.mem.indexOfScalar(u8, lhs, '(') != null) {
                // C'est une fonction : construire une nouvelle string avec = au lieu de :=
                const before = trimmed[0..walrus_pos];
                const after = trimmed[walrus_pos + 2 ..];
                const converted = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ before, after });
                defer self.allocator.free(converted);
                return self.evalFnDef(converted);
            }

            // Sinon c'est un binding simple
            return self.evalLet(trimmed);
        }

        const eq_idx = blk: {
            var i: usize = 0;
            while (i < trimmed.len) {
                if (trimmed[i] == '=') {
                    if (i + 1 < trimmed.len and trimmed[i + 1] == '=') {
                        i += 2;
                        continue;
                    }
                    break :blk i;
                }
                i += 1;
            }
            break :blk null;
        };
        if (eq_idx) |eq_pos| {
            const is_lambda = std.mem.startsWith(u8, trimmed, "fun ") or
                std.mem.startsWith(u8, trimmed, "λ ") or
                std.mem.startsWith(u8, trimmed, "fn(") or
                std.mem.startsWith(u8, trimmed, "\\") or
                (trimmed.len > 0 and trimmed[0] == '|') or
                std.mem.indexOf(u8, trimmed, "=>") != null or
                std.mem.indexOf(u8, trimmed, "->") != null;

            if (!is_lambda and !std.mem.startsWith(u8, trimmed, "let ") and
                !std.mem.startsWith(u8, trimmed, "let macro ") and
                !std.mem.startsWith(u8, trimmed, "let actor ") and
                !std.mem.startsWith(u8, trimmed, "theorem ") and
                !std.mem.startsWith(u8, trimmed, "prove ") and
                !std.mem.startsWith(u8, trimmed, "simplify ") and
                !std.mem.startsWith(u8, trimmed, "transform ") and
                !std.mem.startsWith(u8, trimmed, "type ") and
                !std.mem.startsWith(u8, trimmed, "plot ") and
                !std.mem.startsWith(u8, trimmed, "latex ") and
                !std.mem.startsWith(u8, trimmed, "explain ") and
                !std.mem.startsWith(u8, trimmed, "expand ") and
                !std.mem.startsWith(u8, trimmed, "optimize ") and
                !std.mem.startsWith(u8, trimmed, "trace ") and
                !std.mem.startsWith(u8, trimmed, "qtt ") and
                !std.mem.startsWith(u8, trimmed, "mir ") and
                !std.mem.startsWith(u8, trimmed, "asm ") and
                !std.mem.startsWith(u8, trimmed, "solve ") and
                !std.mem.startsWith(u8, trimmed, "derive ") and
                !std.mem.startsWith(u8, trimmed, "integrate ") and
                !std.mem.startsWith(u8, trimmed, "skill ") and
                !std.mem.startsWith(u8, trimmed, "ask ") and
                !std.mem.startsWith(u8, trimmed, "js ") and
                !std.mem.startsWith(u8, trimmed, "quote "))
            {
                const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
                var token_count: usize = 0;
                var tok_it = std.mem.tokenizeScalar(u8, lhs, ' ');
                while (tok_it.next()) |_| token_count += 1;

                if (token_count >= 2 or std.mem.indexOfScalar(u8, lhs, '(') != null) {
                    if (!is_lambda) {
                        return self.evalFnDef(trimmed);
                    }
                }
            }
        }

        if (std.mem.startsWith(u8, trimmed, "send(") or
            std.mem.startsWith(u8, trimmed, "spawn(") or
            std.mem.startsWith(u8, trimmed, "state("))
        {
            const apply_id = self.parseCallExpr(trimmed) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "actor parse error: {}", .{err});
            };
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, apply_id, 0) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "actor error: {}", .{err});
            };
            return expr.toString(self.store, result, self.allocator);
        }

        if (std.mem.indexOfScalar(u8, trimmed, '(') == null) {
            if (self.tryFnCall(trimmed)) |result| return result;
        }

        if (std.mem.eql(u8, trimmed, "help")) return self.evalHelp();
        if (std.mem.eql(u8, trimmed, "stats")) return self.evalStats();
        if (std.mem.eql(u8, trimmed, "theorems")) return self.evalTheorems();
        if (std.mem.eql(u8, trimmed, "meta") or std.mem.eql(u8, trimmed, "rules")) return self.evalRules();

        if (std.mem.startsWith(u8, trimmed, "let ")) return self.evalLet(trimmed["let ".len..]);
        if (std.mem.startsWith(u8, trimmed, "transform ")) return try self.evalTransform(trimmed["transform ".len..]);
        if (std.mem.startsWith(u8, trimmed, "eval ")) return self.evalSExpr(trimmed["eval ".len..]);
        if (std.mem.startsWith(u8, trimmed, "theorem ")) return self.evalTheorem(trimmed["theorem ".len..]);
        if (std.mem.startsWith(u8, trimmed, "prove ")) return self.evalProve(trimmed["prove ".len..]);
        if (std.mem.startsWith(u8, trimmed, "skill ")) return self.evalSkill(trimmed["skill ".len..]);
        if (std.mem.startsWith(u8, trimmed, "type ")) return self.evalType(trimmed["type ".len..]);

        // === MODIFICATION : evalSimplify utilise désormais simplifyWithEGraph ===
        if (std.mem.startsWith(u8, trimmed, "simplify ")) return self.evalSimplify(trimmed["simplify ".len..]);

        if (std.mem.startsWith(u8, trimmed, "rewrite ")) {
            const rest = trimmed["rewrite ".len..];
            const arrow_pos = std.mem.indexOf(u8, rest, "=>") orelse {
                return self.allocator.dupe(u8, "syntax error: expected lhs => rhs");
            };
            const lhs_str = std.mem.trim(u8, rest[0..arrow_pos], " ");
            const rhs_str = std.mem.trim(u8, rest[arrow_pos + 2 ..], " ");
            const lhs = self.parseExpression(lhs_str) catch return self.allocator.dupe(u8, "parse error in lhs");
            const rhs = self.parseExpression(rhs_str) catch return self.allocator.dupe(u8, "parse error in rhs");

            const lhs_canon = try canon_mod.canonicalize(self.store, self.allocator, lhs);
            const rhs_canon = try canon_mod.canonicalize(self.store, self.allocator, rhs);

            const rule_id = self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{}) catch return self.allocator.dupe(u8, "relation error");
            self.kb.rules.append(self.allocator, rule_id) catch return self.allocator.dupe(u8, "append error");
            return self.allocator.dupe(u8, "✓ rule added");
        }
        if (std.mem.startsWith(u8, trimmed, "plot ")) return self.evalPlot(trimmed["plot ".len..]);
        if (std.mem.startsWith(u8, trimmed, "latex ")) return self.evalLatex(trimmed["latex ".len..]);
        if (std.mem.startsWith(u8, trimmed, "explain ")) return self.evalExplain(trimmed["explain ".len..]);
        if (std.mem.startsWith(u8, trimmed, "expand ")) return self.evalExpand(trimmed["expand ".len..]);
        if (std.mem.startsWith(u8, trimmed, "optimize ")) return self.evalOptimize(trimmed["optimize ".len..]);
        if (std.mem.startsWith(u8, trimmed, "trace ")) return self.evalTrace(trimmed["trace ".len..]);
        if (std.mem.startsWith(u8, trimmed, "qtt ")) return self.evalQtt(trimmed["qtt ".len..]);
        if (std.mem.startsWith(u8, trimmed, "mir ")) return self.evalMir(trimmed["mir ".len..]);
        if (std.mem.startsWith(u8, trimmed, "solve ")) return try self.math.solve(trimmed["solve ".len..], "x");
        if (std.mem.startsWith(u8, trimmed, "derive ")) {
            const expr_str = trimmed["derive ".len..];
            const expr_id = self.parseExpression(expr_str) catch {
                return self.allocator.dupe(u8, "parse error in derive expression");
            };
            const var_id = self.store.sym("x") catch {
                return self.allocator.dupe(u8, "error: cannot create var sym");
            };
            const var_node = self.store.get(var_id);
            const var_sym = var_node.payload;
            const result = self.math.deriveExpr(expr_id, var_sym) catch |err| {
                switch (err) {
                    error.UnsupportedPowerVarExp,
                    error.UnsupportedPowerType,
                    error.UnsupportedDeriveOp,
                    => return self.allocator.dupe(u8, "error: unsupported derive operation"),
                    else => return self.allocator.dupe(u8, "0"),
                }
            };
            // Simplifier le résultat
            const lowered = try self.store.lowerRec(result);
            const simplified = try self.simplify_eng.simplifyWithEGraph(lowered, null, null);
            return expr.toStringInfix(self.store, simplified, self.allocator);
        }
        if (std.mem.startsWith(u8, trimmed, "integrate ")) return try self.math.integrate(trimmed["integrate ".len..], "x");
        if (std.mem.startsWith(u8, trimmed, "asm ")) return self.evalAsm(trimmed["asm ".len..]);
        if (std.mem.startsWith(u8, trimmed, "ask ")) return self.evalAsk(trimmed["ask ".len..]);
        if (std.mem.startsWith(u8, trimmed, "js ")) return self.evalJs(trimmed["js ".len..]);
        if (std.mem.startsWith(u8, trimmed, "green ")) return self.evalGreen(trimmed["green ".len..]);

        if (std.mem.startsWith(u8, trimmed, "derive(")) {
            const rest = trimmed["derive(".len..];
            if (std.mem.endsWith(u8, rest, ")")) {
                const inner = rest[0 .. rest.len - 1];
                if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                    const expr_str = std.mem.trim(u8, inner[0..comma], " ");
                    const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                    return self.math.derive(expr_str, var_str) catch |err| {
                        switch (err) {
                            error.UnsupportedPowerVarExp,
                            error.UnsupportedPowerType,
                            error.UnsupportedDeriveOp,
                            => return error.UnsupportedExpr,
                            else => return error.EvaluationFailed,
                        }
                    };
                }
            }
        }
        if (std.mem.startsWith(u8, trimmed, "solve(")) {
            const rest = trimmed["solve(".len..];
            if (std.mem.endsWith(u8, rest, ")")) {
                const inner = rest[0 .. rest.len - 1];
                if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                    const eq_str = std.mem.trim(u8, inner[0..comma], " ");
                    const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                    return try self.math.solve(eq_str, var_str);
                }
            }
        }
        if (std.mem.startsWith(u8, trimmed, "integrate(")) {
            const rest = trimmed["integrate(".len..];
            if (std.mem.endsWith(u8, rest, ")")) {
                const inner = rest[0 .. rest.len - 1];
                if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                    const expr_str = std.mem.trim(u8, inner[0..comma], " ");
                    const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                    return try self.math.integrate(expr_str, var_str);
                }
            }
        }

        // ─── Fallback : application de fonction utilisateur ───
        // "double 21" ou "add (succ zero) (succ zero)"
        // parseExpression internerait "double 21" comme un seul sym,
        // donc on split ici AVANT le chemin S-expr.
        {
            var head_tokens = std.mem.tokenizeScalar(u8, trimmed, ' ');
            if (head_tokens.next()) |head| {
                const rest = head_tokens.rest();
                if (rest.len > 0 and self.engine.fns.get(head) != null) {
                    var args: std.ArrayListUnmanaged(Id) = .{};
                    defer args.deinit(self.allocator);

                    // Splitter au niveau 0 pour respecter les parenthèses
                    var depth: usize = 0;
                    var start: usize = 0;
                    var i: usize = 0;
                    while (i < rest.len) : (i += 1) {
                        switch (rest[i]) {
                            '(' => depth += 1,
                            ')' => if (depth > 0) {
                                depth -= 1;
                            },
                            ' ' => if (depth == 0) {
                                if (i > start) {
                                    const tok = rest[start..i];
                                    const id = self.parseExpression(tok) catch |err| switch (err) {
                                        error.OutOfMemory => return error.OutOfMemory,
                                        else => return try std.fmt.allocPrint(self.allocator, "parse error for arg: {s}", .{tok}),
                                    };
                                    try args.append(self.allocator, id);
                                }
                                start = i + 1;
                            },
                            else => {},
                        }
                    }
                    if (start < rest.len) {
                        const tok = rest[start..];
                        const id = self.parseExpression(tok) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            else => return try std.fmt.allocPrint(self.allocator, "parse error for arg: {s}", .{tok}),
                        };
                        try args.append(self.allocator, id);
                    }

                    self.engine.fuel = 1_000_000;
                    const result = self.engine.evalFunction(self.env, head, args.items) catch |err| {
                        return try std.fmt.allocPrint(self.allocator, "eval error: {}", .{err});
                    };
                    return expr.toStringInfix(self.store, result, self.allocator);
                }
            }
        }

        if (self.parseExpression(trimmed)) |expr_id| {
            const lowered = try self.store.lowerRec(expr_id);
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, lowered, 0) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "eval error: {}", .{err});
            };
            return expr.toStringInfix(self.store, result, self.allocator);
        } else |_| {}

        self.engine.fuel = 1_000_000;
        const id0 = if (self.bridge.importExpr(input)) |id| id else |_| blk: {
            break :blk self.bridge.importExpr(input) catch {
                return try self.allocator.dupe(u8, "syntax error");
            };
        };
        const result = try engine_expr.evaluate(self.store, self.env, self.engine, id0, 0);
        const canon = if (platform.target.is_wasm)
            try canon_mod.canonicalize(self.store, self.allocator, result)
        else
            result;
        return expr.toStringInfix(self.store, canon, self.allocator);
    }

    fn evalRules(self: *Commands) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);

        _ = try buf.writer(self.allocator).print("=== Knowledge Base Rules ({d}) ===\n", .{self.kb.rules.items.len});

        for (self.kb.rules.items, 0..) |rule_id, i| {
            const rule = self.store.get(rule_id);
            // Utiliser spanSliceConst pour accéder aux éléments
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

    // ─── evalSimplify : pipeline simplifyBasic → E-Graph → simplifyBasic ───
    pub fn evalSimplify(self: *Commands, input: []const u8) HeavenError![]u8 {
        return cas_ops.evalSimplify(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    fn evalHelp(self: *Commands) ![]u8 {
        return try self.allocator.dupe(u8, "═══ Heaven ═══\n" ++
            "  help, stats, theorems\n" ++
            "  theorem <name> : <prop>\n" ++
            "  prove by <method>\n" ++
            "  skill <name>\n" ++
            "  type <expr>\n" ++
            "  simplify <expr>\n" ++
            "  derive <expr>\n" ++
            "  solve <equation>\n" ++
            "  expand <expr>\n" ++
            "  integrate <expr>\n" ++
            "  plot <function>\n" ++
            "  latex <expr>\n" ++
            "  explain <expr>\n" ++
            "  trace <expr>\n" ++
            "  let <var> = <expr>\n");
    }

    fn evalStats(self: *Commands) ![]u8 {
        return try self.allocator.dupe(u8, "═══ Heaven WASM ═══\n" ++
            "Engine: active\n" ++
            "Features: eval, type, simplify, explain, latex, quote, prove");
    }

    fn evalType(self: *Commands, input: []const u8) ![]u8 {
        return self.typeOf(input);
    }

    fn evalExpand(self: *Commands, input: []const u8) ![]u8 {
        return self.math.expand(input);
    }

    pub fn evalLatex(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        const latex = try self.toLaTeXInline(id);
        defer self.allocator.free(latex); // ← ajouter
        return std.fmt.allocPrint(self.allocator, "latex|{s}", .{latex});
    }

    fn evalExplain(self: *Commands, input: []const u8) ![]u8 {
        return self.explain(input);
    }

    fn evalPlot(self: *Commands, input: []const u8) ![]u8 {
        const expr_str = std.mem.trim(u8, input, " ");
        return std.fmt.allocPrint(self.allocator, "plot|{s}", .{expr_str});
    }

    fn evalQtt(self: *Commands, input: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        defer result.deinit(self.allocator);
        var tokens = std.mem.tokenizeScalar(u8, input, ',');
        while (tokens.next()) |token| {
            const trimmed = std.mem.trim(u8, token, " ");
            if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                const name = std.mem.trim(u8, trimmed[0..colon], " ");
                const qty_str = std.mem.trim(u8, trimmed[colon + 1 ..], " ");
                const qty = if (std.mem.eql(u8, qty_str, "0") or std.mem.eql(u8, qty_str, "zero")) @as(u2, 0) else if (std.mem.eql(u8, qty_str, "1") or std.mem.eql(u8, qty_str, "one")) @as(u2, 1) else @as(u2, 2);
                _ = try self.store.interner.intern(name);
                try self.qtt_env.put(self.allocator, name, qty);
                try result.writer(self.allocator).print("qtt: {s} -> {d}\n", .{ name, qty });
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    pub fn evalTrace(self: *Commands, input: []const u8) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        const initial = try expr.toStringInfix(self.store, id, self.allocator);
        defer self.allocator.free(initial);
        try w.print("trace: {s}\n", .{initial});
        var current = try self.simplify_eng.simplifyRec(id, 0);
        const after_rec = try expr.toStringInfix(self.store, current, self.allocator);
        defer self.allocator.free(after_rec);
        if (!std.mem.eql(u8, initial, after_rec))
            try w.print("  → [rewrite] {s}\n", .{after_rec});
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        const after_egraph = try self.simplify_eng.simplifyWithEGraph(current, &qtt, null);
        const after_egraph_str = try expr.toStringInfix(self.store, after_egraph, self.allocator);
        defer self.allocator.free(after_egraph_str);
        if (!std.mem.eql(u8, after_rec, after_egraph_str))
            try w.print("  → [egraph] {s}\n", .{after_egraph_str});
        current = after_egraph;
        const canon = try canon_mod.canonicalize(self.store, self.allocator, current);
        const canon_str = try expr.toStringInfix(self.store, canon, self.allocator);
        defer self.allocator.free(canon_str);
        if (!std.mem.eql(u8, after_egraph_str, canon_str))
            try w.print("  → [canon] {s}\n", .{canon_str});
        const node_count = self.countNodes(canon);
        try w.print("  cost: {d} nodes\n", .{node_count});
        return buf.toOwnedSlice(self.allocator);
    }

    fn countNodes(self: *Commands, id: Id) usize {
        if (id >= self.store.len()) return 0;
        const node = self.store.get(id);
        var count: usize = 1;
        switch (node.tag) {
            .apply => {
                count += self.countNodes(node.payload);
                for (node.span_a.slice(self.store.pool.items)) |child|
                    count += self.countNodes(child);
            },
            .bind => {
                const children = node.span_a.slice(self.store.pool.items);
                if (children.len != 2) return 0;
                count += self.countNodes(children[0]);
                count += self.countNodes(children[1]);
            },
            else => {},
        }
        return count;
    }

    pub fn define(self: *Commands, name: []const u8, value_text: []const u8) HeavenError![]u8 {
        return defs_ops.define(self, name, value_text) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    fn tryFnCall(self: *Commands, input: []const u8) ?[]u8 {
        return parse_ops.tryFnCall(self, input);
    }


    pub fn evalActorDef(self: *Commands, input: []const u8, env: *engine_expr.Env) HeavenError![]u8 {
        return defs_ops.evalActorDef(self, input, env) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn evalMacroDef(self: *Commands, input: []const u8) HeavenError![]u8 {
        return defs_ops.evalMacroDef(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn parseLambdaShortcut(self: *Commands, name: []const u8, expr_str: []const u8) HeavenError![]u8 {
        return defs_ops.parseLambdaShortcut(self, name, expr_str) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn evalFnDef(self: *Commands, input: []const u8) HeavenError![]u8 {
        return defs_ops.evalFnDef(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    fn parseApp(self: *Commands, input: []const u8) !Id {
        return parse_ops.parseApp(self, input);
    }


    fn parseApplication(self: *Commands, input: []const u8) !Id {
        return parse_ops.parseApplication(self, input);
    }


    fn isIdent(s: []const u8) bool {
        return parse_ops.isIdent(s);
    }


    fn isOperatorTok(s: []const u8) bool {
        return parse_ops.isOperatorTok(s);
    }


    pub fn parseExpression(self: *Commands, input: []const u8) anyerror!Id {
        return parse_ops.parseExpression(self, input);
    }


    fn hasErrorNode(self: *Commands, node: *const bridge_expr.Matrix) bool {
        return parse_ops.hasErrorNode(self, node);
    }


    fn parseCallExpr(self: *Commands, input: []const u8) !Id {
        return parse_ops.parseCallExpr(self, input);
    }


    fn parseLambda(self: *Commands, input: []const u8) !Id {
        return parse_ops.parseLambda(self, input);
    }


    pub fn typeOf(self: *Commands, input: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " \t");
        const id = blk: {
            if (std.mem.indexOf(u8, trimmed, "(λ") != null or std.mem.indexOf(u8, trimmed, "(\\") != null) {
                break :blk try self.parseApp(trimmed);
            } else if (trimmed.len > 0 and trimmed[0] == '(') {
                break :blk try self.parser.parseSExpr(trimmed);
            } else {
                // Fallback robuste
                break :blk self.parseExpression(trimmed) catch try self.bridge.importExpr(trimmed);
            }
        };
        var inf = types_mod.Infer.init(self.store, self.allocator);
        defer inf.deinit();
        const t = try inf.typeOf(id);
        return inf.typeStr(&inf.subst, t, self.allocator);
    }

    pub fn simplify(self: *Commands, input: []const u8) ![]u8 {
        return cas_ops.simplify(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn simplifyWithEGraph(self: *Commands, id: Id, qtt: ?*egraph_mod.QttCost) !Id {
        return cas_ops.simplifyWithEGraph(self, id, qtt) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn simplifyRec(self: *Commands, id: Id, depth: u32) !Id {
        return cas_ops.simplifyRec(self, id, depth) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn isFullyNumeric(self: *Commands, id: Id) bool {
        return cas_ops.isFullyNumeric(self, id);
    }


    pub fn toC(self: *Commands, ids: []const Id) ![]u8 {
        var cg = codegen_c.Codegen.init(self.store, self.allocator);
        defer cg.deinit();
        return cg.generate(ids);
    }

    pub fn toLaTeX(self: *Commands, ids: []const Id) ![]u8 {
        var gen = codegen_latex.LaTeX.init(self.store, self.allocator);
        defer gen.deinit();
        return gen.generate(ids);
    }

    pub fn toLaTeXInline(self: *Commands, id: Id) ![]u8 {
        var gen = codegen_latex.LaTeX.init(self.store, self.allocator);
        defer gen.deinit();
        return gen.renderInline(id);
    }

    pub fn format(self: *Commands, id: Id) ![]u8 {
        return expr.toString(self.store, id, self.allocator);
    }

    fn evalGreen(self: *Commands, input: []const u8) ![]u8 {
        // Même mécanisme que cmdGreen : wrapper dans (handle expr greenHandler)
        if (self.eval("let greenHandler(v1, v2, cost) = (+ v1 v2)")) |r| {
            self.allocator.free(r);
        } else |_| {}

        const expr_id = try self.bridge.importExpr(input);
        const handle_op = try self.store.sym("handle");
        const handler_sym = try self.store.sym("greenHandler");
        const handle_node = try self.store.apply(handle_op, &.{ expr_id, handler_sym });

        self.engine.green_call_count = 0;
        self.engine.green_mode = true;
        defer self.engine.green_mode = false;
        self.engine.fuel = 1_000_000;

        const result = engine_expr.evaluate(self.store, self.env, self.engine, handle_node, 0) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "green eval error: {}", .{err});
        };
        const res_str = try expr.toStringInfix(self.store, result, self.allocator);
        defer self.allocator.free(res_str);
        return try std.fmt.allocPrint(self.allocator, "{s} (green calls: {d})", .{ res_str, self.engine.green_call_count });
    }

    fn evalOptimize(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        const optimized = try self.simplify_eng.simplifyWithEGraph(id, &qtt, null);
        return expr.toString(self.store, optimized, self.allocator);
    }

    fn evalAsm(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        var mir_func = mir.MirFunction.init(self.allocator);
        defer mir_func.deinit();
        const entry_block = try mir_func.newBlock();
        var locals = std.AutoHashMap(u32, mir.Id).init(self.allocator);
        defer locals.deinit();
        _ = try mir_func.compileExpr(self.store, id, entry_block, locals);
        mir_func.blocks.items[entry_block].terminator = .{ .ret = 0 };
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        try x86_64.emitFromFunction(&mir_func, buf.writer(self.allocator));
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn evalSExpr(self: *Commands, input: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "()");

        const expr_id = self.parseExpression(trimmed) catch return error.InvalidSyntax;
        self.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(self.store, self.env, self.engine, expr_id, 0) catch expr_id;
        return expr.toStringInfix(self.store, result, self.allocator);
    }

    pub fn substExpr(self: *Commands, input: []const u8, varname: []const u8, value: []const u8) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        const w = result.writer(self.allocator);
        var i: usize = 0;
        while (i < input.len) {
            if (i + varname.len <= input.len and std.mem.eql(u8, input[i .. i + varname.len], varname)) {
                const before_ok = i == 0 or !std.ascii.isAlphabetic(input[i - 1]);
                const after_ok = i + varname.len >= input.len or !std.ascii.isAlphabetic(input[i + varname.len]);
                if (before_ok and after_ok) {
                    try w.writeAll(value);
                    i += varname.len;
                    continue;
                }
            }
            try w.writeByte(input[i]);
            i += 1;
        }
        return result.toOwnedSlice(self.allocator);
    }

    pub fn listRules(self: *Commands) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(self.allocator);
        try w.writeAll("  KB rules as data:\n");
        for (self.kb.rules.items, 0..) |rule_id, idx| {
            if (rule_id >= self.store.len()) continue;
            const s = expr.toString(self.store, rule_id, self.allocator) catch continue;
            defer self.allocator.free(s);
            try std.fmt.format(w, "  [{d}] {s}\n", .{ idx, s });
        }
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn dumpAst(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        try self.writeAst(id, 0, &buf);
        return buf.toOwnedSlice(self.allocator);
    }

    fn writeAst(self: *Commands, id: Id, depth: u32, buf: *std.ArrayListUnmanaged(u8)) !void {
        if (id >= self.store.len()) return;
        const node = self.store.get(id);
        var i: u32 = 0;
        while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
        switch (node.tag) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                try buf.appendSlice(self.allocator, "(sym \"");
                try buf.appendSlice(self.allocator, name);
                try buf.appendSlice(self.allocator, "\")\n");
            },
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |v| {
                        var tmp: [32]u8 = undefined;
                        const s = std.fmt.bufPrint(&tmp, "(lit {d})\n", .{v}) catch return;
                        try buf.appendSlice(self.allocator, s);
                    },
                    else => try buf.appendSlice(self.allocator, "(lit ?)\n"),
                }
            },
            .apply => {
                try buf.appendSlice(self.allocator, "(apply\n");
                try self.writeAst(node.payload, depth + 1, buf);
                for (node.span_a.slice(self.store.pool.items)) |child| try self.writeAst(child, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            .bind => {
                try buf.appendSlice(self.allocator, "(bind ");
                try buf.appendSlice(self.allocator, self.store.interner.resolve(node.payload));
                try buf.appendSlice(self.allocator, "\n");
                for (node.span_a.slice(self.store.pool.items)) |child| try self.writeAst(child, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            .lambda => {
                try buf.appendSlice(self.allocator, "(lambda ");
                try buf.appendSlice(self.allocator, self.store.interner.resolve(node.payload));
                try buf.appendSlice(self.allocator, "\n");
                for (node.span_a.slice(self.store.pool.items)) |child| try self.writeAst(child, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            .relation => {
                try buf.appendSlice(self.allocator, "(relation ");
                try buf.appendSlice(self.allocator, self.store.interner.resolve(node.payload));
                try buf.appendSlice(self.allocator, "\n");
                for (node.span_a.slice(self.store.pool.items)) |child| try self.writeAst(child, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            .source_file, .block, .block_legacy => {
                try buf.appendSlice(self.allocator, "(");
                try buf.appendSlice(self.allocator, @tagName(node.tag));
                try buf.appendSlice(self.allocator, "\n");
                for (node.span_a.slice(self.store.pool.items)) |child| try self.writeAst(child, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, " ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            else => {
                try buf.appendSlice(self.allocator, "(");
                try buf.appendSlice(self.allocator, @tagName(node.tag));
                try buf.appendSlice(self.allocator, ")\n");
            },
        }
    }

    pub fn explain(self: *Commands, input: []const u8) ![]u8 {
        var current = try self.bridge.importExpr(input);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const s0 = try expr.toString(self.store, current, self.allocator);
        defer self.allocator.free(s0);
        try buf.appendSlice(self.allocator, "  step 0: ");
        try buf.appendSlice(self.allocator, s0);
        try buf.append(self.allocator, '\n');
        var step: u32 = 1;
        while (step < 20) {
            const prev = current;
            current = try self.simplify_eng.simplifyOnePass(current, &buf, &step);
            if (current == prev) break;
        }
        const final_str = try expr.toString(self.store, current, self.allocator);
        defer self.allocator.free(final_str);
        try buf.appendSlice(self.allocator, "  ∴ ");
        try buf.appendSlice(self.allocator, s0);
        try buf.appendSlice(self.allocator, " = ");
        try buf.appendSlice(self.allocator, final_str);
        var tmp: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&tmp, "  ({d} rewrites)\n", .{step - 1}) catch "?\n";
        try buf.appendSlice(self.allocator, count_str);
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn simplifyOnePass(self: *Commands, id: Id, buf: *std.ArrayListUnmanaged(u8), step: *u32) !Id {
        return cas_ops.simplifyOnePass(self, id, buf, step) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn describeKB(self: *Commands) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        var tmp: [64]u8 = undefined;
        const n_str = std.fmt.bufPrint(&tmp, " {d} rewrite rules\n", .{self.kb.rules.items.len}) catch "?\n";
        try buf.appendSlice(self.allocator, n_str);
        for (self.kb.rules.items) |rule_id| {
            if (rule_id >= self.store.len()) continue;
            const s = try expr.toString(self.store, rule_id, self.allocator);
            defer self.allocator.free(s);
            try buf.appendSlice(self.allocator, " ");
            try buf.appendSlice(self.allocator, s);
            try buf.append(self.allocator, '\n');
        }
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn exprToC(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        var cg = codegen_c.Codegen.init(self.store, self.allocator);
        defer cg.deinit();
        return cg.generateExpr(id);
    }

    // ─── Preuve ───
    fn evalTheorems(self: *Commands) ![]u8 {
        return self.proof_core.formatAll(self.allocator);
    }

    pub fn evalTheorem(self: *Commands, input: []const u8) ![]u8 {
        return proofs_ops.evalTheorem(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn evalProve(self: *Commands, input: []const u8) ![]u8 {
        return proofs_ops.evalProve(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }




    pub fn evalSkill(self: *Commands, input: []const u8) ![]u8 {
        return proofs_ops.evalSkill(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    pub fn evalLet(self: *Commands, input: []const u8) HeavenError![]u8 {
        return defs_ops.evalLet(self, input) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.EvaluationFailed,
        };
    }


    fn evalMir(self: *Commands, input: []const u8) ![]u8 {
        var instructions = std.mem.splitScalar(u8, input, ';');
        var last_expr: []const u8 = "";
        while (instructions.next()) |instr| {
            const trimmed = std.mem.trim(u8, instr, " \t");
            if (trimmed.len == 0) continue;
            last_expr = trimmed;
        }
        const id = self.bridge.importExpr(last_expr) catch |err| {
            return std.fmt.allocPrint(self.allocator, "parse error: {s}", .{@errorName(err)});
        };
        var mir_func = mir.MirFunction.init(self.allocator);
        defer mir_func.deinit();
        mir_func.engine = self.engine;
        mir_func.store_ref = self.store;
        const entry_block = try mir_func.newBlock();
        var locals = std.AutoHashMap(u32, mir.Id).init(self.allocator);
        defer locals.deinit();
        const result_val = try mir_func.compileExpr(self.store, id, entry_block, locals);
        if (mir_func.blocks.items[entry_block].terminator == .fallthrough) {
            mir_func.blocks.items[entry_block].terminator = .{ .ret = result_val };
        }
        var global_vars = std.AutoHashMap(u32, i64).init(self.allocator);
        defer global_vars.deinit();
        const result = mir_func.execute(&global_vars) catch |err| {
            return std.fmt.allocPrint(self.allocator, "mir exec error: {s}", .{@errorName(err)});
        };
        return std.fmt.allocPrint(self.allocator, "{d}", .{result});
    }

    fn evalAsk(self: *Commands, input: []const u8) ![]u8 {
        const prompt = std.mem.trim(u8, input, " ");
        if (prompt.len == 0) return try self.allocator.dupe(u8, "Usage: ask <question>");
        const suggestion = try self.agent.suggest(prompt) orelse
            return try self.allocator.dupe(u8, "Je ne sais pas répondre à cette question.");
        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "[INFO] Suggestion : {s}\n", .{suggestion});
        const result = try self.eval(suggestion);
        defer self.allocator.free(result);
        return std.fmt.allocPrint(self.allocator, "{s}→ {s}", .{ msg, result });
    }

    fn evalJs(self: *Commands, input: []const u8) ![]u8 {
        const id = self.bridge.importExpr(input) catch |err| {
            return std.fmt.allocPrint(self.allocator, "js parse error: {s}", .{@errorName(err)});
        };
        return codegen_js.exprToJs(self.store, id, self.allocator);
    }

    fn evalTransform(self: *Commands, input: []const u8) ![]u8 {
        const eq_pos = std.mem.indexOf(u8, input, "=") orelse return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs_str = std.mem.trim(u8, input[eq_pos + 1 ..], " ");
        const lhs_id = self.bridge.importExpr(lhs_str) catch return error.InvalidSyntax;
        const rhs_id = self.bridge.importExpr(rhs_str) catch return error.InvalidSyntax;
        var tf = transform_mod.Transform.init(self.allocator, self.store, self.kb);
        const result = tf.transform(lhs_id, rhs_id, self.engine);
        return transform_mod.format(result, self.store, self.allocator);
    }

    fn mkBinop(self: *Commands, op: []const u8, a: Id, b: Id) !Id {
        if (a >= self.store.len() or b >= self.store.len()) return self.store.int(0);
        const na = self.store.get(a);
        const nb = self.store.get(b);
        const is_a_zero = na.tag == .lit and self.store.lits.items[na.aux].eql(.{ .int = 0 });
        const is_b_zero = nb.tag == .lit and self.store.lits.items[nb.aux].eql(.{ .int = 0 });
        const is_a_one = na.tag == .lit and self.store.lits.items[na.aux].eql(.{ .int = 1 });
        const is_b_one = nb.tag == .lit and self.store.lits.items[nb.aux].eql(.{ .int = 1 });
        if (std.mem.eql(u8, op, "+")) {
            if (is_a_zero) return b;
            if (is_b_zero) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.add(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "-")) {
            if (is_b_zero) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.sub(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "*")) {
            if (is_a_zero or is_b_zero) return self.store.int(0);
            if (is_a_one) return b;
            if (is_b_one) return a;
            if (na.tag == .lit and nb.tag == .lit) {
                const la = self.store.lits.items[na.aux];
                const lb = self.store.lits.items[nb.aux];
                switch (la) {
                    .int => |va| switch (lb) {
                        .int => |vb| return self.store.int(std.math.mul(i64, va, vb) catch return error.Overflow),
                        else => {},
                    },
                    else => {},
                }
            }
        } else if (std.mem.eql(u8, op, "/")) {
            if (is_a_zero) return self.store.int(0);
            if (is_b_one) return a;
        } else if (std.mem.eql(u8, op, "^")) {
            if (is_b_zero) return self.store.int(1);
            if (is_b_one) return a;
        }
        return self.store.binop(op, a, b);
    }
};
