//! Commandes shell et évaluation pour Heaven
//! Extrait de heaven_expr.zig pour modularité

const std = @import("std");
const expr = @import("expr");
const ShellParser = @import("shell_parser").ShellParser;

const Allocator = std.mem.Allocator;
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
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

const debug = std.posix.getenv("HEAVEN_DEBUG") != null;
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

    // ─── Eval dispatcher ───
    pub fn eval(self: *Commands, input: []const u8) HeavenError![]u8 {
        const trimmed0 = std.mem.trim(u8, input, " \t\r\n");
        const actual = if (trimmed0.len > 0 and trimmed0[0] == ':') trimmed0[1..] else trimmed0;
        const trimmed = std.mem.trim(u8, actual, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "(test ") or
            std.mem.startsWith(u8, trimmed, "(assert_eq ") or
            std.mem.startsWith(u8, trimmed, "(assert_err "))
        {
            const id = try self.parser.parseSExpr(trimmed);
            return try self.evalTestExpr(id);
        }

        if (std.mem.startsWith(u8, trimmed, "module ") or
            std.mem.startsWith(u8, trimmed, "data ") or
            std.mem.startsWith(u8, trimmed, "zero :") or
            std.mem.startsWith(u8, trimmed, "succ :"))
        {
            return try self.allocator.dupe(u8, "()");
        }

        if (std.mem.startsWith(u8, trimmed, "let actor ")) {
            return self.evalActorDef(trimmed["let actor ".len..], self.env);
        }
        if (std.mem.startsWith(u8, trimmed, "let macro ")) {
            return self.evalMacroDef(trimmed["let macro ".len..]);
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

        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "eval error: {}", .{err});
            };
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        if (std.mem.indexOf(u8, trimmed, ":=") != null) {
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
        const canon = if (@import("builtin").target.cpu.arch.isWasm())
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
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "usage: simplify <expr>");

        const raw_id = self.parseExpression(trimmed) catch try self.bridge.importExpr(trimmed);
        const id = try self.store.lowerRec(raw_id);

        // Pipeline : simplifyBasic (rapide/fiable) → E-Graph (cas complexes) → simplifyBasic (nettoyage)
        const after_basic = try self.math.simplifyBasic(id);
        if (after_basic == id) {
            // Rien à simplifier en direct → cas complexe, tenter l'E-Graph
            const after_egraph = try self.simplify_eng.simplifyWithEGraph(after_basic, null, null);
            return expr.toStringInfix(self.store, try self.math.simplifyBasic(after_egraph), self.allocator);
        }
        return expr.toStringInfix(self.store, after_basic, self.allocator);
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

    fn evalLatex(self: *Commands, input: []const u8) ![]u8 {
        const raw_id = self.parseExpression(input) catch try self.bridge.importExpr(input);
        const id = try self.store.lowerRec(raw_id);
        const latex = try self.toLaTeXInline(id);
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
                for (node.span_a.slice(self.store.pool.items)) |child| count += self.countNodes(child);
            },
            .bind => count += self.countNodes(node.aux),
            else => {},
        }
        return count;
    }

    pub fn define(self: *Commands, name: []const u8, value_text: []const u8) ![]u8 {
        const val_id = try self.bridge.importExpr(value_text);
        self.engine.fuel = 10_000;
        const evaled = engine_expr.evaluate(self.store, self.env, self.engine, val_id, 0) catch val_id;
        const bind_id = try self.store.bind(name, evaled);
        try self.env.put(try self.store.interner.intern(name), evaled);
        return expr.toString(self.store, bind_id, self.allocator);
    }

    fn tryFnCall(self: *Commands, input: []const u8) ?[]u8 {
        if (input.len == 0 or input[0] == '(' or std.ascii.isDigit(input[0])) return null;
        if (std.mem.indexOfScalar(u8, input, '(')) |paren_idx| {
            const before_paren = input[0..paren_idx];
            if (std.mem.indexOfScalar(u8, before_paren, ' ') == null) {
                const potential_name = std.mem.trim(u8, input[0..paren_idx], " ");
                if (potential_name.len == 0) return null;
                for (potential_name) |c| {
                    if (!std.ascii.isAlphanumeric(c) and c != '_') return null;
                }
                if (self.engine.fns.getEntry(potential_name) == null) return null;
                const end_paren = std.mem.lastIndexOfScalar(u8, input, ')') orelse return null;
                if (end_paren <= paren_idx) return null;
                const inner_args = std.mem.trim(u8, input[paren_idx + 1 .. end_paren], " ");
                if (inner_args.len == 0) return null;
                var args_list: [16][]const u8 = undefined;
                var num_args: usize = 0;
                var depth: i32 = 0;
                var start: usize = 0;
                for (inner_args, 0..) |ch, i| {
                    switch (ch) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        ',' => {
                            if (depth == 0) {
                                if (num_args < 16) {
                                    args_list[num_args] = std.mem.trim(u8, inner_args[start..i], " ");
                                    num_args += 1;
                                }
                                start = i + 1;
                            }
                        },
                        else => {},
                    }
                }
                if (start < inner_args.len and num_args < 16) {
                    args_list[num_args] = std.mem.trim(u8, inner_args[start..], " ");
                    num_args += 1;
                }
                if (num_args == 0) return null;
                var eval_args: [16]Id = undefined;
                for (0..num_args) |i| {
                    const expr_id = self.parseExpression(args_list[i]) catch return null;
                    eval_args[i] = expr_id;
                }
                self.engine.fuel = 1000_000;
                const sym_id = self.store.sym(potential_name) catch return null;
                const call_id = self.store.apply(sym_id, eval_args[0..num_args]) catch return null;
                const result = engine_expr.evaluate(self.store, self.env, self.engine, call_id, 0) catch return null;
                return expr.toString(self.store, result, self.allocator) catch return null;
            }
        }
        const space_idx = std.mem.indexOfScalar(u8, input, ' ') orelse return null;
        const name = input[0..space_idx];
        if (self.engine.fns.getEntry(name) == null) {
            return null;
        }

        const args_str = std.mem.trim(u8, input[space_idx..], " ");
        if (args_str.len == 0) return null;
        var args_list: [16][]const u8 = undefined;
        var num_args: usize = 0;
        var depth: i32 = 0;
        var start: usize = 0;
        for (args_str, 0..) |ch, i| {
            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                ' ' => {
                    if (depth == 0 and i > start) {
                        if (num_args < 16) {
                            args_list[num_args] = std.mem.trim(u8, args_str[start..i], " ");
                            num_args += 1;
                        }
                        start = i + 1;
                    }
                },
                else => {},
            }
        }
        if (start < args_str.len and num_args < 16) {
            args_list[num_args] = std.mem.trim(u8, args_str[start..], " ");
            num_args += 1;
        }
        if (num_args == 0) return null;
        var eval_args: [16]Id = undefined;
        for (0..num_args) |i| {
            const expr_id = self.parseExpression(args_list[i]) catch return null;
            eval_args[i] = expr_id;
        }
        self.engine.fuel = 1000_000;
        const sym_id = self.store.sym(name) catch return null;
        const call_id = self.store.apply(sym_id, eval_args[0..num_args]) catch return null;
        const result = engine_expr.evaluate(self.store, self.env, self.engine, call_id, 0) catch return null;
        return expr.toString(self.store, result, self.allocator) catch return null;
    }

    fn evalActorDef(self: *Commands, input: []const u8, env: *engine_expr.Env) ![]u8 {
        const with_pos = std.mem.indexOf(u8, input, " with ") orelse
            return self.allocator.dupe(u8, "syntax error: missing 'with'");

        const lhs = std.mem.trim(u8, input[0..with_pos], " ");
        const rhs = std.mem.trim(u8, input[with_pos + 6 ..], " ");

        const eq_pos = std.mem.indexOfScalar(u8, lhs, '=') orelse
            return self.allocator.dupe(u8, "syntax error: missing '='");

        const name = std.mem.trim(u8, lhs[0..eq_pos], " ");
        const init_state_str = std.mem.trim(u8, lhs[eq_pos + 1 ..], " ");

        const init_state_id = try self.bridge.importExpr(init_state_str);
        const lowered_state = try self.store.lowerRec(init_state_id);

        const handler_id = if (std.mem.indexOf(u8, rhs, "=>") != null) blk: {
            break :blk self.parser.parseLambda(rhs) catch {
                return self.allocator.dupe(u8, "syntax error in actor handler");
            };
        } else blk: {
            if (self.engine.fns.get(rhs) == null) {
                return std.fmt.allocPrint(self.allocator, "Error: function '{s}' not found for actor handler", .{rhs});
            }
            break :blk try self.store.sym(rhs);
        };

        const new_actor_id = self.engine.next_actor_id;
        self.engine.next_actor_id += 1;
        try self.engine.actors.put(self.engine.allocator, new_actor_id, .{
            .state = lowered_state,
            .handler = handler_id,
        });
        const actor_id = try self.store.int(@intCast(new_actor_id));

        const actor_sym = try self.store.interner.intern(name);
        try env.put(actor_sym, actor_id);

        return std.fmt.allocPrint(self.allocator, "actor {s} spawned (id: {d})", .{ name, actor_id });
    }

    fn evalMacroDef(self: *Commands, input: []const u8) ![]u8 {
        const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse return self.allocator.dupe(u8, "syntax error: missing '='");
        const lhs = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

        const paren_pos = std.mem.indexOfScalar(u8, lhs, '(') orelse return self.allocator.dupe(u8, "syntax error: missing '('");
        if (lhs[lhs.len - 1] != ')') return self.allocator.dupe(u8, "syntax error: missing ')'");

        const name = std.mem.trim(u8, lhs[0..paren_pos], " ");
        const params_str = std.mem.trim(u8, lhs[paren_pos + 1 .. lhs.len - 1], " ");

        var param_ids: std.ArrayListUnmanaged(Id) = .{};
        defer param_ids.deinit(self.allocator);
        var it = std.mem.tokenizeAny(u8, params_str, " ,");
        while (it.next()) |p| {
            try param_ids.append(self.allocator, try self.store.sym(p));
        }
        const params_span = try self.store.pushSpan(param_ids.items);

        const body_id = try self.parser.parseSExpr(rhs);

        const name_sym = try self.store.interner.intern(name);
        try self.engine.macros.put(self.allocator, name_sym, .{ .params_span = params_span, .body = body_id });

        return std.fmt.allocPrint(self.allocator, "macro {s} defined", .{name});
    }

    fn parseLambdaShortcut(self: *Commands, name: []const u8, expr_str: []const u8) HeavenError![]u8 {
        const open = std.mem.indexOfScalar(u8, expr_str, '(') orelse return self.allocator.dupe(u8, "syntax error: missing '(' in fn");
        const close = std.mem.indexOfScalar(u8, expr_str, ')') orelse return self.allocator.dupe(u8, "syntax error: missing ')' in fn");

        const params_str = expr_str[open + 1 .. close];
        var rest = std.mem.trim(u8, expr_str[close + 1 ..], " \t");
        if (std.mem.startsWith(u8, rest, "=>")) {
            rest = std.mem.trim(u8, rest[2..], " \t");
        }

        const fn_def_str = try std.fmt.allocPrint(self.allocator, "{s} {s} = {s}", .{ name, params_str, rest });
        defer self.allocator.free(fn_def_str);
        return self.evalFnDef(fn_def_str);
    }

    fn evalFnDef(self: *Commands, input: []const u8) ![]u8 {
        const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse return self.allocator.dupe(u8, "syntax error: missing '='");
        if (eq_pos + 1 < input.len and input[eq_pos + 1] == '=') return self.allocator.dupe(u8, "syntax error: use single '='");
        var lhs = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

        if (lhs.len > 0 and lhs[lhs.len - 1] == ':') {
            lhs = std.mem.trim(u8, lhs[0 .. lhs.len - 1], " ");
        }

        if (std.mem.startsWith(u8, lhs, "fn ")) lhs = std.mem.trim(u8, lhs[3..], " ");
        if (std.mem.startsWith(u8, lhs, "let ")) lhs = std.mem.trim(u8, lhs[4..], " ");

        if (std.mem.startsWith(u8, rhs, "fn ") or std.mem.startsWith(u8, rhs, "fn(")) {
            const name = if (std.mem.indexOfScalar(u8, lhs, ' ')) |space| lhs[0..space] else lhs;
            return self.parseLambdaShortcut(name, rhs);
        }

        var owned_lhs: ?[]u8 = null;
        defer if (owned_lhs) |s| self.allocator.free(s);
        if (std.mem.indexOfScalar(u8, lhs, '(') != null) {
            const open = std.mem.indexOfScalar(u8, lhs, '(') orelse return self.allocator.dupe(u8, "syntax error");
            const close = std.mem.indexOfScalar(u8, lhs, ')') orelse return self.allocator.dupe(u8, "syntax error");
            if (close != lhs.len - 1) return self.allocator.dupe(u8, "syntax error: unexpected chars after )");
            const name = std.mem.trim(u8, lhs[0..open], " ");
            const params_str = lhs[open + 1 .. close];

            var converted = std.ArrayListUnmanaged(u8){};
            try converted.appendSlice(self.allocator, name);
            var it = std.mem.tokenizeAny(u8, params_str, " ,");
            while (it.next()) |p| {
                try converted.append(self.allocator, ' ');
                try converted.appendSlice(self.allocator, p);
            }
            owned_lhs = try converted.toOwnedSlice(self.allocator);
            lhs = owned_lhs.?;
        }

        const wrapped_lhs = try std.fmt.allocPrint(self.allocator, "({s})", .{lhs});
        defer self.allocator.free(wrapped_lhs);

        const lhs_id = self.parser.parseSExpr(wrapped_lhs) catch {
            return self.allocator.dupe(u8, "syntax error in lhs");
        };

        const lhs_node = self.store.get(lhs_id);

        if (lhs_node.tag == .sym) {
            const name = self.store.interner.resolve(lhs_node.payload);
            const body_id = self.parseExpression(rhs) catch return self.allocator.dupe(u8, "parse error in body");

            var def: engine_expr.FunctionDef = undefined;
            def.num_clauses = 1;
            def.clauses[0] = .{ .patterns = .{0} ** 8, .num_patterns = 0, .body = body_id };

            const owned_name = try self.allocator.dupe(u8, name);
            self.engine.fns.put(self.allocator, owned_name, def) catch |err| {
                return std.fmt.allocPrint(self.allocator, "registration error: {s}", .{@errorName(err)});
            };

            const name_sym = try self.store.interner.intern(name);
            const name_sym_id = try self.store.sym(name);
            try self.env.put(name_sym, name_sym_id);

            return std.fmt.allocPrint(self.allocator, "{s} defined", .{name});
        }

        if (lhs_node.tag == .apply) {
            const func_sym_node = self.store.get(lhs_node.payload);
            if (func_sym_node.tag != .sym) return self.allocator.dupe(u8, "syntax error: function name must be a symbol");
            const name = self.store.interner.resolve(func_sym_node.payload);

            const pool = self.store.pool.items;
            const arg_span = lhs_node.span_a.slice(pool);
            const num_args = arg_span.len;

            var patterns_start: usize = 0;
            if (num_args > 0) {
                const first = arg_span[0];
                if (first < self.store.len()) {
                    const first_node = self.store.get(first);
                    if (first_node.tag == .sym) {
                        const first_name = self.store.interner.resolve(first_node.payload);
                        if (std.mem.eql(u8, first_name, name)) {
                            patterns_start = 1;
                        }
                    }
                }
            }

            const num_pats = num_args - patterns_start;
            if (num_pats > 8) return self.allocator.dupe(u8, "too many patterns");

            var pat_ids: [8]u32 = undefined;
            for (0..num_pats) |i| {
                pat_ids[i] = arg_span[patterns_start + i];
            }

            const body_id = self.parseExpression(rhs) catch return self.allocator.dupe(u8, "parse error in body");
            const lowered_body = try self.store.lowerRec(body_id);

            var def: engine_expr.FunctionDef = undefined;
            def.num_clauses = 1;
            def.clauses[0] = .{
                .patterns = .{0} ** 8,
                .num_patterns = @intCast(num_pats),
                .body = lowered_body,
            };
            if (num_pats > 0) {
                @memcpy(def.clauses[0].patterns[0..num_pats], pat_ids[0..num_pats]);
            }

            const owned_name = try self.allocator.dupe(u8, name);
            try self.engine.fns.put(self.engine.allocator, owned_name, def);

            const name_sym = try self.store.interner.intern(name);
            const name_sym_id = try self.store.sym(name);
            try self.env.put(name_sym, name_sym_id);

            return std.fmt.allocPrint(self.allocator, "{s} clause ({d} patterns) registered", .{ name, num_pats });
        }

        return self.allocator.dupe(u8, "syntax error in function definition");
    }

    fn parseApp(self: *Commands, input: []const u8) !Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidLambda;

        var s = trimmed;
        while (s.len >= 2 and s[0] == '(' and s[s.len - 1] == ')') {
            const inner = s[1 .. s.len - 1];
            const inner_trim = std.mem.trim(u8, inner, " \t");
            if (inner_trim.len == 0) break;
            s = inner_trim;
        }

        if (std.mem.startsWith(u8, s, "λ") or std.mem.startsWith(u8, s, "\\")) {
            const wrapped = try std.fmt.allocPrint(self.allocator, "({s})", .{s});
            defer self.allocator.free(wrapped);
            return try self.parseLambda(wrapped);
        }

        var start: ?usize = null;
        if (std.mem.indexOf(u8, trimmed, "(λ")) |pos| {
            start = pos;
        } else if (std.mem.indexOf(u8, trimmed, "(\\")) |pos| start = pos;
        if (start == null) return error.InvalidLambda;
        const pos = start.?;

        var depth: usize = 1;
        var i = pos + 2;
        while (i < trimmed.len) : (i += 1) {
            if (trimmed[i] == '(') {
                depth += 1;
            } else if (trimmed[i] == ')') {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        if (depth != 0) return error.InvalidLambda;
        const lambda_end = i + 1;
        const lambda_part = trimmed[pos..lambda_end];
        const rest = trimmed[lambda_end..];

        const lambda_id = try self.parseLambda(lambda_part);
        const rest_trim = std.mem.trim(u8, rest, " \t");
        if (rest_trim.len == 0) return lambda_id;

        var arg_str = rest_trim;
        if (arg_str.len > 0 and arg_str[0] == ')') {
            arg_str = arg_str[1..];
        }
        arg_str = std.mem.trim(u8, arg_str, " \t");
        if (arg_str.len > 0 and arg_str[arg_str.len - 1] == ')') {
            arg_str = arg_str[0 .. arg_str.len - 1];
        }
        arg_str = std.mem.trim(u8, arg_str, " \t");

        const arg_id = try self.bridge.importExpr(arg_str);
        return try self.store.apply(lambda_id, &.{arg_id});
    }

    fn parseApplication(self: *Commands, input: []const u8) anyerror!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidSyntax;

        if (std.mem.indexOfScalar(u8, trimmed, '(')) |open| {
            if (std.mem.lastIndexOfScalar(u8, trimmed, ')')) |close| {
                if (close > open) {
                    const name = std.mem.trim(u8, trimmed[0..open], " \t");
                    if (name.len > 0 and isIdent(name)) {
                        const inner = std.mem.trim(u8, trimmed[open + 1 .. close], " \t");
                        var args: std.ArrayListUnmanaged(Id) = .{};
                        defer args.deinit(self.allocator);
                        if (inner.len > 0) {
                            var it = std.mem.splitScalar(u8, inner, ',');
                            while (it.next()) |part| {
                                const p = std.mem.trim(u8, part, " \t");
                                if (p.len > 0) {
                                    const arg_id = self.parseExpression(p) catch return error.InvalidSyntax;
                                    try args.append(self.allocator, arg_id);
                                }
                            }
                        }
                        const func_id = try self.store.sym(name);
                        return try self.store.apply(func_id, args.items);
                    }
                }
            }
        }

        var tokens: [16][]const u8 = undefined;
        var num_tokens: usize = 0;
        var tok_it = std.mem.tokenizeScalar(u8, trimmed, ' ');
        while (tok_it.next()) |tok| {
            if (num_tokens < 16) {
                tokens[num_tokens] = tok;
                num_tokens += 1;
            }
        }
        if (num_tokens < 2) return error.InvalidSyntax;
        if (!isIdent(tokens[0])) return error.InvalidSyntax;
        for (tokens[0..num_tokens]) |tok| {
            if (isOperatorTok(tok)) return error.InvalidSyntax;
        }

        const func_id = try self.store.sym(tokens[0]);
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        for (tokens[1..num_tokens]) |tok| {
            const arg_id = self.parseExpression(tok) catch return error.InvalidSyntax;
            try args.append(self.allocator, arg_id);
        }
        return try self.store.apply(func_id, args.items);
    }

    fn isIdent(s: []const u8) bool {
        if (s.len == 0) return false;
        const c = s[0];
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isOperatorTok(s: []const u8) bool {
        const ops = [_][]const u8{ "+", "-", "*", "/", "=", "<", ">", "==", "!=", ":=", "->", "&&", "||" };
        for (ops) |op| {
            if (std.mem.eql(u8, s, op)) return true;
        }
        return false;
    }

    fn parseExpression(self: *Commands, input: []const u8) anyerror!Id {
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

        if (self.shell_parser.parse(input)) |matrix| {
            defer self.shell_parser.reset();

            if (!self.hasErrorNode(&matrix)) {
                const actual_node = if (matrix.kind == .program and matrix.children.len > 0)
                    &matrix.children[0]
                else
                    &matrix;

                var bridge = @import("bridge_expr").Bridge.init(self.store, self.allocator);
                if (bridge.translateOne(actual_node)) |id| {
                    return id;
                } else |_| {}
            }
        } else |_| {}

        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            return self.parser.parseSExpr(trimmed);
        }

        if (std.mem.indexOfScalar(u8, trimmed, ' ')) |space1| {
            if (space1 + 1 < trimmed.len) {
                const op_start = space1 + 1;
                if (std.mem.indexOfScalar(u8, trimmed[op_start..], ' ')) |space2_rel| {
                    const space2 = op_start + space2_rel;
                    const lhs_str = trimmed[0..space1];
                    const op_str = trimmed[op_start..space2];
                    const rhs_str = trimmed[space2 + 1 ..];
                    if (isOperatorTok(op_str)) {
                        const lhs_id = try self.parseExpression(lhs_str);
                        const rhs_id = try self.parseExpression(rhs_str);
                        return self.store.binop(op_str, lhs_id, rhs_id);
                    }
                }
            }
        }

        if (self.parseApplication(input)) |id| {
            return id;
        } else |_| {}

        if (std.fmt.parseInt(i64, trimmed, 10)) |val| {
            return self.store.int(val);
        } else |_| {}
        return self.store.sym(trimmed);
    }

    fn hasErrorNode(self: *Commands, node: *const @import("bridge_expr").Matrix) bool {
        if (node.kind == .err_node) {
            return true;
        }
        for (node.children) |*child| {
            if (hasErrorNode(self, child)) return true;
        }
        return false;
    }

    fn parseCallExpr(self: *Commands, input: []const u8) !Id {
        const open = std.mem.indexOfScalar(u8, input, '(') orelse return error.InvalidSyntax;
        const close = std.mem.lastIndexOfScalar(u8, input, ')') orelse return error.InvalidSyntax;
        if (close <= open) return error.InvalidSyntax;

        const name = std.mem.trim(u8, input[0..open], " \t");
        const inner = std.mem.trim(u8, input[open + 1 .. close], " \t");

        const func_id = try self.store.sym(name);

        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);

        if (inner.len > 0) {
            var depth: i32 = 0;
            var start: usize = 0;
            for (inner, 0..) |ch, i| {
                switch (ch) {
                    '(' => depth += 1,
                    ')' => depth -= 1,
                    ',' => {
                        if (depth == 0) {
                            const part = std.mem.trim(u8, inner[start..i], " \t");
                            if (part.len > 0) {
                                const arg_id = try self.bridge.importExpr(part);
                                try args.append(self.allocator, arg_id);
                            }
                            start = i + 1;
                        }
                    },
                    else => {},
                }
            }
            const last = std.mem.trim(u8, inner[start..], " \t");
            if (last.len > 0) {
                const arg_id = try self.bridge.importExpr(last);
                try args.append(self.allocator, arg_id);
            }
        }

        return self.store.apply(func_id, args.items);
    }

    fn parseLambda(self: *Commands, input: []const u8) !Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidLambda;

        var s = trimmed;
        while (s.len >= 2 and s[0] == '(' and s[s.len - 1] == ')') {
            const inner = s[1 .. s.len - 1];
            const inner_trim = std.mem.trim(u8, inner, " \t");
            if (inner_trim.len == 0) break;
            s = inner_trim;
        }
        if (s.len == 0) return error.InvalidLambda;

        if (!std.mem.startsWith(u8, s, "λ") and !std.mem.startsWith(u8, s, "\\")) {
            return error.InvalidLambda;
        }

        var rest = if (std.mem.startsWith(u8, s, "λ")) s["λ".len..] else s["\\".len..];
        rest = std.mem.trimLeft(u8, rest, " \t");
        if (rest.len == 0) return error.InvalidLambda;

        var param_end: usize = 0;
        while (param_end < rest.len) {
            const c = rest[param_end];
            if (c == '.' or c == ' ' or c == '\t') break;
            param_end += 1;
        }
        if (param_end == 0) return error.InvalidLambda;
        const param_name = rest[0..param_end];
        rest = rest[param_end..];
        rest = std.mem.trimLeft(u8, rest, " \t");
        if (rest.len == 0 or rest[0] != '.') return error.InvalidLambda;
        rest = rest[1..];
        rest = std.mem.trimLeft(u8, rest, " \t");
        if (rest.len == 0) return error.InvalidLambda;

        const body_end = if (rest[rest.len - 1] == ')') rest.len - 1 else rest.len;
        const body_str = rest[0..body_end];
        if (body_str.len == 0) return error.InvalidLambda;

        const body_id = try self.bridge.importExpr(body_str);
        return try self.store.lambdaNative(&.{param_name}, body_id);
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
        const id = try self.parser.parseSExpr(input);
        const debug_str = try expr.toStringInfix(self.store, id, self.allocator);
        defer self.allocator.free(debug_str);
        platform.dbg("[core.commands.simplify] input: {s}\n", .{debug_str});

        // ✅ Pipeline : réécriture directe (rules.zig) → E-Graph → nettoyage
        var current = id;

        // 1. Réécriture directe à point fixe via le module rules
        var changed = true;
        var iterations: u32 = 0;
        while (changed and iterations < 50) : (iterations += 1) {
            changed = false;
            if (try rules_mod.applyFirstRule(self.store, self.kb.rules.items, current, self.allocator)) |match| {
                current = match.new_id;
                changed = true;
            }
        }

        // 2. E-Graph pour les cas complexes (distributivité/factorisation croisées)
        const after_egraph = try self.simplify_eng.simplifyWithEGraph(current, null, null);

        // 3. Nettoyage final (identités 0/1, constant folding)
        const simplified = try self.math.simplifyBasic(after_egraph);

        return expr.toStringInfix(self.store, simplified, self.allocator);
    }

    fn simplifyWithEGraph(self: *Commands, id: Id, qtt: ?*egraph_mod.QttCost) !Id {
        if (self.kb.rules.items.len == 0) return id;
        var egraph = egraph_mod.EGraph.init(self.store, self.allocator);
        defer egraph.deinit();
        const root_class = try egraph.addExpr(id);
        var changed = true;
        var iters: u32 = 0;
        while (changed and iters < 8) : (iters += 1) {
            changed = false;
            for (self.kb.rules.items) |rule_id| {
                if (rule_id >= self.store.len()) continue;
                const rule_node = self.store.get(rule_id);
                if (rule_node.tag != .relation) continue;
                const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
                if (lhs_rhs.len != 2) continue;
                const lhs_id = lhs_rhs[0];
                const rhs_id = lhs_rhs[1];
                var i: u32 = 0;
                while (i < egraph.classes.items.len) : (i += 1) {
                    const eclass = &egraph.classes.items[i];
                    for (eclass.nodes.items) |node_id| {
                        var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
                        defer bindings.deinit(self.allocator);
                        if (pattern_mod.exprPatternMatch(self.store, lhs_id, node_id, &bindings, self.allocator)) {
                            const new_id = pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator) catch continue;
                            const new_class = try egraph.addExpr(new_id);
                            const merged = try egraph.merge(i, new_class);
                            if (merged != i) changed = true;
                        }
                    }
                }
            }
        }
        return egraph.extract(root_class, qtt) orelse id;
    }

    pub fn simplifyRec(self: *Commands, id: Id, depth: u32) !Id {
        platform.dbg("[src/core/commands.zig simplifyRec] called with id={d}, depth={d}\n", .{ id, depth });
        if (depth > 50) return id;
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        var current = id;

        if (node.tag == .apply) {
            const func_id = node.payload;
            const args_span = node.span_a;
            const old_args = args_span.slice(self.store.pool.items);
            if (old_args.len == 2) {
                const arg0 = old_args[0];
                const arg1 = old_args[1];

                const new_func = try self.simplifyRec(func_id, depth + 1);
                const new_l = try self.simplifyRec(arg0, depth + 1);
                const new_r = try self.simplifyRec(arg1, depth + 1);

                if (new_func < self.store.len()) {
                    const func_node = self.store.get(new_func);
                    if (func_node.tag == .sym) {
                        const op_name = self.store.interner.resolve(func_node.payload);
                        current = try self.store.binop(op_name, new_l, new_r);
                    }
                }
            }
        }

        var changed = true;
        var iterations: u32 = 0;
        while (changed and iterations < 10) : (iterations += 1) {
            changed = false;
            if (current >= self.store.len()) break;

            const canon_current = try canon_mod.canonicalize(self.store, self.allocator, current);

            for (self.kb.rules.items) |rule_id| {
                if (rule_id >= self.store.len()) continue;
                const rule_node = self.store.get(rule_id);
                if (rule_node.tag != .relation) continue;
                const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
                if (lhs_rhs.len != 2) continue;
                const lhs_id = lhs_rhs[0];
                const rhs_id = lhs_rhs[1];

                var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
                defer bindings.deinit(self.allocator);

                if (pattern_mod.exprPatternMatch(self.store, lhs_id, canon_current, &bindings, self.allocator)) {
                    const new_id = try pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator);
                    if (new_id < self.store.len()) {
                        current = new_id;
                        changed = true;
                        break;
                    }
                }
            }
        }

        if (current < self.store.len()) {
            self.engine.fuel = 100;
            const folded = engine_expr.evaluate(self.store, self.env, self.engine, current, 0) catch current;
            if (folded != current and folded < self.store.len()) {
                const folded_node = self.store.get(folded);
                if (folded_node.tag == .lit and self.simplify_eng.isFullyNumeric(current)) return folded;
            }
        }
        return current;
    }

    fn isFullyNumeric(self: *Commands, id: Id) bool {
        if (id >= self.store.len()) return false;
        const node = self.store.get(id);
        return switch (node.tag) {
            .lit => true,
            .sym => false,
            .apply => {
                const args = node.span_a.slice(self.store.pool.items);
                for (args) |a| {
                    if (!self.simplify_eng.isFullyNumeric(a)) return false;
                }
                return true;
            },
            else => false,
        };
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
        // ✅ Même mécanisme que cmdGreen : wrapper dans (handle expr greenHandler)
        _ = self.eval("let greenHandler(v1, v2, cost) = (+ v1 v2)") catch {};
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

    fn evalTestExpr(self: *Commands, id: Id) ![]u8 {
        const node = self.store.get(id);
        if (node.tag == .apply) {
            const func_id = node.payload;
            const func_node = self.store.get(func_id);
            if (func_node.tag == .sym) {
                const name = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);

                if (std.mem.eql(u8, name, "test") and args.len >= 2) {
                    const body_id = args[args.len - 1];
                    self.engine.fuel = 1_000_000;
                    const body_result = engine_expr.evaluate(self.store, self.env, self.engine, body_id, 0) catch |err| {
                        return try std.fmt.allocPrint(self.allocator, "✗ test error: {}", .{err});
                    };
                    return try self.evalTestExpr(body_result);
                }

                if (std.mem.eql(u8, name, "assert_eq") and args.len == 2) {
                    // Interpréter derive/simplify inline avant d'évaluer
                    var left = args[0];
                    var right = args[1];
                    inline for (.{ &left, &right }) |side| {
                        const n = self.store.get(side.*);
                        if (n.tag == .apply) {
                            const fnode = self.store.get(n.payload);
                            if (fnode.tag == .sym) {
                                const head = self.store.interner.resolve(fnode.payload);
                                const cargs = self.store.spanSliceConst(n.span_a)[1..];
                                if (cargs.len == 1) {
                                    const arg_str = try expr.toStringInfix(self.store, cargs[0], self.allocator);
                                    defer self.allocator.free(arg_str);
                                    var rstr: ?[]u8 = null;
                                    defer if (rstr) |r| self.allocator.free(r);
                                    if (std.mem.eql(u8, head, "derive")) {
                                        rstr = self.math.derive(arg_str, "x") catch null;
                                    } else if (std.mem.eql(u8, head, "simplify")) {
                                        rstr = self.evalSimplify(arg_str) catch null;
                                    }
                                    if (rstr) |rs| side.* = self.parseExpression(rs) catch side.*;
                                }
                            }
                        }
                    }
                    self.engine.fuel = 1_000_000;
                    const left_v = engine_expr.evaluate(self.store, self.env, self.engine, left, 0) catch left;
                    const right_v = engine_expr.evaluate(self.store, self.env, self.engine, right, 0) catch right;

                    // 1. Identité rapide
                    if (left_v == right_v) {
                        return try self.allocator.dupe(u8, "✓ assert_eq passed");
                    }

                    // 2. Comparaison textuelle
                    const l_str = try expr.toStringInfix(self.store, left_v, self.allocator);
                    const r_str = try expr.toStringInfix(self.store, right_v, self.allocator);
                    if (std.mem.eql(u8, l_str, r_str)) {
                        return try self.allocator.dupe(u8, "✓ assert_eq passed");
                    }

                    // 3. Comparaison sémantique : simplifier les deux puis comparer
                    const l_simp = self.math.simplifyBasic(left_v) catch left_v;
                    const r_simp = self.math.simplifyBasic(right_v) catch right_v;

                    if (self.math.structuralEq(l_simp, r_simp)) {
                        return try self.allocator.dupe(u8, "✓ assert_eq passed");
                    }
                    const ls_str = try expr.toStringInfix(self.store, l_simp, self.allocator);
                    const rs_str = try expr.toStringInfix(self.store, r_simp, self.allocator);
                    if (std.mem.eql(u8, ls_str, rs_str)) {
                        return try self.allocator.dupe(u8, "✓ assert_eq passed");
                    }

                    return try std.fmt.allocPrint(self.allocator, "✗ assert_eq failed: {s} != {s}", .{ l_str, r_str });
                }

                if (std.mem.eql(u8, name, "assert_err") and args.len == 1) {
                    self.engine.fuel = 1_000_000;
                    const result = engine_expr.evaluate(self.store, self.env, self.engine, args[0], 0);
                    if (result) |_| {
                        return try self.allocator.dupe(u8, "✗ assert_err failed: expected error but got value");
                    } else |_| {
                        return try self.allocator.dupe(u8, "✓ assert_err passed");
                    }
                }
            }
        }
        // Fallback
        self.engine.fuel = 1_000_000;
        const result = engine_expr.evaluate(self.store, self.env, self.engine, id, 0) catch id;
        return expr.toStringInfix(self.store, result, self.allocator);
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

    fn simplifyOnePass(self: *Commands, id: Id, buf: *std.ArrayListUnmanaged(u8), step: *u32) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        var current = id;
        if (node.tag == .apply) {
            const func_id = node.payload;
            const args_span = node.span_a;
            const old_args = args_span.slice(self.store.pool.items);
            if (old_args.len == 2) {
                const arg0 = old_args[0];
                const arg1 = old_args[1];
                const new_l = try self.simplify_eng.simplifyOnePass(arg0, buf, step);
                const new_r = try self.simplify_eng.simplifyOnePass(arg1, buf, step);
                if (new_l != arg0 or new_r != arg1) {
                    if (func_id < self.store.len()) {
                        const func_node = self.store.get(func_id);
                        if (func_node.tag == .sym) {
                            const op_name = self.store.interner.resolve(func_node.payload);
                            current = try self.store.binop(op_name, new_l, new_r);
                        }
                    }
                }
            }
        }
        if (current >= self.store.len()) return current;
        for (self.kb.rules.items) |rule_id| {
            if (rule_id >= self.store.len()) continue;
            const rule_node = self.store.get(rule_id);
            if (rule_node.tag != .relation) continue;
            const lhs_rhs = rule_node.span_a.slice(self.store.pool.items);
            if (lhs_rhs.len != 2) continue;
            const lhs_id = lhs_rhs[0];
            const rhs_id = lhs_rhs[1];
            var bindings: std.AutoHashMapUnmanaged(u32, Id) = .{};
            defer bindings.deinit(self.allocator);
            if (pattern_mod.exprPatternMatch(self.store, lhs_id, current, &bindings, self.allocator)) {
                const new_id = pattern_mod.substitutePattern(self.store, rhs_id, &bindings, self.allocator) catch continue;
                if (new_id < self.store.len() and new_id != current) {
                    const lhs_str = expr.toString(self.store, lhs_id, self.allocator) catch continue;
                    defer self.allocator.free(lhs_str);
                    const rhs_str = expr.toString(self.store, rhs_id, self.allocator) catch continue;
                    defer self.allocator.free(rhs_str);
                    const new_str = expr.toString(self.store, new_id, self.allocator) catch continue;
                    defer self.allocator.free(new_str);
                    var tmp: [16]u8 = undefined;
                    const sn = std.fmt.bufPrint(&tmp, "  step {d}: ", .{step.*}) catch "  step ?: ";
                    buf.appendSlice(self.allocator, sn) catch continue;
                    buf.appendSlice(self.allocator, new_str) catch continue;
                    buf.appendSlice(self.allocator, "  [") catch continue;
                    buf.appendSlice(self.allocator, lhs_str) catch continue;
                    buf.appendSlice(self.allocator, " → ") catch continue;
                    buf.appendSlice(self.allocator, rhs_str) catch continue;
                    buf.appendSlice(self.allocator, "]\n") catch continue;
                    step.* += 1;
                    return new_id;
                }
            }
        }
        if (current < self.store.len()) {
            self.engine.fuel = 100;
            const folded = engine_expr.evaluate(self.store, self.env, self.engine, current, 0) catch current;
            if (folded != current and folded < self.store.len()) {
                const folded_node = self.store.get(folded);
                if (folded_node.tag == .lit) {
                    const old_str = expr.toString(self.store, current, self.allocator) catch return current;
                    defer self.allocator.free(old_str);
                    const new_str = expr.toString(self.store, folded, self.allocator) catch return current;
                    defer self.allocator.free(new_str);
                    var tmp: [16]u8 = undefined;
                    const sn = std.fmt.bufPrint(&tmp, " step {d}: ", .{step.*}) catch " step ?: ";
                    buf.appendSlice(self.allocator, sn) catch {};
                    buf.appendSlice(self.allocator, new_str) catch {};
                    buf.appendSlice(self.allocator, " [eval ") catch {};
                    buf.appendSlice(self.allocator, old_str) catch {};
                    buf.appendSlice(self.allocator, "]\n") catch {};
                    step.* += 1;
                    return folded;
                }
            }
        }
        return current;
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
        const colon_pos = std.mem.indexOfScalar(u8, input, ':') orelse
            return try self.allocator.dupe(u8, "Usage: theorem <name> : <stmt>");
        const name = std.mem.trim(u8, input[0..colon_pos], " ");
        const stmt = std.mem.trim(u8, input[colon_pos + 1 ..], " ");
        const has_proof_block = std.mem.indexOf(u8, stmt, "{") != null;
        var proof_text: ?[]const u8 = null;
        var stmt_clean = stmt;
        if (has_proof_block) {
            const brace_pos = std.mem.indexOf(u8, stmt, "{").?;
            stmt_clean = std.mem.trim(u8, stmt[0..brace_pos], " ");
            proof_text = stmt[brace_pos..];
            if (!std.mem.startsWith(u8, stmt_clean, "forall") and std.mem.indexOf(u8, stmt_clean, "Eq<") == null) {
                const eq_pos = std.mem.indexOf(u8, stmt_clean, "=") orelse return try self.allocator.dupe(u8, "Invalid syntax");
                var lhs = std.mem.trim(u8, stmt_clean[0..eq_pos], " ");
                var rhs = std.mem.trim(u8, stmt_clean[eq_pos + 1 ..], " ");
                var lhs_buf: [256]u8 = undefined;
                var rhs_buf: [256]u8 = undefined;
                const ops = [_]struct { char: u8, name: []const u8 }{
                    .{ .char = '+', .name = "add" }, .{ .char = '*', .name = "mul" },
                    .{ .char = '-', .name = "sub" }, .{ .char = '/', .name = "div" },
                };
                for (ops) |op| {
                    if (std.mem.indexOfScalar(u8, lhs, op.char)) |pos| {
                        const a = std.mem.trim(u8, lhs[0..pos], " ");
                        const b = std.mem.trim(u8, lhs[pos + 1 ..], " ");
                        lhs = try std.fmt.bufPrint(&lhs_buf, "({s} {s} {s})", .{ op.name, a, b });
                        break;
                    }
                }
                for (ops) |op| {
                    if (std.mem.indexOfScalar(u8, rhs, op.char)) |pos| {
                        const a = std.mem.trim(u8, rhs[0..pos], " ");
                        const b = std.mem.trim(u8, rhs[pos + 1 ..], " ");
                        rhs = try std.fmt.bufPrint(&rhs_buf, "({s} {s} {s})", .{ op.name, a, b });
                        break;
                    }
                }
                var buf: [1024]u8 = undefined;
                stmt_clean = try std.fmt.bufPrint(&buf, "Eq<{s}, {s}>", .{ lhs, rhs });
            }
        }
        const is_new_format = std.mem.startsWith(u8, stmt_clean, "forall") or std.mem.indexOf(u8, stmt_clean, "Eq<") != null;
        if (is_new_format) {
            var src_buf: [1024]u8 = undefined;
            const src = try std.fmt.bufPrint(&src_buf, "theorem {s} : {s}", .{ name, stmt_clean });
            var tmp_store = Store.init(self.allocator);
            defer tmp_store.deinit();
            if (@import("builtin").target.cpu.arch == .wasm32) return error.NotSupported;
            const root_id = elab_mod.elaborateSource(self.allocator, &tmp_store, src, null) catch |err| {
                var buf: [128]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "✗ elaboration failed: {}", .{err});
                return try self.allocator.dupe(u8, msg);
            };
            const eq_args = proof_helpers_mod.extractEqArgsFromStore(&tmp_store, root_id) orelse
                return try self.allocator.dupe(u8, "✗ could not extract Eq<lhs,rhs> from statement");
            const lhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, self.store, eq_args.lhs);
            const rhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, self.store, eq_args.rhs);
            const lhs_canon = try canon_mod.canonicalize(self.store, self.allocator, lhs);
            const rhs_canon = try canon_mod.canonicalize(self.store, self.allocator, rhs);
            var proof_term: ?*const proof_core.ProofTerm = null;
            if (proof_text) |pt| proof_term = proof_helpers_mod.ProofHelpers.parseProofBlock(self.allocator, pt);
            try self.proof_core.theorem(name, stmt, lhs_canon, rhs_canon);
            if (proof_term) |pt| {
                if (self.proof_core.theorems.getPtr(name)) |thm| {
                    thm.proof = pt;
                    thm.verified = true;
                }
            }
            const rule_id = try self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
            try self.kb.rules.append(self.allocator, rule_id);
            if (self.active_theorem.*) |old| self.allocator.free(old);
            self.active_theorem.* = try self.allocator.dupe(u8, name);
            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
            return try self.allocator.dupe(u8, msg);
        }
        const eq_pos = std.mem.indexOf(u8, stmt, "=") orelse
            return try self.allocator.dupe(u8, "Usage: theorem <name> : <lhs> = <rhs>");
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " ");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 1 ..], " ");

        // Parser correctement les côtés de l'équation
        const lhs = self.parseExpression(lhs_str) catch try self.bridge.importExpr(lhs_str);
        const rhs = self.parseExpression(rhs_str) catch try self.bridge.importExpr(rhs_str);
        const lhs_canon = try canon_mod.canonicalize(self.store, self.allocator, lhs);
        const rhs_canon = try canon_mod.canonicalize(self.store, self.allocator, rhs);
        try self.proof_core.theorem(name, stmt, lhs_canon, rhs_canon);
        const rule_id = try self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
        try self.kb.rules.append(self.allocator, rule_id);
        if (self.active_theorem.*) |old| self.allocator.free(old);
        self.active_theorem.* = try self.allocator.dupe(u8, name);
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
        return try self.allocator.dupe(u8, msg);
    }

    pub fn evalProve(self: *Commands, input: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " ");
        if (std.mem.startsWith(u8, trimmed, "by ")) {
            const rest = trimmed[3..];
            var skill_name: []const u8 = rest;
            var induction_var: []const u8 = "n";
            if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
                skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
                induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
            }
            const target = self.active_theorem.* orelse
                return try self.allocator.dupe(u8, "No active theorem. Use 'theorem <name> : ...' first.");
            const request_msg = try std.fmt.allocPrint(self.allocator, "proof_request|{s}|{s}|{s}", .{ target, skill_name, induction_var });
            if (self.pending_proof_request.*) |old| self.allocator.free(old);
            self.pending_proof_request.* = request_msg;
            return self.proveWith(target, skill_name, induction_var);
        }
        if (std.mem.indexOf(u8, trimmed, " by ")) |by_pos| {
            const name = std.mem.trim(u8, trimmed[0..by_pos], " ");
            const rest = std.mem.trim(u8, trimmed[by_pos + 4 ..], " ");
            var skill_name: []const u8 = rest;
            var induction_var: []const u8 = "n";
            if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
                skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
                induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
            }

            if (self.active_theorem.*) |old| self.allocator.free(old);
            self.active_theorem.* = try self.allocator.dupe(u8, name);

            const request_msg = try std.fmt.allocPrint(self.allocator, "proof_request|{s}|{s}|{s}", .{ name, skill_name, induction_var });
            if (self.pending_proof_request.*) |old| self.allocator.free(old);
            self.pending_proof_request.* = request_msg;
            return self.proveWith(name, skill_name, induction_var);
        }
        return try self.allocator.dupe(u8, "Usage: prove [name] by <method> [on <var>]");
    }

    fn proveWith(self: *Commands, target: []const u8, skill_name: []const u8, induction_var: []const u8) ![]u8 {
        const normalized = std.mem.trim(u8, skill_name, " ");
        if (std.mem.eql(u8, normalized, "simplify")) {
            const ok = try self.proof_core.verifyBySimplify(target, self);
            return self.proofResult(target, ok, "simplify");
        }
        if (std.mem.eql(u8, normalized, "eval")) {
            const ok = try self.proof_core.verifyByEval(target, self.engine, self.env, self.store);
            return self.proofResult(target, ok, "eval");
        }
        if (std.mem.eql(u8, normalized, "induction")) {
            const ok = try self.proof_core.verifyByInduction(target, induction_var, self, self.store);
            return self.proofResult(target, ok, "induction");
        }
        if (std.mem.eql(u8, normalized, "rewrite")) {
            const ok = try self.proof_core.verifyByRewrite(target, self);
            return self.proofResult(target, ok, "rewrite");
        }
        return self.evalSkill(normalized);
    }

    fn proofResult(self: *Commands, target: []const u8, ok: bool, method: []const u8) ![]u8 {
        if (ok) {
            if (self.proof_core.theorems.getPtr(target)) |thm| thm.verified = true;
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, method });
            return try self.allocator.dupe(u8, msg);
        } else {
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✗ [{s}] proof failed ({s})", .{ target, method });
            return try self.allocator.dupe(u8, msg);
        }
    }

    pub fn evalSkill(self: *Commands, input: []const u8) ![]u8 {
        const skill_name = std.mem.trim(u8, input, " ");
        const target = self.active_theorem.* orelse return try self.allocator.dupe(u8, "No active theorem.");
        const thm = self.proof_core.theorems.getPtr(target) orelse return try self.allocator.dupe(u8, "Theorem not found");
        const ok = if (std.mem.eql(u8, skill_name, "simplify")) try self.proof_core.verifyBySimplify(target, self) else if (std.mem.eql(u8, skill_name, "eval")) try self.proof_core.verifyByEval(target, self.engine, self.env, self.store) else if (std.mem.eql(u8, skill_name, "induction")) try self.proof_core.verifyByInduction(target, "n", self, self.store) else if (std.mem.eql(u8, skill_name, "algebra")) try self.proof_core.verifyBySimplify(target, self) else return try self.allocator.dupe(u8, "skill: unknown tactic");
        if (ok) {
            thm.verified = true;
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, skill_name });
            return try self.allocator.dupe(u8, msg);
        } else return try self.allocator.dupe(u8, "✗ proof failed");
    }

    fn evalLet(self: *Commands, input: []const u8) ![]u8 {
        if (std.mem.indexOf(u8, input, " in ")) |_| {
            const ast = self.parser.parseLetExpr(input) catch return try self.allocator.dupe(u8, "syntax error in let expression");
            self.engine.fuel = 10_000;
            const result = engine_expr.evaluate(self.store, self.env, self.engine, ast, 0) catch ast;
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        const op_len: usize = if (std.mem.startsWith(u8, input, ":=")) 2 else 1;
        var eq_pos: ?usize = null;
        var i: usize = input.len;
        while (i > 1) : (i -= 1) {
            if (input[i - 1] == '=') {
                const prev_c = if (i >= 2) input[i - 2] else ' ';
                if (prev_c != '!' and prev_c != '<' and prev_c != '>') {
                    if (op_len == 1 or prev_c == ':') {
                        eq_pos = i - 1;
                        break;
                    }
                }
            }
        }

        if (eq_pos) |eq| {
            const name = std.mem.trim(u8, input[0..eq], " \t:");
            const expr_str = std.mem.trim(u8, input[eq + 1 ..], " \t");

            if (std.mem.startsWith(u8, expr_str, "fn ") or std.mem.startsWith(u8, expr_str, "fn(")) {
                const fn_def_str = try std.fmt.allocPrint(self.allocator, "{s} = {s}", .{ name, expr_str });
                defer self.allocator.free(fn_def_str);
                return self.evalFnDef(fn_def_str);
            }

            if (std.mem.indexOfScalar(u8, name, ' ') != null) {
                const fn_def_str = try std.fmt.allocPrint(self.allocator, "{s} = {s}", .{ name, expr_str });
                defer self.allocator.free(fn_def_str);
                return self.evalFnDef(fn_def_str);
            }

            return self.define(name, expr_str);
        }

        return try self.allocator.dupe(u8, "syntax error: missing =");
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
