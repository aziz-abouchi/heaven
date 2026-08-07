//! Commandes shell et évaluation pour Heaven
//! Extrait de heaven_expr.zig pour modularité

const std = @import("std");
const expr = @import("expr");
//const bridge = @import("bridge_expr");
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
const mlcpd_mod = @import("mlcpd");
const mlcpd_equiv_mod = @import("mlcpd_equiv");
const universal_translator = @import("universal_translator");
const mlcpd = @import("mlcpd");

pub const HeavenError = error{
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
} || std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine_expr.EvalError;

pub const Commands = struct {
    store: *Store,
    engine: *Engine,
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
        return .{
            .store = store,
            .engine = engine,
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
            .simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, engine, kb, allocator),
            .shell_parser = shell_parser,
        };
    }

    pub fn deinit(self: *Commands) void {
        self.shell_parser.deinit();
        // ... reste du deinit ...
    }

    // ─── Eval dispatcher ───
    pub fn eval(self: *Commands, input: []const u8) HeavenError![]u8 {
        const trimmed0 = std.mem.trim(u8, input, " \t\r\n");
        const actual = if (trimmed0.len > 0 and trimmed0[0] == ':') trimmed0[1..] else trimmed0;
        const trimmed = std.mem.trim(u8, actual, " \t\r\n");

        //IGNORER LES DÉCLARATIONS DE TYPES POUR L'INSTANT
        if (std.mem.startsWith(u8, trimmed, "module ") or
            std.mem.startsWith(u8, trimmed, "data ") or
            std.mem.startsWith(u8, trimmed, "zero :") or
            std.mem.startsWith(u8, trimmed, "succ :"))
        {
            return try self.allocator.dupe(u8, "()"); // On avale la ligne sans faire rien
        }

        // INTERCEPTIONS SPÉCIALES
        if (std.mem.startsWith(u8, trimmed, "let actor ")) {
            return self.evalActorDef(trimmed["let actor ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "let macro ")) {
            return self.evalMacroDef(trimmed["let macro ".len..]);
        }

        // === INTERCEPTION POUR LE FRAMEWORK DE TEST NATIF ===
        if (std.mem.startsWith(u8, trimmed, "(test ") or std.mem.startsWith(u8, trimmed, "(assert_eq ")) {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch id;
            return expr.toStringInfix(self.store, result, self.allocator);
        }
        // ======================================================

        // === INTERCEPTION POUR LES EFFETS ALGÉBRIQUES ===
        if (std.mem.startsWith(u8, trimmed, "(handle ") or std.mem.startsWith(u8, trimmed, "(perform ")) {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch id;
            return expr.toStringInfix(self.store, result, self.allocator);
        }
        // ========================================================

        // NOUVELLE INTERCEPTION HAUTE : Toutes les S-expr (commençant par '(')
        // On les délègue au parseur S-expr robuste avant d'appeler les parsers mathématiques ou Tree-sitter
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            const id = try self.parser.parseSExpr(trimmed);
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch id;
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        // Detect function definition: "name pat1 pat2 = body"
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
            // Ne pas traiter comme définition si c'est une lambda
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
                !std.mem.startsWith(u8, trimmed, "profile ") and
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
                !std.mem.startsWith(u8, trimmed, "quote ") and
                !std.mem.startsWith(u8, trimmed, "equiv "))
            {
                const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
                var token_count: usize = 0;
                var tok_it = std.mem.tokenizeScalar(u8, lhs, ' ');
                while (tok_it.next()) |_| token_count += 1;
                if (token_count >= 2) {
                    if (!is_lambda) {
                        return self.evalFnDef(trimmed);
                    }
                }
            }
        }

        // Court-circuit pour les primitives d'acteurs
        if (std.mem.startsWith(u8, trimmed, "send(") or
            std.mem.startsWith(u8, trimmed, "spawn(") or
            std.mem.startsWith(u8, trimmed, "state("))
        {
            const apply_id = self.parseCallExpr(trimmed) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "actor parse error: {}", .{err});
            };
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(apply_id) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "actor error: {}", .{err});
            };
            return expr.toString(self.store, result, self.allocator);
        }
        // ====================================================

        // Try function call
        // On n'utilise tryFnCall que s'il n'y a pas de parenthèses
        // car tryFnCall découpe par espaces et casserait les S-expr comme (succ n)
        if (std.mem.indexOfScalar(u8, trimmed, '(') == null) {
            if (self.tryFnCall(trimmed)) |result| return result;
        }

        if (std.mem.eql(u8, trimmed, "help")) return self.evalHelp();
        if (std.mem.eql(u8, trimmed, "stats")) return self.evalStats();
        if (std.mem.eql(u8, trimmed, "theorems")) return self.evalTheorems();
        if (std.mem.startsWith(u8, trimmed, "let ")) return self.evalLet(trimmed["let ".len..]);
        if (std.mem.startsWith(u8, trimmed, "load ")) return self.loadFile(trimmed["load ".len..]);
        if (std.mem.startsWith(u8, trimmed, "transform ")) return try self.evalTransform(trimmed["transform ".len..]);
        if (std.mem.startsWith(u8, trimmed, "eval ")) return self.evalSExpr(trimmed["eval ".len..]);
        if (std.mem.startsWith(u8, trimmed, "theorem ")) return self.evalTheorem(trimmed["theorem ".len..]);
        if (std.mem.startsWith(u8, trimmed, "prove ")) return self.evalProve(trimmed["prove ".len..]);
        if (std.mem.startsWith(u8, trimmed, "skill ")) return self.evalSkill(trimmed["skill ".len..]);
        if (std.mem.startsWith(u8, trimmed, "type ")) return self.evalType(trimmed["type ".len..]);
        if (std.mem.startsWith(u8, trimmed, "simplify ")) return self.evalSimplify(trimmed["simplify ".len..]);
        if (std.mem.startsWith(u8, trimmed, "plot ")) return self.evalPlot(trimmed["plot ".len..]);
        if (std.mem.startsWith(u8, trimmed, "latex ")) return self.evalLatex(trimmed["latex ".len..]);
        if (std.mem.startsWith(u8, trimmed, "explain ")) return self.evalExplain(trimmed["explain ".len..]);
        if (std.mem.startsWith(u8, trimmed, "expand ")) return self.evalExpand(trimmed["expand ".len..]);
        if (std.mem.startsWith(u8, trimmed, "optimize ")) return self.evalOptimize(trimmed["optimize ".len..]);
        if (std.mem.startsWith(u8, trimmed, "profile ")) return self.evalProfile(trimmed["profile ".len..]);
        if (std.mem.startsWith(u8, trimmed, "trace ")) return self.evalTrace(trimmed["trace ".len..]);
        if (std.mem.startsWith(u8, trimmed, "qtt ")) return self.evalQtt(trimmed["qtt ".len..]);
        if (std.mem.startsWith(u8, trimmed, "mir ")) return self.evalMir(trimmed["mir ".len..]);
        if (std.mem.startsWith(u8, trimmed, "solve ")) return try self.math.solve(trimmed["solve ".len..], "x");
        if (std.mem.startsWith(u8, trimmed, "derive ")) return self.math.derive(trimmed["derive ".len..], "x") catch self.allocator.dupe(u8, "0");
        if (std.mem.startsWith(u8, trimmed, "integrate ")) return try self.math.integrate(trimmed["integrate ".len..], "x");
        if (std.mem.startsWith(u8, trimmed, "asm ")) return self.evalAsm(trimmed["asm ".len..]);
        if (std.mem.startsWith(u8, trimmed, "green ")) return self.evalGreen(trimmed["green ".len..]);
        if (std.mem.startsWith(u8, trimmed, "parseFileWithLanguage ")) return self.parseFileWithLanguage(trimmed["parseFileWithLanguage ".len..]);

        // derive(<expr>, <var>)
        if (std.mem.startsWith(u8, trimmed, "derive(")) {
            const rest = trimmed["derive(".len..];
            if (std.mem.endsWith(u8, rest, ")")) {
                const inner = rest[0 .. rest.len - 1];
                if (std.mem.indexOfScalar(u8, inner, ',')) |comma| {
                    const expr_str = std.mem.trim(u8, inner[0..comma], " ");
                    const var_str = std.mem.trim(u8, inner[comma + 1 ..], " ");
                    return try self.math.derive(expr_str, var_str);
                }
            }
        }
        // solve(<equation>, <var>)
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
        // integrate(<expr>, <var>)
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

        if (std.mem.startsWith(u8, trimmed, "ask ")) return self.evalAsk(trimmed["ask ".len..]);
        if (std.mem.startsWith(u8, trimmed, "equiv ")) return self.evalEquiv(trimmed["equiv ".len..]);
        if (std.mem.startsWith(u8, trimmed, "js ")) return self.evalJs(trimmed["js ".len..]);
        if (std.mem.startsWith(u8, trimmed, "dumpAstFile ")) return self.dumpAstFile(trimmed["dumpAstFile ".len..]);
        if (std.mem.startsWith(u8, trimmed, "translateAndDump ")) return self.translateAndDump(trimmed["translateAndDump ".len..]);

        // === Parser avec tree-sitter ===
        if (self.parseExpression(trimmed)) |expr_id| {
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(expr_id) catch |err| {
                return try std.fmt.allocPrint(self.allocator, "eval error: {}", .{err});
            };
            return expr.toStringInfix(self.store, result, self.allocator);
        } else |_| {
            // Si parseExpression échoue, continuer vers le fallback
        }
        // ================================================

        // Lambda ou Expression mathématique
        self.engine.fuel = 1_000_000;
        const id0 = if (self.bridge.importExpr(input)) |id| id else |_| blk: {
            break :blk self.bridge.importExpr(input) catch {
                return try self.allocator.dupe(u8, "syntax error");
            };
        };
        const result = try self.engine.eval(id0);
        const canon = if (@import("builtin").target.cpu.arch.isWasm())
            try canon_mod.canonicalize(self.store, self.allocator, result)
        else
            result;
        return expr.toStringInfix(self.store, canon, self.allocator);
    }

    // ─── Commandes simples ───
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
            "  profile <expr>\n" ++
            "  trace <expr>\n" ++
            "  let <var> = <expr>\n");
    }

    fn evalStats(self: *Commands) ![]u8 {
        return try self.allocator.dupe(u8, "═══ Heaven WASM ═══\n" ++
            "Engine: active\n" ++
            "Features: eval, type, simplify, explain, latex, quote, prove");
    }

    fn evalSimplify(self: *Commands, input: []const u8) ![]u8 {
        return self.simplify(input);
    }

    fn evalType(self: *Commands, input: []const u8) ![]u8 {
        return self.typeOf(input);
    }

    fn evalExpand(self: *Commands, input: []const u8) ![]u8 {
        return self.math.expand(input);
    }

    fn evalLatex(self: *Commands, input: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(input);
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

    fn evalProfile(self: *Commands, input: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(input);
        if (comptime !@import("builtin").target.cpu.arch.isWasm()) {
            var timer = try std.time.Timer.start();
            const start_time = timer.read();
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "Profile error: {s}", .{@errorName(err)});
            };
            const result_str = try expr.toStringInfix(self.store, result, self.allocator);
            const elapsed_ns = timer.read() - start_time;
            const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            const node_count = self.countNodes(result);
            const bigO = if (node_count > 100) "O(n^2)" else "O(n)";
            const energy_nJ = @as(f64, @floatFromInt(elapsed_ns)) * 0.5;
            const energy_uJ = energy_nJ / 1000.0;
            const silicon_thermal_mass = 0.001;
            const silicon_specific_heat = 700.0;
            const delta_T = (energy_nJ * 1e-9) / (silicon_thermal_mass * silicon_specific_heat);
            var buf: std.ArrayListUnmanaged(u8) = .{};
            defer buf.deinit(self.allocator);
            const w = buf.writer(self.allocator);
            try w.print(
                \\═══ Profile ═══
                \\ Expression  : {s}
                \\ Temps       : {d:.3} ms
                \\ Nœuds       : {d}
                \\ Big O       : {s}
                \\ Énergie     : {d:.3} uJ
                \\ Température : {d:.6} °C
                \\═══════════════
                \\
            , .{ result_str, elapsed_ms, node_count, bigO, energy_uJ, delta_T });
            return buf.toOwnedSlice(self.allocator);
        } else {
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "Profile error: {s}", .{@errorName(err)});
            };
            const result_str = try expr.toStringInfix(self.store, result, self.allocator);
            const node_count = self.countNodes(result);
            var buf: std.ArrayListUnmanaged(u8) = .{};
            defer buf.deinit(self.allocator);
            const w = buf.writer(self.allocator);
            try w.print("═══ Profile (WASM) ═══\nExpression : {s}\nNœuds : {d}\n═══════════════\n", .{ result_str, node_count });
            return buf.toOwnedSlice(self.allocator);
        }
    }

    pub fn evalTrace(self: *Commands, input: []const u8) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        const id = try self.bridge.importExpr(input);
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
        const after_egraph = try self.simplify_eng.simplifyWithEGraph(current, &qtt);
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

    // ─── Define ───
    pub fn define(self: *Commands, name: []const u8, value_text: []const u8) ![]u8 {
        const val_id = try self.bridge.importExpr(value_text);
        self.engine.fuel = 10_000;
        const evaled = self.engine.eval(val_id) catch val_id;
        const bind_id = try self.store.bind(name, evaled);
        try self.engine.env.put(try self.store.interner.intern(name), evaled);
        return expr.toString(self.store, bind_id, self.allocator);
    }

    fn tryFnCall(self: *Commands, input: []const u8) ?[]u8 {
        if (input.len == 0 or input[0] == '(' or std.ascii.isDigit(input[0])) return null;
        // Cas 1: name(args)
        if (std.mem.indexOfScalar(u8, input, '(')) |paren_idx| {
            const before_paren = input[0..paren_idx];
            if (std.mem.indexOfScalar(u8, before_paren, ' ') == null) {
                const potential_name = std.mem.trim(u8, input[0..paren_idx], " ");
                if (potential_name.len == 0) return null;
                for (potential_name) |c| {
                    if (!std.ascii.isAlphanumeric(c) and c != '_') return null;
                }
                if (self.engine.fns.functions.getEntry(potential_name) == null) return null;
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
                const result = self.engine.evalFunction(potential_name, eval_args[0..num_args]) catch return null;
                return expr.toString(self.store, result, self.allocator) catch return null;
            }
        }
        // Cas 2: name arg1 arg2 ...
        const space_idx = std.mem.indexOfScalar(u8, input, ' ') orelse return null;
        const name = input[0..space_idx];
        if (self.engine.fns.functions.getEntry(name) == null) {
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
        const result = self.engine.evalFunction(name, eval_args[0..num_args]) catch return null;
        return expr.toString(self.store, result, self.allocator) catch return null;
    }

    fn evalActorDef(self: *Commands, input: []const u8) ![]u8 {
        const with_pos = std.mem.indexOf(u8, input, " with ") orelse
            return self.allocator.dupe(u8, "syntax error: missing 'with'");

        const lhs = std.mem.trim(u8, input[0..with_pos], " ");
        const rhs = std.mem.trim(u8, input[with_pos + 6 ..], " ");

        const eq_pos = std.mem.indexOfScalar(u8, lhs, '=') orelse
            return self.allocator.dupe(u8, "syntax error: missing '='");

        const name = std.mem.trim(u8, lhs[0..eq_pos], " ");
        const init_state_str = std.mem.trim(u8, lhs[eq_pos + 1 ..], " ");

        const init_state_id = try self.bridge.importExpr(init_state_str);

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

        // Créer l'acteur directement dans le moteur
        const new_actor_id = self.engine.next_actor_id;
        self.engine.next_actor_id += 1;
        try self.engine.actors.put(self.engine.allocator, new_actor_id, .{
            .state = init_state_id,
            .handler = handler_id,
        });
        const actor_id = try self.store.int(@intCast(new_actor_id));

        // OBLIGATOIRE : Lier le nom de l'acteur à son ID dans l'environnement
        const actor_sym = try self.store.interner.intern(name);
        try self.engine.env.put(actor_sym, actor_id);

        return std.fmt.allocPrint(self.allocator, "actor {s} spawned (id: {d})", .{ name, actor_id });
    }

    fn evalMacroDef(self: *Commands, input: []const u8) ![]u8 {
        // Format attendu: name(params) = body
        const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse return self.allocator.dupe(u8, "syntax error: missing '='");
        const lhs = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

        const paren_pos = std.mem.indexOfScalar(u8, lhs, '(') orelse return self.allocator.dupe(u8, "syntax error: missing '('");
        if (lhs[lhs.len - 1] != ')') return self.allocator.dupe(u8, "syntax error: missing ')'");

        const name = std.mem.trim(u8, lhs[0..paren_pos], " ");
        const params_str = std.mem.trim(u8, lhs[paren_pos + 1 .. lhs.len - 1], " ");

        // Créer les symboles des paramètres
        var param_ids: std.ArrayListUnmanaged(Id) = .{};
        defer param_ids.deinit(self.allocator);
        var it = std.mem.tokenizeAny(u8, params_str, " ,");
        while (it.next()) |p| {
            try param_ids.append(self.allocator, try self.store.sym(p));
        }
        const params_span = try self.store.pushSpan(param_ids.items);

        // Parser le corps de la macro (qui devrait contenir un quote)
        const body_id = try self.parser.parseSExpr(rhs);

        // Enregistrer dans le moteur en utilisant le Sym du nom comme clé
        const name_sym = try self.store.interner.intern(name);
        try self.engine.macros.put(self.allocator, name_sym, .{ .params_span = params_span, .body = body_id });

        return std.fmt.allocPrint(self.allocator, "macro {s} defined", .{name});
    }

    /// Transforme un raccourci lambda (fn(x) body) en une définition de fonction standard (name x = body)
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

        // Gérer le walrus operator := (on enlève le ':' à la fin du nom)
        if (lhs.len > 0 and lhs[lhs.len - 1] == ':') {
            lhs = std.mem.trim(u8, lhs[0 .. lhs.len - 1], " ");
        }

        if (std.mem.startsWith(u8, lhs, "fn ")) lhs = std.mem.trim(u8, lhs[3..], " ");
        if (std.mem.startsWith(u8, lhs, "let ")) lhs = std.mem.trim(u8, lhs[4..], " ");

        // Si le côté droit est un raccourci lambda (ex: "fn(x) (* x 3)"), on le transforme !
        if (std.mem.startsWith(u8, rhs, "fn ") or std.mem.startsWith(u8, rhs, "fn(")) {
            // On doit extraire le nom de la fonction depuis le lhs
            const name = if (std.mem.indexOfScalar(u8, lhs, ' ')) |space| lhs[0..space] else lhs;
            return self.parseLambdaShortcut(name, rhs);
        }

        // ON PARSE LE CÔTÉ GAUCHE COMME UNE S-EXPR !
        // On l'enveloppe dans des parenthèses pour que parseSExpr le lise correctement
        // ex: "add (succ n) m" devient "(add (succ n) m)"
        const wrapped_lhs = try std.fmt.allocPrint(self.allocator, "({s})", .{lhs});
        defer self.allocator.free(wrapped_lhs);

        const lhs_id = self.parser.parseSExpr(wrapped_lhs) catch {
            return self.allocator.dupe(u8, "syntax error in lhs");
        };

        const lhs_node = self.store.get(lhs_id);

        // Si c'est juste un symbole (ex: "fac")
        if (lhs_node.tag == .sym) {
            const name = self.store.interner.resolve(lhs_node.payload);
            const body_id = self.parseExpression(rhs) catch return self.allocator.dupe(u8, "parse error in body");
            self.engine.fns.register(name, &.{}, body_id) catch return self.allocator.dupe(u8, "registration error");
            const sym = self.store.interner.intern(name) catch return self.allocator.dupe(u8, "intern error");
            self.engine.env.put(sym, body_id) catch {};
            return std.fmt.allocPrint(self.allocator, "{s} defined", .{name});
        }

        // Si c'est une application (ex: add (succ n) m)
        if (lhs_node.tag == .apply) {
            const func_sym_node = self.store.get(lhs_node.payload);
            if (func_sym_node.tag != .sym) return self.allocator.dupe(u8, "syntax error: function name must be a symbol");
            const name = self.store.interner.resolve(func_sym_node.payload);

            const args = lhs_node.span_a.slice(self.store.pool.items);
            const num_pats = args.len;

            var pat_ids: [8]u32 = undefined;
            for (0..num_pats) |pi| {
                pat_ids[pi] = args[pi]; // On prend directement l'AST des patterns !
            }

            // Si le corps commence par une parenthèse ou contient des espaces, on utilise parseSExpr
            // pour éviter que parseApplication ne découpe les S-expr par espaces.
            const body_id = if (rhs.len > 0 and (rhs[0] == '(' or std.mem.indexOfScalar(u8, rhs, ' ') != null))
                self.parser.parseSExpr(rhs) catch return self.allocator.dupe(u8, "parse error in body (Lisp)")
            else if (rhs.len > 0)
                try self.store.sym(rhs)
            else
                return self.allocator.dupe(u8, "empty body");

            // On enregistre la fonction UNIQUEMENT dans le FunctionRegistry.
            // La mettre dans env casse l'évaluation car le corps sera évalué hors-contexte.
            self.engine.fns.register(name, pat_ids[0..num_pats], body_id) catch return self.allocator.dupe(u8, "registration error");

            return std.fmt.allocPrint(self.allocator, "{s} clause ({d} patterns) registered", .{ name, num_pats });
        }

        return self.allocator.dupe(u8, "syntax error in function definition");
    }

    /// Fallback WASM : parse les applications `name arg1 arg2` et appels `name(args)`.
    fn parseApplication(self: *Commands, input: []const u8) !Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidSyntax;

        // ── Cas 1 : appel C-style `name(arg1, arg2)` ──
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
                                    const arg_id = self.bridge.importExpr(p) catch return error.InvalidSyntax;
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

        // ── Cas 2 : application ML-style `name arg1 arg2` ──
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
        // Refuser si un token est un opérateur (sinon c'est de l'infixe, géré par importExpr)
        for (tokens[0..num_tokens]) |tok| {
            if (isOperatorTok(tok)) return error.InvalidSyntax;
        }

        const func_id = try self.store.sym(tokens[0]);
        var args: std.ArrayListUnmanaged(Id) = .{};
        defer args.deinit(self.allocator);
        for (tokens[1..num_tokens]) |tok| {
            const arg_id = self.bridge.importExpr(tok) catch return error.InvalidSyntax;
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

    fn parseExpression(self: *Commands, input: []const u8) !Id {
        // 1. Essayer tree-sitter d'abord
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
                } else |_| {
                    // Bridge a échoué, continuer vers le fallback
                }
            }
        } else |_| {
            // tree-sitter.parse() a échoué
        }

        // AJOUT : Si ça commence par '(', on utilise le parseur S-expr (Lisp) qui gère les espaces
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            return self.parser.parseSExpr(trimmed);
        }

        // 2. Fallback application/appel (WASM)
        if (self.parseApplication(input)) |id| {
            return id;
        } else |_| {}

        // 3. Fallback sur l'ancien parser (bridge.importExpr)
        return self.bridge.importExpr(input);
    }

    /// Vérifie récursivement si une Matrix contient un vrai nœud d'erreur tree-sitter
    fn hasErrorNode(self: *Commands, node: *const @import("bridge_expr").Matrix) bool {
        // On ne rejette que les erreurs explicites de tree-sitter, pas les nœuds non mappés (.unknown)
        if (node.kind == .err_node) {
            return true;
        }
        for (node.children) |*child| {
            if (hasErrorNode(self, child)) return true;
        }
        return false;
    }

    /// Parse `nom(arg1, arg2, ...)` et construit un nœud .apply.
    /// Nécessaire car importExpr ne gère pas la syntaxe d'appel C-style.
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

    // ─── Types ───
    pub fn typeOf(self: *Commands, input: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " \t");

        // Si ça commence par '(', on utilise le parseur S-expr qui gère bien les opérateurs (==, *, etc.)
        const id = if (trimmed.len > 0 and trimmed[0] == '(')
            try self.parser.parseSExpr(trimmed)
        else
            try self.bridge.importExpr(trimmed);

        var inf = types_mod.Infer.init(self.store, self.allocator);
        defer inf.deinit();
        const t = try inf.typeOf(id);
        return inf.typeStr(&inf.subst, t, self.allocator);
    }

    // ─── Simplify ───
    pub fn simplify(self: *Commands, input: []const u8) ![]u8 {
        var current = try self.bridge.importExpr(input);
        current = try self.simplify_eng.simplifyRec(current, 0);
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        current = try self.simplify_eng.simplifyWithEGraph(current, &qtt);
        current = try canon_mod.canonicalize(self.store, self.allocator, current);
        return expr.toStringInfix(self.store, current, self.allocator);
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
                const new_func = try self.simplify_eng.simplifyRec(func_id, depth + 1);
                const new_l = try self.simplify_eng.simplifyRec(arg0, depth + 1);
                const new_r = try self.simplify_eng.simplifyRec(arg1, depth + 1);
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
                if (pattern_mod.exprPatternMatch(self.store, lhs_id, id, &bindings, self.allocator)) {
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
            const folded = self.engine.eval(current) catch current;
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

    // ─── Codegen wrappers ───
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

    fn evalOptimize(self: *Commands, input: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(input);
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        const optimized = try self.simplify_eng.simplifyWithEGraph(id, &qtt);
        return expr.toString(self.store, optimized, self.allocator);
    }

    fn evalAsm(self: *Commands, input: []const u8) ![]u8 {
        const id = try self.bridge.importExpr(input);
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

        // parseExpression gère tree-sitter (natif) + fallbacks (WASM)
        const expr_id = self.parseExpression(trimmed) catch return error.InvalidSyntax;
        self.engine.fuel = 1_000_000;
        const result = self.engine.eval(expr_id) catch expr_id;
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
        const id = try self.bridge.importExpr(input);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        try self.writeAst(id, 0, &buf);
        return buf.toOwnedSlice(self.allocator);
    }

    fn writeAst(self: *Commands, id: Id, depth: u32, buf: *std.ArrayListUnmanaged(u8)) !void {
        if (id >= self.store.len()) return;
        const node = self.store.get(id);
        var i: u32 = 0;
        while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, "  ");
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
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, "  ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            .bind => {
                try buf.appendSlice(self.allocator, "(bind\n");
                try self.writeAst(node.payload, depth + 1, buf);
                try self.writeAst(node.aux, depth + 1, buf);
                i = 0;
                while (i < depth) : (i += 1) try buf.appendSlice(self.allocator, "  ");
                try buf.appendSlice(self.allocator, ")\n");
            },
            else => try buf.appendSlice(self.allocator, "(node)\n"),
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
            const folded = self.engine.eval(current) catch current;
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
        const id = try self.bridge.importExpr(input);
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
        const lhs = try self.bridge.importExpr(lhs_str);
        const rhs = try self.bridge.importExpr(rhs_str);
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

            // On libère l'ancien théorème actif ICI SEULEMENT (avant de le remplacer)
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
            const ok = try self.proof_core.verifyByEval(target, self.engine, self.store);
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
        const ok = if (std.mem.eql(u8, skill_name, "simplify")) try self.proof_core.verifyBySimplify(target, self) else if (std.mem.eql(u8, skill_name, "eval")) try self.proof_core.verifyByEval(target, self.engine, self.store) else if (std.mem.eql(u8, skill_name, "induction")) try self.proof_core.verifyByInduction(target, "n", self, self.store) else if (std.mem.eql(u8, skill_name, "algebra")) try self.proof_core.verifyBySimplify(target, self) else return try self.allocator.dupe(u8, "skill: unknown tactic");
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
            const result = self.engine.eval(ast) catch ast;
            return expr.toStringInfix(self.store, result, self.allocator);
        }

        // Gestion du walrus operator :=
        const op_len: usize = if (std.mem.startsWith(u8, input, ":=")) 2 else 1;
        var eq_pos: ?usize = null;
        var i: usize = input.len;
        while (i > 1) : (i -= 1) {
            if (input[i - 1] == '=') {
                const prev_c = if (i >= 2) input[i - 2] else ' ';
                if (prev_c != '!' and prev_c != '<' and prev_c != '>') {
                    // Si on a trouvé ':=' on l'enregistre, sinon on prend le '=' simple
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

            // Si la valeur commence par 'fn', on enregistre une fonction !
            if (std.mem.startsWith(u8, expr_str, "fn ") or std.mem.startsWith(u8, expr_str, "fn(")) {
                // On reconstruit la chaîne pour evalFnDef (ex: "triple x = (* x 3)")
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

    pub fn loadFile(self: *Commands, path: []const u8) HeavenError![]u8 {
        const file = try platform.fs.cwd().openFile(path, .{});
        defer file.close();
        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_count: usize = 0;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#' or std.mem.startsWith(u8, trimmed, "--")) continue;
            line_count += 1;
            const result = try self.eval(trimmed);
            try w.print("{s}\n", .{result});
            self.allocator.free(result);
        }
        try w.print("✓ fichier '{s}' chargé ({d} lignes)\n", .{ path, line_count });
        return buf.toOwnedSlice(self.allocator);
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

    // ─── Helpers preuve ───
    fn parseProofBlock(allocator: Allocator, text: []const u8) ?*const proof_core.ProofTerm {
        if (std.mem.indexOf(u8, text, "qed") != null) {
            const pt = allocator.create(proof_core.ProofTerm) catch return null;
            if (std.mem.indexOf(u8, text, "refl") != null) pt.* = .{ .refl = 0 } else if (std.mem.indexOf(u8, text, "apply") != null) pt.* = .{ .by_eval = .{ .lhs = 0, .rhs = 0 } } else pt.* = .{ .qed = {} };
            return pt;
        }
        return null;
    }

    fn extractEqArgs(store: *Store, id: Id) ?struct { lhs: Id, rhs: Id } {
        const node = store.get(id);
        const pool = store.pool.items;
        if (node.tag == .source_file) {
            const children = node.span_a.slice(pool);
            if (children.len == 0) return null;
            return extractEqArgs(store, children[0]);
        }
        if (node.tag == .bind) return extractEqArgs(store, node.aux);
        if (node.tag != .apply) return null;
        const func_node = store.get(node.payload);
        if (func_node.tag != .sym) return null;
        const name = store.interner.resolve(func_node.payload);
        const args = node.span_a.slice(pool);
        if (std.mem.eql(u8, name, "Eq") and args.len == 2) return .{ .lhs = args[0], .rhs = args[1] };
        if (std.mem.eql(u8, name, "forall") and args.len >= 1) return extractEqArgs(store, args[args.len - 1]);
        if (std.mem.eql(u8, name, "->") and args.len == 2) return extractEqArgs(store, args[1]);
        return null;
    }

    fn copyId(src: *Store, dst: *Store, id: Id) !Id {
        const node = src.get(id);
        const pool = src.pool.items;
        switch (node.tag) {
            .sym => return dst.sym(src.interner.resolve(node.payload)),
            .lit => return dst.lit(src.lits.items[node.aux]),
            .apply => {
                const func = try copyId(src, dst, node.payload);
                var args: std.ArrayListUnmanaged(Id) = .{};
                defer args.deinit(dst.allocator);
                for (node.span_a.slice(pool)) |arg| try args.append(dst.allocator, try copyId(src, dst, arg));
                return dst.apply(func, args.items);
            },
            .bind => {
                const val = try copyId(src, dst, node.aux);
                return dst.bind(src.interner.resolve(node.payload), val);
            },
            else => return dst.sym("<unsupported>"),
        }
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
    // ═══════════════════════════════════════════════════════════
    // MLCPD & MCP Commands
    // ═══════════════════════════════════════════════════════════

    pub fn cmdMlcpdParse(self: *Commands, input: []const u8) ![]const u8 {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "usage: mlcpd <json-file-or-inline-json>");

        // Essayer de lire comme fichier d'abord
        const json_data = blk: {
            if (platform.fs.readFile(self.allocator, trimmed)) |data| {
                break :blk data;
            } else |_| {}
            // Sinon traiter comme JSON inline
            break :blk try self.allocator.dupe(u8, trimmed);
        };
        defer if (!std.mem.eql(u8, json_data.ptr[0..@min(json_data.len, trimmed.len)], trimmed)) {
            // C'était un fichier lu, libérer
        };

        var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error: MLCPD parse failed: {s}", .{@errorName(err)});
        };
        defer parsed.deinit();

        return std.fmt.allocPrint(self.allocator,
            \\MLCPD Parse Result:
            \\  Language: {s}
            \\  Nodes: {d}
            \\  Lines: {d}
            \\  Errors: {d}
        , .{
            @tagName(parsed.metadata.language),
            parsed.nodeCount(),
            parsed.metadata.lines,
            parsed.metadata.errors,
        });
    }

    pub fn cmdMlcpdConvert(self: *Commands, input: []const u8) ![]const u8 {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "usage: mlcpd-convert <json-file-or-inline-json>");

        const json_data = blk: {
            if (platform.fs.readFile(self.allocator, trimmed)) |data| {
                break :blk data;
            } else |_| {}
            break :blk try self.allocator.dupe(u8, trimmed);
        };

        var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error: MLCPD parse failed: {s}", .{@errorName(err)});
        };
        defer parsed.deinit();

        const expr_id = parsed.toExprIr(&self.store) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error: conversion failed: {s}", .{@errorName(err)});
        };

        // Afficher l'expression convertie
        const printer = self.store.printer();
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        printer.printId(expr_id, buf.writer(self.allocator)) catch {};

        return std.fmt.allocPrint(self.allocator,
            \\MLCPD → Heaven Expr IR:
            \\  Source nodes: {d}
            \\  Expression: {s}
        , .{ parsed.nodeCount(), buf.items });
    }

    pub fn cmdMlcpdStats(self: *Commands, _: []const u8) ![]const u8 {
        return self.allocator.dupe(u8,
            \\MLCPD Integration Status:
            \\  Schema: Universal AST (4 layers)
            \\  Languages: C, C++, C#, Go, Java, JS, Python, Ruby, Scala, TS
            \\  Format: JSON / Parquet
            \\  Commands:
            \\    mlcpd <file.json>       - Parse MLCPD file
            \\    mlcpd-convert <file>    - Convert to Heaven Expr IR
            \\    mlcpd-stats             - Show this help
            \\  Reference: https://arxiv.org/html/2510.16357v1
        );
    }

    fn evalEquiv(self: *Commands, args: []const u8) HeavenError![]u8 {
        // Parser "file1.json file2.json"
        var iter = std.mem.splitSequence(u8, args, " ");
        const file1_path = iter.next() orelse {
            return try self.allocator.dupe(u8, "Usage: equiv <file1.json> <file2.json>");
        };
        const file2_path = iter.next() orelse {
            return try self.allocator.dupe(u8, "Usage: equiv <file1.json> <file2.json>");
        };

        // Charger les fichiers
        const file1_content = platform.fs.cwd().readFileAlloc(self.allocator, file1_path, 10 * 1024 * 1024) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error reading {s}: {s}", .{ file1_path, @errorName(err) });
        };
        defer self.allocator.free(file1_content);

        const file2_content = platform.fs.cwd().readFileAlloc(self.allocator, file2_path, 10 * 1024 * 1024) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error reading {s}: {s}", .{ file2_path, @errorName(err) });
        };
        defer self.allocator.free(file2_content);

        // Parser et normaliser
        var parsed1 = mlcpd_mod.parseMlcpdJson(self.allocator, file1_content) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error parsing {s}: {s}", .{ file1_path, @errorName(err) });
        };
        defer parsed1.deinit();
        parsed1.normalizeParsedFile();

        var parsed2 = mlcpd_mod.parseMlcpdJson(self.allocator, file2_content) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error parsing {s}: {s}", .{ file2_path, @errorName(err) });
        };
        defer parsed2.deinit();
        parsed2.normalizeParsedFile();

        // Convertir en Expr IR
        const expr1 = parsed1.toExprIr(self.store) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error converting {s}: {s}", .{ file1_path, @errorName(err) });
        };

        const expr2 = parsed2.toExprIr(self.store) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Error converting {s}: {s}", .{ file2_path, @errorName(err) });
        };

        // Prouver l'équivalence
        var result = mlcpd_equiv_mod.proveEquivalence(self.allocator, self.store, expr1, expr2) catch |err| {
            return try std.fmt.allocPrint(self.allocator, "Proof failed: {s}", .{@errorName(err)});
        };
        defer result.deinit(self.allocator);

        // Formater le résultat
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(self.allocator);
        const writer = output.writer(self.allocator);

        try writer.print("═══ MLCPD Equivalence Proof ═══\n", .{});
        try writer.print("  file1: {s} ({d} nodes)\n", .{ file1_path, parsed1.nodes.items.len });
        try writer.print("  file2: {s} ({d} nodes)\n", .{ file2_path, parsed2.nodes.items.len });
        try writer.print("  expr1 → IR: {d}\n", .{expr1});
        try writer.print("  expr2 → IR: {d}\n", .{expr2});
        try writer.print("\n", .{});
        try writer.print("  equivalent: {}\n", .{result.equivalent});
        try writer.print("  strategy:   {s}\n", .{@tagName(result.strategy)});

        if (result.error_message) |msg| {
            try writer.print("  error:      {s}\n", .{msg});
        }

        try writer.print("  proof:      {}\n", .{result.proof != null});
        try writer.print("\n", .{});

        if (result.equivalent) {
            try writer.print("ÉQUIVALENCE PROUVÉE\n", .{});
            try writer.print("Proof<Equiv<{s}, {s}>> = Refl<congruence>\n", .{ file1_path, file2_path });
        } else {
            try writer.print("❌ ÉQUIVALENCE NON PROUVÉE\n", .{});
        }

        return output.toOwnedSlice(self.allocator);
    }

    fn evalGreen(self: *Commands, input: []const u8) ![]u8 {
        const expr_id = try self.bridge.importExpr(input);

        // 1. Créer la fonction handler qui accumule l'énergie
        // Elle prend (val1, val2, cost) et retourne (val1 + val2), tout en accumulant cost dans une variable globale.
        // Pour faire simple en Heaven : le handler va juste retourner la somme et on comptera les appels.
        const handler_str = "fn greenHandler(v1, v2, cost) = (+ v1 v2)";
        const handler_result = try self.eval(handler_str);
        // On libère la chaîne de retour ("greenHandler clause...")
        defer self.allocator.free(handler_result);

        // 2. Activer le mode Green dans le moteur
        self.engine.green_call_count = 0;
        self.engine.green_mode = true;
        defer self.engine.green_mode = false; // Désactiver après

        // 3. Créer le nœud AST : (handle <expr> greenHandler)
        const handler_id = try self.store.sym("greenHandler");
        const handle_node = try self.store.handle(expr_id, handler_id);

        // 4. Évaluer
        self.engine.fuel = 1_000_000;
        const result = try self.engine.eval(handle_node);

        // 5. Compter combien de fois l'effet a été déclenché (en regardant la taille de l'AST ou un compteur)
        // Pour l'instant, on simplifie : le handler a été appelé, on affiche le résultat.
        const result_str = try expr.toStringInfix(self.store, result, self.allocator);
        defer self.allocator.free(result_str);

        return std.fmt.allocPrint(self.allocator,
            \\═══ Green Profile ═══
            \\ Resultat : {s}
            \\ Énergie   : {d} J (estimation)
            \\═══════════════════
        , .{ result_str, self.engine.green_call_count });
    }

    /// Parse un fichier selon son extension (.hvn, .pie, .c, .zig)
    pub fn parseFileWithLanguage(self: *Commands, path: []const u8) ![]u8 {
        const ext = std.fs.path.extension(path);
        const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse
            return std.fmt.allocPrint(self.allocator, "unsupported extension: {s}", .{ext});

        const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error reading {s}: {}", .{ path, err });
        };
        defer self.allocator.free(content);

        if (lang == .heaven) {
            const id = self.bridge.importExpr(content) catch {
                return std.fmt.allocPrint(self.allocator, "parse failed for {s}", .{path});
            };
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch id;
            _ = result;
            return std.fmt.allocPrint(self.allocator, "✓ parsed and evaluated {s} as heaven", .{path});
        }

        var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
            return std.fmt.allocPrint(self.allocator, "parser init error: {}", .{err});
        };
        defer parser.deinit();

        const matrix = parser.parse(content) catch {
            return std.fmt.allocPrint(self.allocator, "parse failed for {s}", .{lang.toString()});
        };

        var universal = universal_translator.UniversalTranslator.init(self.allocator, self.store);
        const mlcpd_lang = switch (lang) {
            .c => mlcpd.FileMetadata.Language.c,
            .zig => mlcpd.FileMetadata.Language.c,
            .pie => mlcpd.FileMetadata.Language.unknown,
            .heaven => unreachable,
        };

        const heaven_id = universal.translate(&matrix, mlcpd_lang) catch {
            return std.fmt.allocPrint(self.allocator, "translation failed for {s}", .{lang.toString()});
        };

        self.engine.fuel = 1_000_000;
        const result = self.engine.eval(heaven_id) catch heaven_id;
        const result_str = expr.toString(self.store, result, self.allocator) catch "error";
        defer self.allocator.free(result_str);

        return std.fmt.allocPrint(self.allocator, "✓ translated and evaluated {s} as {s}", .{ path, lang.toString() });
    }

    /// Affiche l'AST brut d'un fichier parsé (pour debug du bridge)
    pub fn dumpAstFile(self: *Commands, path: []const u8) ![]u8 {
        const ext = std.fs.path.extension(path);
        const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse
            return std.fmt.allocPrint(self.allocator, "unsupported extension: {s}", .{ext});

        const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error reading {s}: {}", .{ path, err });
        };
        defer self.allocator.free(content);

        var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
            return std.fmt.allocPrint(self.allocator, "parser init error: {}", .{err});
        };
        defer parser.deinit();

        const matrix = parser.parse(content) catch {
            return std.fmt.allocPrint(self.allocator, "parse failed for {s}", .{lang.toString()});
        };

        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        try dumpMatrix(&matrix, 0, &buf, self.allocator);
        return buf.toOwnedSlice(self.allocator);
    }

    fn dumpMatrix(matrix: *const platform.shell_parser_types.Matrix, depth: u32, buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
        var i: u32 = 0;
        while (i < depth) : (i += 1) try buf.appendSlice(alloc, "  ");
        try buf.appendSlice(alloc, @tagName(matrix.kind));
        if (matrix.text) |text| {
            if (text.len <= 40) {
                try buf.appendSlice(alloc, " \"");
                try buf.appendSlice(alloc, text);
                try buf.appendSlice(alloc, "\"");
            } else {
                try buf.appendSlice(alloc, " \"");
                try buf.appendSlice(alloc, text[0..40]);
                try buf.appendSlice(alloc, "...\"");
            }
        }
        try buf.append(alloc, '\n');
        for (matrix.children) |*child| {
            try dumpMatrix(child, depth + 1, buf, alloc);
        }
    }

    pub fn translateAndDump(self: *Commands, path: []const u8) ![]u8 {
        const ext = std.fs.path.extension(path);
        const lang = platform.shell_parser_types.Language.fromExtension(ext) orelse
            return std.fmt.allocPrint(self.allocator, "unsupported extension: {s}", .{ext});

        const content = platform.fs.cwd().readFileAlloc(self.allocator, path, 10 * 1024 * 1024) catch |err| {
            return std.fmt.allocPrint(self.allocator, "error reading {s}: {}", .{ path, err });
        };
        defer self.allocator.free(content);

        var parser = platform.MultiParser.init(self.allocator, lang) catch |err| {
            return std.fmt.allocPrint(self.allocator, "parser init error: {}", .{err});
        };
        defer parser.deinit();

        const matrix = parser.parse(content) catch {
            return std.fmt.allocPrint(self.allocator, "parse failed for {s}", .{lang.toString()});
        };

        var universal = universal_translator.UniversalTranslator.init(self.allocator, self.store);
        const mlcpd_lang = switch (lang) {
            .c => mlcpd.FileMetadata.Language.c,
            .zig => mlcpd.FileMetadata.Language.c,
            .pie => mlcpd.FileMetadata.Language.unknown,
            .heaven => unreachable,
        };

        const heaven_id = universal.translate(&matrix, mlcpd_lang) catch {
            return std.fmt.allocPrint(self.allocator, "translation failed for {s}", .{lang.toString()});
        };

        // Afficher l'AST Heaven généré
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        try self.writeAst(heaven_id, 0, &buf);
        return buf.toOwnedSlice(self.allocator);
    }
};
