const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const engine_expr = @import("engine_expr");
const codegen_c = @import("codegen_expr_c");
const codegen_js = @import("codegen_expr_js");
const codegen_latex = @import("codegen_expr_latex");
const types_mod = @import("types");
const egraph_mod = @import("egraph");
const lowering_mod = @import("lowering");
const canon_mod = @import("canon");
const proof_lib = @import("proof");
const skill_lib = @import("skill");
const mir = @import("mir");
const x86_64 = @import("x86_64");
const proof_core = @import("proof_core");
const platform = @import("platform");
const transform_mod = @import("transform");
const pattern_mod = @import("pattern");
//const ts = platform.ts;
const agent_mod = @import("agent");
const elab_mod = @import("elab");
const parse_mod = @import("parse");
const commands_mod = @import("commands");
const codegen_wrapper_mod = @import("codegen_wrapper");
const math_mod = @import("math");
const proof_helpers_mod = @import("proof_helpers");
const simplify_engine_mod = @import("simplify_engine");
const mcp_server_mod = @import("mcp_server");

// Import conditionnel : matrix_bridge n'existe pas en WASM
const matrix_bridge_mod = @import("matrix_bridge");

const PROOF_DEBUG = false;

pub const Config = struct {
    use_lowering: bool = false,
};

pub const HeavenError = std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine_expr.EvalError || error{ UnsupportedExpr,
    // Ajoute ici tes autres erreurs spécifiques au shell si tu en as
    UnknownVariable, TypeMismatch, DependentListsNotImplemented, UnsupportedNode, TimerUnsupported, InvalidSyntax, TypeError, ArityMismatch, StackOverflow, NoSpaceLeft, NotSupported, InputOutput, SystemResources, IsDir, OperationAborted, BrokenPipe, ConnectionResetByPeer, ConnectionTimedOut, NotOpenForReading, SocketNotConnected, WouldBlock, Canceled, AccessDenied, ProcessNotFound, LockViolation, Unexpected, FileTooBig, OpenError, NotALambda };

pub const HeavenExpr = struct {
    store: Store,
    engine: engine_expr.Engine,
    bridge: matrix_bridge_mod.MatrixBridge,
    allocator: Allocator,
    parser: parse_mod.Parser,
    kb: transform_mod.KnowledgeBase,
    initialized: bool = false,
    config: Config,
    skills: skill_lib.SkillRegistry,
    active_theorem: ?[]const u8 = null,
    qtt_env: std.StringHashMapUnmanaged(u2),
    proof_core: proof_core.ProofCore,
    agent: agent_mod.Agent,
    pending_proof_request: ?[]const u8 = null,
    cmds: commands_mod.Commands = undefined,
    codegen: codegen_wrapper_mod.CodegenWrapper = undefined,
    math: math_mod.Math = undefined,

    pub fn init(allocator: Allocator) HeavenExpr {
        return .{
            .store = Store.init(allocator),
            .engine = undefined,
            .bridge = undefined,
            .allocator = allocator,
            .parser = undefined, // On initialise ici à undefined car alloué dans ensureInit
            .kb = transform_mod.KnowledgeBase.init(allocator),
            .initialized = false,
            .config = .{ .use_lowering = false },
            .skills = skill_lib.SkillRegistry.init(allocator),
            .qtt_env = .{},
            .proof_core = proof_core.ProofCore.init(allocator),
            .agent = agent_mod.Agent.init(allocator),
        };
    }

    pub fn deinit(self: *HeavenExpr) void {
        self.kb.deinit(self.allocator);
        if (self.initialized) {
            self.bridge.deinit();
            self.engine.deinit();
            self.cmds.deinit();
        }
        self.store.deinit();
        self.skills.deinit();
        self.qtt_env.deinit(self.allocator);
        self.proof_core.deinit();

        if (self.active_theorem) |t| self.allocator.free(t);
        if (self.pending_proof_request) |r| self.allocator.free(r);
    }

    pub fn ensureInit(self: *HeavenExpr) void {
        if (!self.initialized) {
            self.engine = engine_expr.Engine.init(&self.store, self.allocator);
            self.bridge = matrix_bridge_mod.MatrixBridge.init(&self.store, self.allocator);
            self.parser = parse_mod.Parser.init(&self.store, &self.engine, self.allocator);
            self.kb = transform_mod.KnowledgeBase.init(self.allocator);
            self.skills = skill_lib.SkillRegistry.init(self.allocator);
            self.proof_core = proof_core.ProofCore.init(self.allocator);
            self.agent = agent_mod.Agent.init(self.allocator);
            self.qtt_env = std.StringHashMapUnmanaged(u2){};
            self.math = math_mod.Math.init(&self.store, &self.engine, &self.bridge, &self.parser, self.allocator);
            self.codegen = codegen_wrapper_mod.CodegenWrapper.init(&self.store, self.allocator);
            self.cmds = commands_mod.Commands.init(
                &self.store,
                &self.engine,
                &self.bridge,
                self.allocator,
                &self.parser,
                &self.math,
                &self.kb,
                &self.skills,
                &self.qtt_env,
                &self.proof_core,
                &self.agent,
                &self.active_theorem,
                &self.pending_proof_request,
            ) catch |err| {
                platform.debug.print("[FATAL] Failed to initialize Commands: {}\n", .{err});
                @panic("HeavenExpr initialization failed");
            };
            self.initialized = true;
            // Pre-allocate pool to avoid reallocation crashes
            self.store.pool.ensureTotalCapacity(self.allocator, 4096) catch {};
            // Builtin rewrite rules
            const builtins = [_][2][]const u8{
                .{ "x + 0", "x" },
                .{ "0 + x", "x" },
                .{ "x * 1", "x" },
                .{ "1 * x", "x" },
                .{ "x * 0", "0" },
                .{ "0 * x", "0" },
                .{ "x - 0", "x" },
                .{ "x - x", "0" },
                .{ "x / 1", "x" },
                .{ "x / x", "1" },
                .{ "x + x", "2 * x" },
                .{ "0 - (0 - x)", "x" },
                .{ "x * x", "x ^ 2" },
                .{ "x ^ 1", "x" },
                .{ "x ^ 0", "1" },
                .{ "0 ^ x", "0" },
                .{ "1 ^ x", "1" },
                // Règles pour Nat (add, mul, zero, succ)
                .{ "add(zero, n)", "n" },
                .{ "add(succ(n), m)", "succ(add(n, m))" },
                .{ "mul(zero, n)", "zero" },
                .{ "mul(succ(n), m)", "add(m, mul(n, m))" },
            };
            for (builtins) |rule| {
                const rewrite = self.addRewrite(rule[0], rule[1]) catch continue;
                self.allocator.free(rewrite);
            }

            // Charger bootstrap.hvn dans le FunctionRegistry
            self.loadBootstrap();
        }
    }

    fn applyLowering(self: *HeavenExpr, id: Id) !Id {
        var lowering = lowering_mod.Lowering.init(self.allocator, &self.bridge);
        return lowering.lowerSource(id);
    }
    // ─── Eval ───

    pub fn eval(self: *HeavenExpr, input: []const u8) HeavenError![]u8 {
        self.ensureInit();
        return self.cmds.eval(input);
    }

    /// Legacy eval kept for reference
    fn evalHelp(self: *HeavenExpr) ![]u8 {
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
            "  profile <expr>         — profiler temps, mémoire, Big O, énergie\n" ++
            "  trace <expr>           — tracer l'évaluation\n" ++
            "  let <var> = <expr>\n");
    }

    fn evalStats(self: *HeavenExpr) ![]u8 {
        return try self.allocator.dupe(u8, "═══ Heaven WASM ═══\n" ++
            "Engine: active\n" ++
            "Features: eval, type, simplify, explain, latex, quote, prove");
    }

    fn evalSimplify(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.simplify(input);
    }

    fn evalType(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.typeOf(input);
    }

    fn evalDerive(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.math.derive(input, "x");
    }

    fn evalSolve(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.math.solve(input, "x");
    }

    fn evalIntegrate(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.math.integrate(input, "x");
    }

    fn evalExpand(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.math.expand(input);
    }

    fn evalLatex(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const id = try self.bridge.importExpr(input);
        const latex = try self.codegen.toLaTeXInline(id);
        const result = try std.fmt.allocPrint(self.allocator, "latex|{s}", .{latex});
        return result;
    }

    fn evalExplain(self: *HeavenExpr, input: []const u8) ![]u8 {
        return try self.explain(input);
    }

    fn evalPlot(self: *HeavenExpr, input: []const u8) ![]u8 {
        const expr_str = std.mem.trim(u8, input, " ");
        const result = try std.fmt.allocPrint(self.allocator, "plot|{s}", .{expr_str});
        return result;
    }

    fn evalQtt(self: *HeavenExpr, input: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        defer result.deinit(self.allocator);
        var tokens = std.mem.tokenizeScalar(u8, input, ',');
        while (tokens.next()) |token| {
            const trimmed = std.mem.trim(u8, token, " ");
            if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
                const name = std.mem.trim(u8, trimmed[0..colon], " ");
                const qty_str = std.mem.trim(u8, trimmed[colon + 1 ..], " ");
                const qty = if (std.mem.eql(u8, qty_str, "0") or std.mem.eql(u8, qty_str, "zero")) @as(u2, 0) else if (std.mem.eql(u8, qty_str, "1") or std.mem.eql(u8, qty_str, "one")) @as(u2, 1) else @as(u2, 2); // ω par défaut
                const sym = try self.store.interner.intern(name);
                _ = sym;
                try self.qtt_env.put(self.allocator, name, qty);
                try result.writer(self.allocator).print("qtt: {s} -> {d}\n", .{ name, qty });
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn evalProfile(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const id = try self.bridge.importExpr(input);

        if (comptime !@import("builtin").target.cpu.arch.isWasm()) {
            var timer = try std.time.Timer.start();
            const start_time = timer.read();
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "Profile error: {s}", .{@errorName(err)});
            };
            const result_str = try expr.toStringInfix(&self.store, result, self.allocator);
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
            // Version WASM légère (pas de temps, pas d'énergie)
            self.engine.fuel = 1_000_000;
            const result = self.engine.eval(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "Profile error: {s}", .{@errorName(err)});
            };
            const result_str = try expr.toStringInfix(&self.store, result, self.allocator);
            const node_count = self.countNodes(result);
            var buf: std.ArrayListUnmanaged(u8) = .{};
            defer buf.deinit(self.allocator);
            const w = buf.writer(self.allocator);
            try w.print("═══ Profile (WASM) ═══\n Expression : {s}\n Nœuds : {d}\n═══════════════\n", .{ result_str, node_count });
            return buf.toOwnedSlice(self.allocator);
        }
    }

    pub fn evalTrace(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        const id = try self.bridge.importExpr(input);
        const initial = try expr.toStringInfix(&self.store, id, self.allocator);
        defer self.allocator.free(initial);
        try w.print("trace: {s}\n", .{initial});

        // Étape 1 : simplifyRec
        var current = try self.cmds.simplify_eng.simplifyRec(id, 0);
        const after_rec = try expr.toStringInfix(&self.store, current, self.allocator);
        defer self.allocator.free(after_rec);
        if (!std.mem.eql(u8, initial, after_rec))
            try w.print("  → [rewrite] {s}\n", .{after_rec});

        // Étape 2 : E-graph saturation
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        const after_egraph = try self.cmds.simplify_eng.simplifyWithEGraph(current, &qtt);
        const after_egraph_str = try expr.toStringInfix(&self.store, after_egraph, self.allocator);
        defer self.allocator.free(after_egraph_str);
        if (!std.mem.eql(u8, after_rec, after_egraph_str))
            try w.print("  → [egraph] {s}\n", .{after_egraph_str});
        current = after_egraph;

        // Étape 3 : canon AC
        const canon = try canon_mod.canonicalize(&self.store, self.allocator, current);
        const canon_str = try expr.toStringInfix(&self.store, canon, self.allocator);
        defer self.allocator.free(canon_str);
        if (!std.mem.eql(u8, after_egraph_str, canon_str))
            try w.print("  → [canon] {s}\n", .{canon_str});

        // Coût final
        const node_count = self.countNodes(canon);
        try w.print("  cost: {d} nodes\n", .{node_count});

        return buf.toOwnedSlice(self.allocator);
    }

    fn countNodes(self: *HeavenExpr, id: Id) usize {
        if (id >= self.store.len()) return 0;
        const node = self.store.get(id);
        var count: usize = 1;
        switch (node.tag) {
            .apply => {
                count += self.countNodes(node.payload);
                for (node.span_a.slice(self.store.pool.items)) |child| {
                    count += self.countNodes(child);
                }
            },
            .bind => count += self.countNodes(node.aux),
            else => {},
        }
        return count;
    }

    // ─── Define ───

    pub fn define(self: *HeavenExpr, name: []const u8, value_text: []const u8) ![]u8 {
        self.ensureInit();
        const val_id = try self.bridge.importExpr(value_text);
        self.engine.fuel = 10_000;
        const evaled = self.engine.eval(val_id) catch val_id;
        const bind_id = try self.store.bind(name, evaled);
        try self.engine.env.put(try self.store.interner.intern(name), evaled);
        return expr.toString(&self.store, bind_id, self.allocator);
    }

    fn tryFnCall(self: *HeavenExpr, input: []const u8) ?[]u8 {
        self.ensureInit();
        if (input.len == 0 or input[0] == '(' or std.ascii.isDigit(input[0])) return null;

        // Cas 1: name(args) - parenthèse juste après le nom (SANS espace avant)
        if (std.mem.indexOfScalar(u8, input, '(')) |paren_idx| {
            const before_paren = input[0..paren_idx];
            // Si pas d'espace avant la parenthèse, c'est un appel name(args)
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
                    eval_args[i] = self.bridge.importExpr(args_list[i]) catch return null;
                }

                self.engine.fuel = 1000_000;
                for (0..num_args) |i| {
                    const s =
                        expr.toString(&self.store, eval_args[i], self.allocator) catch "ERR";

                    platform.debug.print("ARG[{d}]={s}\n", .{ i, s });
                }
                const result = self.engine.evalFunction(potential_name, eval_args[0..num_args]) catch return null;
                return expr.toString(&self.store, result, self.allocator) catch return null;
            }
        }

        // Cas 2: name arg1 arg2 ... (espace après le nom)
        const space_idx = std.mem.indexOfScalar(u8, input, ' ') orelse return null;
        const name = input[0..space_idx];

        if (self.engine.fns.functions.getEntry(name) == null) return null;

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
            eval_args[i] = self.bridge.importExpr(args_list[i]) catch return null;
        }

        self.engine.fuel = 1000_000;
        const result = self.engine.evalFunction(name, eval_args[0..num_args]) catch return null;
        return expr.toString(&self.store, result, self.allocator) catch return null;
    }

    fn evalFnDef(self: *HeavenExpr, input: []const u8) ![]u8 {
        return self.cmds.evalFnDef(input);
    }

    fn evalFnDefo(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const eq_pos = std.mem.indexOfScalar(u8, input, '=') orelse {
            return self.allocator.dupe(u8, "syntax error: missing '='");
        };

        // Check it's not ==
        if (eq_pos + 1 < input.len and input[eq_pos + 1] == '=') {
            return self.allocator.dupe(u8, "syntax error: use single '='");
        }

        const lhs = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

        // Parser le nom de la fonction et les patterns en respectant les parenthèses
        var pat_strs: [8][]const u8 = undefined;
        var num_pats: usize = 0;
        var depth: i32 = 0;
        var start: usize = 0;
        var name_found = false;
        var name: []const u8 = "";

        var i: usize = 0;
        while (i < lhs.len) : (i += 1) {
            const ch = lhs[i];
            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                ' ', '\t' => {
                    if (depth == 0 and i > start) {
                        const token = std.mem.trim(u8, lhs[start..i], " \t");
                        if (!name_found) {
                            name = token;
                            name_found = true;
                        } else if (num_pats < 8) {
                            pat_strs[num_pats] = token;
                            num_pats += 1;
                        }
                        start = i + 1;
                    }
                },
                else => {},
            }
        }
        // Dernier token
        if (start < lhs.len) {
            const token = std.mem.trim(u8, lhs[start..], " \t");
            if (!name_found) {
                name = token;
            } else if (num_pats < 8) {
                pat_strs[num_pats] = token;
                num_pats += 1;
            }
        }

        if (!name_found or name.len == 0) {
            return self.allocator.dupe(u8, "syntax error: missing function name");
        }

        // Parser chaque pattern comme une expression
        // Transformer "f x y" ou "(f x y)" en "f(x,y)" pour que importExpr crée un .apply
        var pat_ids: [8]u32 = undefined;
        for (0..num_pats) |pi| {
            const raw = pat_strs[pi];

            var transformed: [256]u8 = undefined;
            var tlen: usize = 0;

            // Étape 1: Retirer les parenthèses externes si présentes
            const raw_inner = if (raw.len >= 2 and raw[0] == '(' and raw[raw.len - 1] == ')')
                std.mem.trim(u8, raw[1 .. raw.len - 1], " \t")
            else
                raw;

            // Étape 2: Découper en tokens respectant les parenthèses imbriquées
            var parts: [8][]const u8 = undefined;
            var nparts: usize = 0;
            var depth2: i32 = 0;
            var pstart: usize = 0;

            for (raw_inner, 0..) |ch, idx| {
                switch (ch) {
                    '(' => depth2 += 1,
                    ')' => depth2 -= 1,
                    ' ', '\t' => {
                        if (depth2 == 0 and idx > pstart) {
                            if (nparts < 8) {
                                parts[nparts] = std.mem.trim(u8, raw_inner[pstart..idx], " \t");
                                nparts += 1;
                            }
                            pstart = idx + 1;
                        }
                    },
                    else => {},
                }
            }
            // Dernier token
            if (pstart < raw_inner.len and nparts < 8) {
                parts[nparts] = std.mem.trim(u8, raw_inner[pstart..], " \t");
                nparts += 1;
            }

            // Étape 3: Reconstruire
            if (nparts > 1) {
                // Pattern composé: "succ n" → "succ(n)"
                const fname = parts[0];
                @memcpy(transformed[0..fname.len], fname);
                tlen = fname.len;
                transformed[tlen] = '(';
                tlen += 1;
                for (1..nparts) |j| {
                    if (j > 1) {
                        transformed[tlen] = ',';
                        tlen += 1;
                    }
                    const part = parts[j];
                    @memcpy(transformed[tlen .. tlen + part.len], part);
                    tlen += part.len;
                }
                transformed[tlen] = ')';
                tlen += 1;

                pat_ids[pi] = self.bridge.importExpr(raw) catch {
                    return self.allocator.dupe(u8, "parse error in pattern");
                };
            } else if (nparts == 1) {
                // Pattern simple (un seul token)
                pat_ids[pi] = self.bridge.importExpr(parts[0]) catch {
                    return self.allocator.dupe(u8, "parse error in pattern");
                };
            } else {
                return self.allocator.dupe(u8, "empty pattern");
            }
        }

        // Transformer le corps récursivement
        const body_id = self.bridge.importExpr(rhs) catch {
            return self.allocator.dupe(u8, "parse error in body");
        };

        self.engine.fns.register(self.allocator.dupe(u8, name) catch name, pat_ids[0..num_pats], body_id) catch {
            return self.allocator.dupe(u8, "registration error");
        };

        // Ajouter le symbole dans l'environnement (commun aux deux cas)
        const sym = self.store.interner.intern(name) catch {
            return self.allocator.dupe(u8, "intern error");
        };
        self.engine.env.put(sym, body_id) catch {};

        if (num_pats == 0) {
            return std.fmt.allocPrint(self.allocator, "{s} defined", .{name});
        } else {
            return std.fmt.allocPrint(self.allocator, "{s} clause ({d} patterns) registered", .{ name, num_pats });
        }
    }

    // ─── Logic ───

    pub fn assertFact(self: *HeavenExpr, pred: []const u8, args: []const []const u8) ![]u8 {
        self.ensureInit();
        const id = try self.bridge.importFact(pred, args);
        try self.kb.rules.append(self.allocator, id);
        return expr.toStringInfix(&self.store, id, self.allocator);
    }

    pub fn query(self: *HeavenExpr, pred: []const u8, num_holes: u32) ![][]u8 {
        self.ensureInit();
        var arg_ids: std.ArrayListUnmanaged(Id) = .{};
        defer arg_ids.deinit(self.allocator);
        for (0..num_holes) |i| {
            try arg_ids.append(self.allocator, try self.store.hole(@intCast(i)));
        }
        const pattern = try self.store.relation(pred, arg_ids.items, &.{});
        const pat_node = self.store.get(pattern);

        var output: std.ArrayListUnmanaged([]u8) = .{};
        for (self.kb.rules.items) |fact_id| {
            const fact = self.store.get(fact_id);
            if (fact.tag != .relation) continue;
            if (fact.payload != pat_node.payload) continue;
            const pat_args = pat_node.span_a.slice(self.store.pool.items);
            const fact_args = fact.span_a.slice(self.store.pool.items);
            if (pat_args.len != fact_args.len) continue;
            for (pat_args, fact_args) |pa, fa| {
                const pn = self.store.get(pa);
                if (pn.tag == .hole) {
                    const s = try expr.toString(&self.store, fa, self.allocator);
                    try output.append(self.allocator, s);
                }
            }
        }
        return output.toOwnedSlice(self.allocator);
    }

    // ─── Types ───
    pub fn typeOf(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const trimmed = std.mem.trim(u8, input, " \t");

        // Si ça commence par '(', on utilise le parseur S-expr (plus robuste)
        const id = if (trimmed.len > 0 and trimmed[0] == '(')
            try self.parser.parseSExpr(trimmed)
        else
            try self.bridge.importExpr(trimmed);

        var inf = types_mod.Infer.init(&self.store, self.allocator);
        defer inf.deinit();
        const t = try inf.typeOf(id);
        return types_mod.Infer.typeStr(&inf.subst, t, self.allocator);
    }

    // ─── Simplify ───

    pub fn simplify(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        var current = try self.bridge.importExpr(input);

        // Phase 1 : réécriture récursive existante
        current = try self.cmds.simplify_eng.simplifyRec(current, 0);

        // Phase 2 : saturation E-graph avec les règles de la KB
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);
        // Charger les multiplicités depuis l'environnement
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }
        current = try self.cmds.simplify_eng.simplifyWithEGraph(current, &qtt);

        // Phase 3 : canonicalisation AC
        if (true) {
            current = try canon_mod.canonicalize(&self.store, self.allocator, current);
        }

        return expr.toStringInfix(&self.store, current, self.allocator);
    }

    // ─── Rewrite rules ───

    pub fn addRewrite(self: *HeavenExpr, lhs_text: []const u8, rhs_text: []const u8) ![]u8 {
        self.ensureInit();
        const lhs_id = try self.bridge.importExpr(lhs_text);
        const rhs_id = try self.bridge.importExpr(rhs_text);
        const rule_id = try self.store.relation("\xE2\x87\x92", &.{ lhs_id, rhs_id }, &.{});
        try self.kb.rules.append(self.allocator, rule_id);

        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "rule: ");
        const ls = try expr.toString(&self.store, lhs_id, self.allocator);
        defer self.allocator.free(ls);
        try buf.appendSlice(self.allocator, ls);
        try buf.appendSlice(self.allocator, " \xE2\x87\x92 ");
        const rs = try expr.toString(&self.store, rhs_id, self.allocator);
        defer self.allocator.free(rs);
        try buf.appendSlice(self.allocator, rs);
        return buf.toOwnedSlice(self.allocator);
    }

    // ─── Dump ───

    pub fn dump(self: *HeavenExpr) ![]u8 {
        self.ensureInit();
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        const n = self.store.len();
        for (0..n) |i| {
            const node = self.store.get(@intCast(i));
            if (node.tag == .bind or node.tag == .relation) {
                const s = try expr.toString(&self.store, @intCast(i), self.allocator);
                defer self.allocator.free(s);
                try buf.appendSlice(self.allocator, s);
                try buf.append(self.allocator, '\n');
            }
        }
        if (buf.items.len == 0) {
            try buf.appendSlice(self.allocator, "(vide)\n");
        }
        return buf.toOwnedSlice(self.allocator);
    }

    // ─── Codegen ───

    pub fn toLaTeX(self: *HeavenExpr, ids: []const Id) ![]u8 {
        var gen = codegen_latex.LaTeX.init(&self.store, self.allocator);
        defer gen.deinit();
        return gen.generate(ids);
    }

    fn evalOptimize(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const id = try self.bridge.importExpr(input);
        var qtt = egraph_mod.QttCost{};
        defer qtt.deinit(self.allocator);

        // Remplir les multiplicités pour les symboles connus
        var it = self.qtt_env.iterator();
        while (it.next()) |entry| {
            const sym = try self.store.interner.intern(entry.key_ptr.*);
            const sym_id = try self.store.symId(sym);
            try qtt.quantities.put(self.allocator, sym_id, entry.value_ptr.*);
        }

        const optimized = try self.cmds.simplify_eng.simplifyWithEGraph(id, &qtt);
        return expr.toString(&self.store, optimized, self.allocator);
    }

    fn evalAsm(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const id = try self.bridge.importExpr(input);
        var mir_func = mir.MirFunction.init(self.allocator);
        defer mir_func.deinit();
        const entry_block = try mir_func.newBlock();
        var locals = std.AutoHashMap(u32, mir.ValueId).init(self.allocator);
        defer locals.deinit();
        _ = try mir_func.compileExpr(&self.store, id, entry_block, locals);
        mir_func.blocks.items[entry_block].terminator = .{ .ret = 0 }; // valeur factice
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        try x86_64.emitFromFunction(&mir_func, buf.writer(self.allocator));
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn evalSExpr(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "()");
        if (trimmed[0] == '(') {
            const id = try self.parser.parseSExpr(trimmed);
            const result = self.engine.eval(id) catch id;
            return expr.toString(&self.store, result, self.allocator);
        }
        return self.eval(trimmed);
    }

    // Cherche un mot-clé à la racine (profondeur parenthèses = 0)
    fn findKeywordAtRoot(text: []const u8, kw: []const u8) ?usize {
        return parse_mod.Parser.findKeywordAtRoot(text, kw);
    }

    /// Ancienne implémentation conservée comme référence (non utilisée)
    pub fn substExpr(self: *HeavenExpr, input: []const u8, varname: []const u8, value: []const u8) ![]u8 {
        self.ensureInit();
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

    pub fn listRules(self: *HeavenExpr) ![]u8 {
        self.ensureInit();
        var buf = std.ArrayListUnmanaged(u8){};
        const w = buf.writer(self.allocator);
        try w.writeAll("  KB rules as data:\n");
        for (self.kb.rules.items, 0..) |rule_id, idx| {
            if (rule_id >= self.store.len()) continue;
            const s = expr.toString(&self.store, rule_id, self.allocator) catch continue;
            defer self.allocator.free(s);
            try std.fmt.format(w, "  [{d}] {s}\n", .{ idx, s });
        }
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn dumpAst(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();

        // 1. Convertir la string en slice C (si nécessaire)
        //const input_len = @as(u32, @intCast(input.len));

        // 2. Appeler l'API C correctement
        // ts_parser_parse_string prend : (parser, old_tree, string, length)
        //const tree = ts.ts_parser_parse_string(self.parser, null, input.ptr, input_len);

        // 3. Récupérer la root node
        //const ast_root = ts.ts_tree_root_node(tree);

        //var lowering = lowering_mod.Lowering.init(self.allocator, &self.bridge,);

        // 1. D'abord, tu dois traduire ton TSNode en BobId via ton pont
        //const node_id = try self.bridge.tsNodeToBobId(ast_root);

        // 2. Ensuite, tu appelles ton lowering sur ton identifiant interne
        //const id = try lowering.lowerSource(node_id);

        const id = try self.bridge.importExpr(input);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        try self.writeAst(id, 0, &buf);
        return buf.toOwnedSlice(self.allocator);
    }

    fn writeAst(self: *HeavenExpr, id: Id, depth: u32, buf: *std.ArrayListUnmanaged(u8)) !void {
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
                for (node.span_a.slice(self.store.pool.items)) |child| {
                    try self.writeAst(child, depth + 1, buf);
                }
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

    pub fn explain(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        var current = try self.bridge.importExpr(input);
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);

        const s0 = try expr.toString(&self.store, current, self.allocator);
        defer self.allocator.free(s0);
        try buf.appendSlice(self.allocator, "  step 0: ");
        try buf.appendSlice(self.allocator, s0);
        try buf.append(self.allocator, '\n');

        var step: u32 = 1;
        while (step < 20) {
            const prev = current;
            current = try self.cmds.simplify_eng.simplifyOnePass(current, &buf, &step);
            if (current == prev) break;
        }

        const final_str = try expr.toString(&self.store, current, self.allocator);
        defer self.allocator.free(final_str);
        try buf.appendSlice(self.allocator, "  \xe2\x88\xb4 ");
        try buf.appendSlice(self.allocator, s0);
        try buf.appendSlice(self.allocator, " = ");
        try buf.appendSlice(self.allocator, final_str);
        var tmp: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&tmp, "  ({d} rewrites)\n", .{step - 1}) catch "?\n";
        try buf.appendSlice(self.allocator, count_str);
        return buf.toOwnedSlice(self.allocator);
    }

    pub fn describeKB(self: *HeavenExpr) ![]u8 {
        self.ensureInit();
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(self.allocator);
        var tmp: [64]u8 = undefined;
        const n_str = std.fmt.bufPrint(&tmp, " {d} rewrite rules\n", .{self.kb.rules.items.len}) catch "?\n";
        try buf.appendSlice(self.allocator, n_str);
        for (self.kb.rules.items) |rule_id| {
            if (rule_id >= self.store.len()) continue;
            const s = try expr.toString(&self.store, rule_id, self.allocator);
            defer self.allocator.free(s);
            try buf.appendSlice(self.allocator, " ");
            try buf.appendSlice(self.allocator, s);
            try buf.append(self.allocator, '\n');
        }
        return buf.toOwnedSlice(self.allocator);
    }

    fn normalizeUnicode(self: *HeavenExpr, input: []const u8) ![]u8 {
        var buf = try self.allocator.alloc(u8, input.len * 2);
        var pos: usize = 0;
        var i: usize = 0;
        while (i < input.len and pos < buf.len - 4) {
            if (i + 1 < input.len and input[i] == 0xc2) {
                const c2 = input[i + 1];
                if (c2 == 0xb2) {
                    buf[pos] = '^';
                    buf[pos + 1] = '2';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb3) {
                    buf[pos] = '^';
                    buf[pos + 1] = '3';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb9) {
                    buf[pos] = '^';
                    buf[pos + 1] = '1';
                    pos += 2;
                    i += 2;
                    continue;
                }
                if (c2 == 0xb0) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0';
                    pos += 2;
                    i += 2;
                    continue;
                }
            }
            if (i + 2 < input.len and input[i] == 0xe2 and input[i + 1] == 0x81) {
                const c3 = input[i + 2];
                if (c3 == 0xb0) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0';
                    pos += 2;
                    i += 3;
                    continue;
                }
                if (c3 >= 0xb4 and c3 <= 0xb9) {
                    buf[pos] = '^';
                    buf[pos + 1] = '0' + (c3 - 0xb0);
                    pos += 2;
                    i += 3;
                    continue;
                }
            }
            buf[pos] = input[i];
            pos += 1;
            i += 1;
        }
        return self.allocator.realloc(buf, pos);
    }

    fn deriveStr(self: *HeavenExpr, input: []const u8, v: []const u8) ![]u8 {
        const trimmed = std.mem.trim(u8, input, " ");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "0");

        // Constante numérique
        if (std.fmt.parseInt(i64, trimmed, 10)) |_| {
            return self.allocator.dupe(u8, "0");
        } else |_| {}

        // Variable ou symbole simple
        var all_alpha = true;
        for (trimmed) |ch| {
            if (!std.ascii.isAlphabetic(ch) and ch != '_') {
                all_alpha = false;
                break;
            }
        }
        if (all_alpha and trimmed.len > 0) {
            if (std.mem.eql(u8, trimmed, v)) return self.allocator.dupe(u8, "1");
            return self.allocator.dupe(u8, "0");
        }

        // Parenthèses
        if (trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
            return self.math.deriveStr(trimmed[1 .. trimmed.len - 1], v);
        }

        // Trouver opérateur principal
        var depth: i32 = 0;
        var last_add: ?usize = null;
        var last_add_op: u8 = '+';
        var last_mul: ?usize = null;
        var last_div: ?usize = null;
        var last_pow: ?usize = null;

        for (trimmed, 0..) |ch, idx| {
            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                '+' => if (depth == 0 and idx > 0) {
                    last_add = idx;
                    last_add_op = '+';
                },
                '-' => if (depth == 0 and idx > 0 and trimmed[idx - 1] != '(' and trimmed[idx - 1] != ',') {
                    last_add = idx;
                    last_add_op = '-';
                },
                '*' => if (depth == 0 and idx > 0) {
                    last_mul = idx;
                },
                '/' => if (depth == 0 and idx > 0) {
                    last_div = idx;
                },
                '^' => if (depth == 0 and idx > 0) {
                    last_pow = idx;
                },
                else => {},
            }
        }

        // + ou -
        if (last_add) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.math.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.math.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            // Simplification inline
            if (std.mem.eql(u8, dl, "0") and std.mem.eql(u8, dr, "0")) return self.allocator.dupe(u8, "0");
            if (std.mem.eql(u8, dl, "0")) {
                if (last_add_op == '-') return std.fmt.allocPrint(self.allocator, "0 - {s}", .{dr});
                return self.allocator.dupe(u8, dr);
            }
            if (std.mem.eql(u8, dr, "0")) return self.allocator.dupe(u8, dl);
            return std.fmt.allocPrint(self.allocator, "{s} {c} {s}", .{ dl, last_add_op, dr });
        }

        // *
        if (last_mul) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.math.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.math.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            const dl_zero = std.mem.eql(u8, dl, "0");
            const dr_zero = std.mem.eql(u8, dr, "0");
            const dl_one = std.mem.eql(u8, dl, "1");
            const dr_one = std.mem.eql(u8, dr, "1");
            // f'g + fg'
            if (dl_zero and dr_zero) return self.allocator.dupe(u8, "0");
            if (dl_zero) {
                // 0*g + f*g' = f*g'
                if (dr_one) return self.allocator.dupe(u8, lhs);
                return std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ lhs, dr });
            }
            if (dr_zero) {
                // f'*g + f*0 = f'*g
                if (dl_one) return self.allocator.dupe(u8, rhs);
                return std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ dl, rhs });
            }
            // Both nonzero
            var left: []u8 = undefined;
            if (dl_one) {
                left = try self.allocator.dupe(u8, rhs);
            } else {
                left = try std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ dl, rhs });
            }
            defer self.allocator.free(left);
            var right: []u8 = undefined;
            if (dr_one) {
                right = try self.allocator.dupe(u8, lhs);
            } else {
                right = try std.fmt.allocPrint(self.allocator, "{s} * {s}", .{ lhs, dr });
            }
            defer self.allocator.free(right);
            return std.fmt.allocPrint(self.allocator, "{s} + {s}", .{ left, right });
        }

        // /
        if (last_div) |idx| {
            const lhs = std.mem.trim(u8, trimmed[0..idx], " ");
            const rhs = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            const dl = try self.math.deriveStr(lhs, v);
            defer self.allocator.free(dl);
            const dr = try self.math.deriveStr(rhs, v);
            defer self.allocator.free(dr);
            if (std.mem.eql(u8, dr, "0")) {
                // Denominator is constant
                if (std.mem.eql(u8, dl, "0")) return self.allocator.dupe(u8, "0");
                return std.fmt.allocPrint(self.allocator, "({s}) / {s}", .{ dl, rhs });
            }
            return std.fmt.allocPrint(self.allocator, "(({s}) * {s} - ({s}) * ({s})) / ({s}) ^ 2", .{ dl, rhs, lhs, dr, rhs });
        }

        // ^
        if (last_pow) |idx| {
            const base = std.mem.trim(u8, trimmed[0..idx], " ");
            const exp_str = std.mem.trim(u8, trimmed[idx + 1 ..], " ");
            if (std.fmt.parseInt(i64, exp_str, 10)) |n| {
                if (std.mem.eql(u8, base, v)) {
                    if (n == 2) return std.fmt.allocPrint(self.allocator, "{d} * {s}", .{ n, base });
                    return std.fmt.allocPrint(self.allocator, "{d} * {s} ^ {d}", .{ n, base, n - 1 });
                }
            } else |_| {}
            return self.allocator.dupe(u8, "0");
        }

        return self.allocator.dupe(u8, "0");
    }

    // ─── Integrate ───

    fn integrateExpr(self: *HeavenExpr, id: Id, v: []const u8) !Id {
        if (id >= self.store.len()) return self.store.int(0);
        const node = self.store.get(id);
        switch (node.tag) {
            .lit => {
                // ∫c dx = c*x
                return self.store.binop("*", id, try self.store.sym(v));
            },
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, v)) {
                    // ∫x dx = x^2/2
                    const x2 = try self.store.binop("^", id, try self.store.int(2));
                    return self.store.binop("/", x2, try self.store.int(2));
                }
                // ∫c dx = c*x (c is another variable, treated as constant)
                return self.store.binop("*", id, try self.store.sym(v));
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag != .sym) return self.store.int(0);
                const op = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);
                if (args.len != 2) return self.store.int(0);
                const a0 = args[0];
                const a1 = args[1];

                // ∫(f+g) = ∫f + ∫g
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
                    const left = try self.math.integrateExpr(a0, v);
                    const right = try self.math.integrateExpr(a1, v);
                    return self.store.binop(op, left, right);
                }
                // ∫k*f = k*∫f
                if (std.mem.eql(u8, op, "*")) {
                    const n0 = self.store.get(a0);
                    const n1 = self.store.get(a1);
                    if (n0.tag == .lit) {
                        const inner = try self.math.integrateExpr(a1, v);
                        return self.store.binop("*", a0, inner);
                    }
                    if (n1.tag == .lit) {
                        const inner = try self.math.integrateExpr(a0, v);
                        return self.store.binop("*", a1, inner);
                    }
                    // k*x where k is constant sym
                    if (n0.tag == .sym and n1.tag == .sym) {
                        const name1 = self.store.interner.resolve(n1.payload);
                        if (std.mem.eql(u8, name1, v)) {
                            // ∫a*x dx = a*x^2/2
                            const x2 = try self.store.binop("^", a1, try self.store.int(2));
                            const half = try self.store.binop("/", x2, try self.store.int(2));
                            return self.store.binop("*", a0, half);
                        }
                        const name0 = self.store.interner.resolve(n0.payload);
                        if (std.mem.eql(u8, name0, v)) {
                            const x2 = try self.store.binop("^", a0, try self.store.int(2));
                            const half = try self.store.binop("/", x2, try self.store.int(2));
                            return self.store.binop("*", a1, half);
                        }
                    }
                    return self.store.int(0);
                }
                // ∫x^n dx = x^(n+1)/(n+1)
                if (std.mem.eql(u8, op, "^")) {
                    const base = self.store.get(a0);
                    const exp_node = self.store.get(a1);
                    if (base.tag == .sym and exp_node.tag == .lit) {
                        const name = self.store.interner.resolve(base.payload);
                        if (std.mem.eql(u8, name, v)) {
                            const e = self.store.lits.items[exp_node.aux];
                            switch (e) {
                                .int => |n| {
                                    if (n == -1) {
                                        // ∫1/x = ln(x) — return symbol
                                        return self.store.sym("ln(x)");
                                    }
                                    const np1 = try self.store.int(n + 1);
                                    const power = try self.store.binop("^", a0, np1);
                                    return self.store.binop("/", power, np1);
                                },
                                else => {},
                            }
                        }
                    }
                }
                return self.store.int(0);
            },
            else => return self.store.int(0),
        }
    }
    // ─── Solve ───

    fn collectCoeffs(self: *HeavenExpr, id: Id, v: []const u8, a: *i64, b: *i64, c: *i64) void {
        if (id >= self.store.len()) return;
        const node = self.store.get(id);
        switch (node.tag) {
            .lit => {
                const l = self.store.lits.items[node.aux];
                switch (l) {
                    .int => |val| c.* += val,
                    else => {},
                }
            },
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, v)) b.* += 1;
            },
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag != .sym) return;
                const op = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);
                if (args.len != 2) return;
                if (std.mem.eql(u8, op, "+")) {
                    self.math.collectCoeffs(args[0], v, a, b, c);
                    self.math.collectCoeffs(args[1], v, a, b, c);
                } else if (std.mem.eql(u8, op, "-")) {
                    self.math.collectCoeffs(args[0], v, a, b, c);
                    var a2: i64 = 0;
                    var b2: i64 = 0;
                    var c2: i64 = 0;
                    self.math.collectCoeffs(args[1], v, &a2, &b2, &c2);
                    a.* -= a2;
                    b.* -= b2;
                    c.* -= c2;
                } else if (std.mem.eql(u8, op, "*")) {
                    // k * x ou x * k
                    const n0 = self.store.get(args[0]);
                    const n1 = self.store.get(args[1]);
                    if (n0.tag == .lit and n1.tag == .sym) {
                        const k = self.store.lits.items[n0.aux];
                        const name = self.store.interner.resolve(n1.payload);
                        if (std.mem.eql(u8, name, v)) {
                            switch (k) {
                                .int => |val| b.* += val,
                                else => {},
                            }
                        } else {
                            switch (k) {
                                .int => |val| c.* += val,
                                else => {},
                            }
                        }
                    } else if (n1.tag == .lit and n0.tag == .sym) {
                        const k = self.store.lits.items[n1.aux];
                        const name = self.store.interner.resolve(n0.payload);
                        if (std.mem.eql(u8, name, v)) {
                            switch (k) {
                                .int => |val| b.* += val,
                                else => {},
                            }
                        }
                    } else if (n0.tag == .lit) {
                        // k * (subexpr)
                        const k = self.store.lits.items[n0.aux];
                        var sa: i64 = 0;
                        var sb: i64 = 0;
                        var sc: i64 = 0;
                        self.math.collectCoeffs(args[1], v, &sa, &sb, &sc);
                        switch (k) {
                            .int => |val| {
                                a.* += sa * val;
                                b.* += sb * val;
                                c.* += sc * val;
                            },
                            else => {},
                        }
                    }
                } else if (std.mem.eql(u8, op, "^")) {
                    const base = self.store.get(args[0]);
                    const exp_node = self.store.get(args[1]);
                    if (base.tag == .sym and exp_node.tag == .lit) {
                        const name = self.store.interner.resolve(base.payload);
                        if (std.mem.eql(u8, name, v)) {
                            const e = self.store.lits.items[exp_node.aux];
                            switch (e) {
                                .int => |val| {
                                    if (val == 2) a.* += 1 else if (val == 1) b.* += 1 else if (val == 0) c.* += 1;
                                },
                                else => {},
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn intSqrt(n: i64) i64 {
        if (n <= 0) return 0;
        var x: i64 = 1;
        while (x * x <= n) : (x += 1) {}
        return x - 1;
    }

    // ─── Expand ───

    fn expandExpr(self: *HeavenExpr, id: Id) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        if (node.tag != .apply) return id;
        const func_node = self.store.get(node.payload);
        if (func_node.tag != .sym) return id;
        const op = self.store.interner.resolve(func_node.payload);
        const args = node.span_a.slice(self.store.pool.items);
        if (args.len != 2) return id;
        const a0 = args[0];
        const a1 = args[1];

        if (std.mem.eql(u8, op, "*")) {
            const left = try self.math.expandExpr(a0);
            const right = try self.math.expandExpr(a1);
            // Check si left = (la0 + la1)
            if (left < self.store.len()) {
                const ln = self.store.get(left);
                if (ln.tag == .apply) {
                    const lf = self.store.get(ln.payload);
                    if (lf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(lf.payload), "+")) {
                        const la = ln.span_a.slice(self.store.pool.items);
                        if (la.len == 2) {
                            const la0 = la[0];
                            const la1 = la[1];
                            // Check si right = (ra0 + ra1)
                            if (right < self.store.len()) {
                                const rn = self.store.get(right);
                                if (rn.tag == .apply) {
                                    const rf = self.store.get(rn.payload);
                                    if (rf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(rf.payload), "+")) {
                                        const ra = rn.span_a.slice(self.store.pool.items);
                                        if (ra.len == 2) {
                                            const ra0 = ra[0];
                                            const ra1 = ra[1];
                                            // (a+b)*(c+d) = ac + ad + bc + bd
                                            const ac = try self.store.binop("*", la0, ra0);
                                            const ad = try self.store.binop("*", la0, ra1);
                                            const bc = try self.store.binop("*", la1, ra0);
                                            const bd = try self.store.binop("*", la1, ra1);
                                            const t1 = try self.store.binop("+", ac, ad);
                                            const t2 = try self.store.binop("+", bc, bd);
                                            return self.store.binop("+", t1, t2);
                                        }
                                    }
                                }
                            }
                            // (a+b)*c = ac + bc
                            const t1 = try self.store.binop("*", la0, right);
                            const t2 = try self.store.binop("*", la1, right);
                            return self.store.binop("+", t1, t2);
                        }
                    }
                }
            }
            // a*(c+d) = ac + ad
            if (right < self.store.len()) {
                const rn = self.store.get(right);
                if (rn.tag == .apply) {
                    const rf = self.store.get(rn.payload);
                    if (rf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(rf.payload), "+")) {
                        const ra = rn.span_a.slice(self.store.pool.items);
                        if (ra.len == 2) {
                            const ra0 = ra[0];
                            const ra1 = ra[1];
                            const t1 = try self.store.binop("*", left, ra0);
                            const t2 = try self.store.binop("*", left, ra1);
                            return self.store.binop("+", t1, t2);
                        }
                    }
                }
            }
            return self.store.binop("*", left, right);
        }
        if (std.mem.eql(u8, op, "^")) {
            const base_node = self.store.get(a0);
            const exp_node = self.store.get(a1);
            if (exp_node.tag == .lit and base_node.tag == .apply) {
                const e = self.store.lits.items[exp_node.aux];
                switch (e) {
                    .int => |val| {
                        if (val == 2) {
                            const bf = self.store.get(base_node.payload);
                            if (bf.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(bf.payload), "+")) {
                                const ba = base_node.span_a.slice(self.store.pool.items);
                                if (ba.len == 2) {
                                    const ba0 = ba[0];
                                    const ba1 = ba[1];
                                    const a2 = try self.store.binop("^", ba0, try self.store.int(2));
                                    const two = try self.store.int(2);
                                    const ab = try self.store.binop("*", ba0, ba1);
                                    const two_ab = try self.store.binop("*", two, ab);
                                    const b2 = try self.store.binop("^", ba1, try self.store.int(2));
                                    const t1 = try self.store.binop("+", a2, two_ab);
                                    return self.store.binop("+", t1, b2);
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }
        if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
            const left = try self.math.expandExpr(a0);
            const right = try self.math.expandExpr(a1);
            return self.store.binop(op, left, right);
        }
        return id;
    }

    // ─── Plot ───

    // Helper : crée un binop simplifié à la volée

    fn evalTheorems(self: *HeavenExpr) ![]u8 {
        return self.proof_core.formatAll(self.allocator);
    }

    pub fn evalTheorem(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const colon_pos = std.mem.indexOfScalar(u8, input, ':') orelse
            return try self.allocator.dupe(u8, "Usage: theorem <name> : <stmt>");
        const name = std.mem.trim(u8, input[0..colon_pos], " ");
        const stmt = std.mem.trim(u8, input[colon_pos + 1 ..], " ");

        // Détecter si on a un proof_block inline
        const has_proof_block = std.mem.indexOf(u8, stmt, "{") != null;
        var proof_text: ?[]const u8 = null;
        var stmt_clean = stmt;

        if (has_proof_block) {
            // Extraire le proof_block
            const brace_pos = std.mem.indexOf(u8, stmt, "{").?;
            stmt_clean = std.mem.trim(u8, stmt[0..brace_pos], " ");
            proof_text = stmt[brace_pos..];

            // Convertir "a + 0 = a" en notation Lisp pour l'élaborateur
            if (!std.mem.startsWith(u8, stmt_clean, "forall") and std.mem.indexOf(u8, stmt_clean, "Eq<") == null) {
                const eq_pos = std.mem.indexOf(u8, stmt_clean, "=") orelse return try self.allocator.dupe(u8, "Invalid syntax");
                var lhs = std.mem.trim(u8, stmt_clean[0..eq_pos], " ");
                var rhs = std.mem.trim(u8, stmt_clean[eq_pos + 1 ..], " ");

                var lhs_buf: [256]u8 = undefined;
                var rhs_buf: [256]u8 = undefined;

                // Convertir les opérateurs infixes en notation Lisp
                const ops = [_]struct { char: u8, name: []const u8 }{
                    .{ .char = '+', .name = "add" },
                    .{ .char = '*', .name = "mul" },
                    .{ .char = '-', .name = "sub" },
                    .{ .char = '/', .name = "div" },
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

        // Nouveau format : forall / Eq<> — élaborer via elab.zig
        const is_new_format = std.mem.startsWith(u8, stmt_clean, "forall") or
            std.mem.indexOf(u8, stmt_clean, "Eq<") != null;

        if (is_new_format) {
            // Construire un mini fichier Heaven pour l'élaborer
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

            // Extraire lhs/rhs depuis (forall ... (Eq lhs rhs))
            const eq_args = proof_helpers_mod.extractEqArgsFromStore(&tmp_store, root_id) orelse {
                return try self.allocator.dupe(u8, "✗ could not extract Eq<lhs,rhs> from statement");
            };

            // Copier les nœuds extraits dans self.store
            const lhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, &self.store, eq_args.lhs);
            const rhs = try proof_helpers_mod.copyIdBetweenStores(&tmp_store, &self.store, eq_args.rhs);
            const lhs_canon = try canon_mod.canonicalize(&self.store, self.allocator, lhs);
            const rhs_canon = try canon_mod.canonicalize(&self.store, self.allocator, rhs);

            // Parser le proof_block directement depuis proof_text
            var proof_term: ?*const proof_core.ProofTerm = null;
            if (proof_text) |pt| {
                proof_term = proof_helpers_mod.ProofHelpers.parseProofBlock(self.allocator, pt);
            }

            try self.proof_core.theorem(name, stmt, lhs_canon, rhs_canon);

            // Stocker la preuve si extraite et marquer comme vérifié
            if (proof_term) |pt| {
                if (self.proof_core.theorems.getPtr(name)) |thm| {
                    thm.proof = pt;
                    thm.verified = true;
                }
            }
            const rule_id = try self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
            try self.kb.rules.append(self.allocator, rule_id);
            self.active_theorem = try self.allocator.dupe(u8, name);

            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
            return try self.allocator.dupe(u8, msg);
        }

        // Ancien format : lhs = rhs (chemin inchangé)
        const eq_pos = std.mem.indexOf(u8, stmt, "=") orelse
            return try self.allocator.dupe(u8, "Usage: theorem <name> : <lhs> = <rhs>");
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " ");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 1 ..], " ");
        const lhs = try self.bridge.importExpr(lhs_str);
        const rhs = try self.bridge.importExpr(rhs_str);
        const lhs_canon = try canon_mod.canonicalize(&self.store, self.allocator, lhs);
        const rhs_canon = try canon_mod.canonicalize(&self.store, self.allocator, rhs);
        try self.proof_core.theorem(name, stmt, lhs_canon, rhs_canon);
        const rule_id = try self.store.relation("=>", &.{ lhs_canon, rhs_canon }, &.{});
        try self.kb.rules.append(self.allocator, rule_id);
        self.active_theorem = try self.allocator.dupe(u8, name);
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "✓ theorem {s} stated", .{name});
        return try self.allocator.dupe(u8, msg);
    }

    pub fn evalProve(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const trimmed = std.mem.trim(u8, input, " ");
        // Forme 1 : prove by <method>  (utilise le théorème actif)
        if (std.mem.startsWith(u8, trimmed, "by ")) {
            const rest = trimmed[3..];
            var skill_name: []const u8 = rest;
            var induction_var: []const u8 = "n";
            if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
                skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
                induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
            }
            const target = self.active_theorem orelse
                return try self.allocator.dupe(u8, "No active theorem. Use 'theorem <name> : ...' first.");
            const request_msg = try std.fmt.allocPrint(self.allocator, "proof_request|{s}|{s}|{s}", .{ target, skill_name, induction_var });
            if (self.pending_proof_request) |old| self.allocator.free(old);
            self.pending_proof_request = request_msg;

            self.pending_proof_request = request_msg;

            return self.proveWith(target, skill_name, induction_var);
        }
        // Forme 2 : prove <name> by <method>
        if (std.mem.indexOf(u8, trimmed, " by ")) |by_pos| {
            const name = std.mem.trim(u8, trimmed[0..by_pos], " ");
            const rest = std.mem.trim(u8, trimmed[by_pos + 4 ..], " ");
            var skill_name: []const u8 = rest;
            var induction_var: []const u8 = "n";
            if (std.mem.indexOf(u8, rest, " on ")) |on_pos| {
                skill_name = std.mem.trim(u8, rest[0..on_pos], " ");
                induction_var = std.mem.trim(u8, rest[on_pos + 4 ..], " ");
            }
            self.active_theorem = try self.allocator.dupe(u8, name);

            const request_msg = try std.fmt.allocPrint(self.allocator, "proof_request|{s}|{s}|{s}", .{ name, skill_name, induction_var });
            if (self.pending_proof_request) |old| self.allocator.free(old);
            self.pending_proof_request = request_msg;

            return self.proveWith(name, skill_name, induction_var);
        }
        return try self.allocator.dupe(u8, "Usage: prove [name] by <method> [on <var>]");
    }

    fn proveWith(self: *HeavenExpr, target: []const u8, skill_name: []const u8, induction_var: []const u8) ![]u8 {
        const normalized = std.mem.trim(u8, skill_name, " ");

        if (std.mem.eql(u8, normalized, "simplify")) {
            const ok = try self.proof_core.verifyBySimplify(target, self);
            return self.proofResult(target, ok, "simplify");
        }

        if (std.mem.eql(u8, normalized, "eval")) {
            const ok = try self.proof_core.verifyByEval(target, &self.engine, &self.store);
            return self.proofResult(target, ok, "eval");
        }

        if (std.mem.eql(u8, normalized, "induction")) {
            const ok = try self.proof_core.verifyByInduction(target, induction_var, self, &self.store);
            return self.proofResult(target, ok, "induction");
        }

        if (std.mem.eql(u8, normalized, "rewrite")) {
            const ok = try self.proof_core.verifyByRewrite(target, self);
            return self.proofResult(target, ok, "rewrite");
        }

        // fallback vers evalSkill (qui gère aussi algebra, etc.)
        return self.evalSkill(normalized);
    }

    fn proofResult(self: *HeavenExpr, target: []const u8, ok: bool, method: []const u8) ![]u8 {
        if (ok) {
            if (self.proof_core.theorems.getPtr(target)) |thm| {
                thm.verified = true;
            }
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, method });
            return try self.allocator.dupe(u8, msg);
        } else {
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✗ [{s}] proof failed ({s})", .{ target, method });
            return try self.allocator.dupe(u8, msg);
        }
    }

    pub fn evalSkill(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const skill_name = std.mem.trim(u8, input, " ");
        const target = self.active_theorem orelse
            return try self.allocator.dupe(u8, "No active theorem.");

        const thm = self.proof_core.theorems.getPtr(target) orelse
            return try self.allocator.dupe(u8, "Theorem not found");

        const ok = if (std.mem.eql(u8, skill_name, "simplify"))
            try self.proof_core.verifyBySimplify(target, self)
        else if (std.mem.eql(u8, skill_name, "eval"))
            try self.proof_core.verifyByEval(target, &self.engine, &self.store)
        else if (std.mem.eql(u8, skill_name, "induction"))
            try self.proof_core.verifyByInduction(target, "n", self, &self.store)
        else if (std.mem.eql(u8, skill_name, "algebra"))
            try self.proof_core.verifyBySimplify(target, self)
        else
            return try self.allocator.dupe(u8, "skill: unknown tactic");

        if (ok) {
            thm.verified = true;
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "✓ [{s}] proved ({s})", .{ target, skill_name });
            return try self.allocator.dupe(u8, msg);
        } else {
            return try self.allocator.dupe(u8, "✗ proof failed");
        }
    }

    fn preprocessCallSyntax(self: *HeavenExpr, input: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '(') {
                // Trouver le nom de la fonction avant la parenthèse
                var start = i;
                while (start > 0 and input[start - 1] != ' ' and input[start - 1] != '(') start -= 1;
                const func_name = input[start..i];
                // Écrire "(funcname "
                try buf.append(self.allocator, '(');
                try buf.appendSlice(self.allocator, func_name);
                try buf.append(self.allocator, ' ');
                i += 1; // passer '('
                // Traiter les arguments
                var depth: u32 = 1;
                var arg_start = i;
                while (i < input.len and depth > 0) {
                    switch (input[i]) {
                        '(' => depth += 1,
                        ')' => depth -= 1,
                        ',' => {
                            if (depth == 1) {
                                // Fin d'un argument
                                const arg = input[arg_start..i];
                                const processed = try preprocessCallSyntax(self, arg);
                                defer self.allocator.free(processed);
                                try buf.appendSlice(self.allocator, processed);
                                try buf.append(self.allocator, ' ');
                                arg_start = i + 1;
                            }
                        },
                        else => {},
                    }
                    i += 1;
                }
                // Dernier argument (après la dernière virgule, avant ')')
                if (arg_start < i - 1) {
                    const arg = input[arg_start .. i - 1];
                    const processed = try preprocessCallSyntax(self, arg);
                    defer self.allocator.free(processed);
                    try buf.appendSlice(self.allocator, processed);
                }
                try buf.append(self.allocator, ')');
            } else {
                try buf.append(self.allocator, input[i]);
                i += 1;
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }

    /// Convertit les virgules d'une expression Heaven en espaces pour la syntaxe Lisp
    /// Exemple: "if(n == 0, 1, n * fac(n - 1))" -> "(if (== n 0) 1 (* n (fac (- n 1))))"
    fn commasToLisp(self: *HeavenExpr, input: []const u8) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(self.allocator);
        var i: usize = 0;
        var depth: u32 = 0;
        var in_paren = false;

        while (i < input.len) {
            const ch = input[i];
            switch (ch) {
                '(' => {
                    try buf.append(self.allocator, '(');
                    depth += 1;
                    if (depth == 1) in_paren = true;
                    i += 1;
                },
                ')' => {
                    try buf.append(self.allocator, ')');
                    if (depth > 0) depth -= 1;
                    if (depth == 0) in_paren = false;
                    i += 1;
                },
                ',' => {
                    // Remplacer la virgule par un espace uniquement à l'intérieur des parenthèses
                    if (in_paren) {
                        try buf.append(self.allocator, ' ');
                    } else {
                        try buf.append(self.allocator, ',');
                    }
                    i += 1;
                },
                else => {
                    try buf.append(self.allocator, ch);
                    i += 1;
                },
            }
        }
        return buf.toOwnedSlice(self.allocator);
    }

    fn parseLambda(self: *HeavenExpr, input: []const u8) (std.mem.Allocator.Error || error{NotALambda})!Id {
        var work = std.mem.trim(u8, input, " \t");
        if (work.len == 0) return error.NotALambda;

        const is_backslash = work[0] == '\\';
        const is_lambda_char = work[0] == 'λ';

        // Cherche "->" ou "=>" pour la syntaxe "x -> body"
        const arrow_pos = blk: {
            var i: usize = 0;
            while (i < work.len - 1) : (i += 1) {
                if ((work[i] == '-' or work[i] == '=') and work[i + 1] == '>') {
                    break :blk i;
                }
            }
            break :blk null;
        };

        var param_str: []const u8 = undefined;
        var body_str: []const u8 = undefined;

        if (is_backslash or is_lambda_char) {
            // Cas \x. body ou λx. body
            const after_prefix = if (is_backslash) work[1..] else work[3..]; // λ fait 2 octets en UTF-8
            const trimmed_prefix = std.mem.trimLeft(u8, after_prefix, " \t");

            // Trouver la fin du nom du paramètre (arrêt sur espace, point, ou tiret)
            var delim_pos: usize = 0;
            for (trimmed_prefix, 0..) |c, i| {
                if (c == '.' or c == ' ' or c == '-' or c == '=') {
                    delim_pos = i;
                    break;
                }
                delim_pos = i + 1;
            }

            param_str = std.mem.trim(u8, trimmed_prefix[0..delim_pos], " \t");

            // Trouver le début du body (skip le délimiteur)
            var body_start = delim_pos;
            if (body_start < trimmed_prefix.len and (trimmed_prefix[body_start] == '-' or trimmed_prefix[body_start] == '=')) {
                body_start += 2; // skip -> ou =>
            } else if (body_start < trimmed_prefix.len and trimmed_prefix[body_start] == '.') {
                body_start += 1; // skip .
            }
            body_str = std.mem.trimLeft(u8, trimmed_prefix[body_start..], " \t");
        } else if (arrow_pos) |apos| {
            // Cas "x -> body"
            param_str = std.mem.trim(u8, work[0..apos], " \t");
            body_str = std.mem.trimLeft(u8, work[apos + 2 ..], " \t"); // +2 pour skip ->

            // Vérifier que le côté gauche est un seul identifiant valide (pas "x + y ->")
            for (param_str) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') return error.NotALambda;
            }
        } else {
            return error.NotALambda;
        }

        if (param_str.len == 0 or body_str.len == 0) return error.NotALambda;

        // Parser le body (qui peut être un AUTRE lambda, un let, ou une expression mathématique)
        // On essaie le lambda d'abord, si ça échoue on fait un let ou du math.
        const body_id = self.parser.parseLambda(body_str) catch |err| {
            if (err == error.NotALambda) {
                return self.parser.parseLetExpr(body_str);
            }
            return err;
        };

        // Créer le vrai nœud AST
        return self.store.lambdaNative(param_str, body_id);
    }

    fn parseLetExpr(self: *HeavenExpr, input: []const u8) (std.mem.Allocator.Error || error{NotALambda})!Id {
        // 1. Ignorer le mot-clé "let" s'il est présent (pour les appels récursifs)
        var work = input;
        if (std.mem.startsWith(u8, work, "let ")) {
            work = std.mem.trimLeft(u8, work[4..], " \t");
        }

        // 2. Cherche " in " (en utilisant `work` au lieu de `input`)
        if (std.mem.indexOf(u8, work, " in ")) |pos| {
            const lhs_str = std.mem.trim(u8, work[0..pos], " \t");
            const body_str = std.mem.trim(u8, work[pos + 4 ..], " \t");

            // Trouve le '=' dans la partie gauche
            var eq_pos: ?usize = null;
            var i: usize = lhs_str.len;
            while (i > 0) : (i -= 1) {
                if (lhs_str[i - 1] == '=') {
                    const next_c = if (i < lhs_str.len) lhs_str[i] else ' ';
                    const prev_c = if (i >= 2) lhs_str[i - 2] else ' ';
                    if (next_c != '=' and prev_c != '!' and prev_c != '<' and prev_c != '>') {
                        eq_pos = i - 1;
                        break;
                    }
                }
            }

            if (eq_pos) |eq| {
                const name = std.mem.trim(u8, lhs_str[0..eq], " \t");
                const rhs_str = std.mem.trim(u8, lhs_str[eq + 1 ..], " \t");

                // Parse le côté droit (essaie lambda, sinon math)
                const rhs_id = if (self.parser.parseLambda(rhs_str)) |id| id else |_| blk: {
                    break :blk try self.bridge.importExpr(rhs_str);
                };

                // Parse le corps RÉCURSIVEMENT
                const body_id = try self.parser.parseLetExpr(body_str);

                // Construit le vrai nœud AST
                return self.store.letIn(name, rhs_id, body_id);
            }
        }

        // Plus de " in ", c'est une expression mathématique standard
        return self.bridge.importExpr(work);
    }

    fn evalLet(self: *HeavenExpr, input: []const u8) ![]u8 {
        return self.cmds.evalLet(input);
    }
    fn evalLeto(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();

        // CAS 1 : Il y a " in " -> Expression scopée (utilisant le vrai AST)
        //if (std.mem.indexOf(u8, input, " in ")) |pos| {
        if (std.mem.indexOf(u8, input, " in ")) |_| {
            const ast = self.parser.parseLetExpr(input) catch {
                return try self.allocator.dupe(u8, "syntax error in let expression");
            };

            self.engine.fuel = 10_000;
            const result = self.engine.eval(ast) catch ast;
            return expr.toStringInfix(&self.store, result, self.allocator);
        }

        // CAS 2 : Pas de " in " -> Définition globale persistante
        var eq_pos: ?usize = null;
        var i: usize = input.len;
        while (i > 0) : (i -= 1) {
            if (input[i - 1] == '=') {
                const next_c = if (i < input.len) input[i] else ' ';
                const prev_c = if (i >= 2) input[i - 2] else ' ';
                if (next_c != '=' and prev_c != '!' and prev_c != '<' and prev_c != '>') {
                    eq_pos = i - 1;
                    break;
                }
            }
        }

        if (eq_pos) |eq| {
            const name = std.mem.trim(u8, input[0..eq], " \t");
            const expr_str = std.mem.trim(u8, input[eq + 1 ..], " \t");
            return self.define(name, expr_str);
        }

        return try self.allocator.dupe(u8, "syntax error: missing =");
    }

    fn evalMir(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();

        // Diviser en instructions séparées par ;
        var instructions = std.mem.splitScalar(u8, input, ';');

        // Exécuter toutes les instructions sauf la dernière (qui est l'expression de retour)
        var last_expr: []const u8 = "";
        while (instructions.next()) |instr| {
            const trimmed = std.mem.trim(u8, instr, " \t");
            if (trimmed.len == 0) continue;
            last_expr = trimmed;
        }

        // Pour l'instant, on parse la dernière expression comme expression MIR
        // Si elle contient des variables, il faut les injecter dans global_vars

        // Solution temporaire : utiliser parseSExpr pour la syntaxe Lisp uniquement
        const id = self.parser.parseSExpr(last_expr) catch |err| {
            return std.fmt.allocPrint(self.allocator, "parse error: {s}", .{@errorName(err)});
        };

        var mir_func = mir.MirFunction.init(self.allocator);
        defer mir_func.deinit();
        mir_func.engine = &self.engine;
        mir_func.store_ref = &self.store;

        const entry_block = try mir_func.newBlock();
        var locals = std.AutoHashMap(u32, mir.ValueId).init(self.allocator);
        defer locals.deinit();
        const result_val = try mir_func.compileExpr(&self.store, id, entry_block, locals);

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

    pub fn loadFile(self: *HeavenExpr, path: []const u8) HeavenError![]u8 {
        self.ensureInit();
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

    fn evalAsk(self: *HeavenExpr, input: []const u8) ![]u8 {
        const prompt = std.mem.trim(u8, input, " ");
        if (prompt.len == 0) return try self.allocator.dupe(u8, "Usage: ask <question>");

        // Obtenir une suggestion de l'agent
        const suggestion = try self.agent.suggest(prompt) orelse
            return try self.allocator.dupe(u8, "Je ne sais pas répondre à cette question.");

        // Afficher la suggestion
        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "[INFO] Suggestion : {s}\n", .{suggestion});

        // Exécuter la suggestion automatiquement
        const result = try self.eval(suggestion);
        defer self.allocator.free(result);

        const full = try std.fmt.allocPrint(self.allocator, "{s}→ {s}", .{ msg, result });
        return full;
    }

    fn evalJs(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const id = self.parser.parseSExpr(input) catch |err| {
            return std.fmt.allocPrint(self.allocator, "js parse error: {s}", .{@errorName(err)});
        };
        return codegen_js.exprToJs(&self.store, id, self.allocator);
    }

    fn evalTransform(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        const eq_pos = std.mem.indexOf(u8, input, "=") orelse return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, input[0..eq_pos], " ");
        const rhs_str = std.mem.trim(u8, input[eq_pos + 1 ..], " ");

        // Plus de bridge.importExpr !
        const lhs_id = self.parser.parseSExpr(lhs_str) catch return error.InvalidSyntax;
        const rhs_id = self.parser.parseSExpr(rhs_str) catch return error.InvalidSyntax;

        var tf = transform_mod.Transform.init(self.allocator, &self.store, &self.kb);
        const result = tf.transform(lhs_id, rhs_id, &self.engine);

        return transform_mod.format(result, &self.store, self.allocator);
    }

    fn extractProofId(store: *Store, id: Id) ?Id {
        const node = store.get(id);
        const pool = store.pool.items;

        // Traverser source_file
        if (node.tag == .source_file) {
            const children = node.span_a.slice(pool);
            if (children.len == 0) return null;
            return extractProofId(store, children[0]);
        }

        // Traverser bind ou theorem
        if (node.tag == .bind) {
            return extractProofId(store, node.aux);
        }

        // Chercher dans les arguments de apply
        if (node.tag == .apply) {
            const args = node.span_a.slice(pool);
            for (args) |arg| {
                const arg_node = store.get(arg);
                if (arg_node.tag == .apply) {
                    const func_node = store.get(arg_node.payload);
                    if (func_node.tag == .sym) {
                        const func_name = store.interner.resolve(func_node.payload);
                        if (std.mem.eql(u8, func_name, "proof")) {
                            return arg;
                        }
                    }
                }
                // Récursion
                if (extractProofId(store, arg)) |found| return found;
            }
        }

        return null;
    }

    fn extractProofTerm(store: *Store, allocator: Allocator, id: Id) ?*const proof_core.ProofTerm {
        const node = store.get(id);
        const pool = store.pool.items;

        // Cas 1 : nœud sym "qed"
        if (node.tag == .sym) {
            const name = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, name, "qed")) {
                const pt = allocator.create(proof_core.ProofTerm) catch return null;
                pt.* = .{ .qed = {} };
                return pt;
            }
        }

        // Cas 2 : nœud apply
        if (node.tag == .apply) {
            const func_node = store.get(node.payload);
            if (func_node.tag == .sym) {
                const func_name = store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(pool);

                // apply refl
                if (std.mem.eql(u8, func_name, "refl") and args.len == 0) {
                    const pt = allocator.create(proof_core.ProofTerm) catch return null;
                    pt.* = .{ .refl = 0 }; // TODO: extraire le vrai ID
                    return pt;
                }

                // apply <expr>
                if (args.len == 1) {
                    const pt = allocator.create(proof_core.ProofTerm) catch return null;
                    pt.* = .{ .by_eval = .{ .lhs = 0, .rhs = args[0] } }; // TODO: raffiner
                    return pt;
                }
            }
        }

        // Cas 3 : nœud proof (liste de steps)
        if (node.tag == .apply) {
            const func_node = store.get(node.payload);
            if (func_node.tag == .sym) {
                const func_name = store.interner.resolve(func_node.payload);
                if (std.mem.eql(u8, func_name, "proof")) {
                    const args = node.span_a.slice(pool);
                    // Prendre le dernier step (qed)
                    if (args.len > 0) {
                        return extractProofTerm(store, allocator, args[args.len - 1]);
                    }
                }
            }
        }

        return null;
    }

    fn loadBootstrap(self: *HeavenExpr) void {
        // WASM n'a pas de filesystem - désactivé temporairement
        if (@import("builtin").target.cpu.arch == .wasm32) return;
        const source = platform.fs.cwd().readFileAlloc(self.allocator, "core/bootstrap.hvn", 64 * 1024) catch |err| {
            if (PROOF_DEBUG) platform.debug.print("DEBUG: loadBootstrap failed to read core/bootstrap.hvn: {s}\n", .{@errorName(err)});
            return;
        };
        defer self.allocator.free(source);

        _ = elab_mod.elaborateSource(
            self.allocator,
            &self.store,
            source,
            &self.engine.fns,
        ) catch |err| {
            if (PROOF_DEBUG) platform.debug.print("DEBUG: loadBootstrap elaborateSource failed: {s}\n", .{@errorName(err)});
            return;
        };

        // Charger la bibliothèque standard (std.hvn) en Heaven pur
        const std_source = platform.fs.cwd().readFileAlloc(self.allocator, "core/std.hvn", 64 * 1024) catch |err| {
            if (PROOF_DEBUG) platform.debug.print("DEBUG: loadBootstrap failed to read core/std.hvn: {s}\n", .{@errorName(err)});
            return;
        };
        defer self.allocator.free(std_source);

        var std_lines = std.mem.splitScalar(u8, std_source, '\n');
        while (std_lines.next()) |line| {
            const trimmed_line = std.mem.trim(u8, line, " \t\r");
            if (trimmed_line.len > 0 and trimmed_line[0] != '#') {
                const result = self.eval(trimmed_line) catch |err| {
                    if (PROOF_DEBUG) platform.debug.print("DEBUG: std.hvn eval error on '{s}': {}\n", .{ trimmed_line, err });
                    continue;
                };
                self.allocator.free(result);
            }
        }
    }

    // ─── Math API (délégation à self.math) ───

    pub fn derive(self: *HeavenExpr, input: []const u8, varname: []const u8) ![]u8 {
        self.ensureInit();
        return self.math.derive(input, varname);
    }

    pub fn integrate(self: *HeavenExpr, input: []const u8, varname: []const u8) ![]u8 {
        self.ensureInit();
        return self.math.integrate(input, varname);
    }

    pub fn solve(self: *HeavenExpr, input: []const u8, varname: []const u8) ![]u8 {
        self.ensureInit();
        return self.math.solve(input, varname);
    }

    pub fn expand(self: *HeavenExpr, input: []const u8) ![]u8 {
        self.ensureInit();
        return self.math.expand(input);
    }

    pub fn plot(self: *HeavenExpr, input: []const u8, varname: []const u8) ![]u8 {
        self.ensureInit();
        return self.math.plot(input, varname);
    }

    // ─── Codegen API (délégation à self.codegen) ───

    pub fn toC(self: *HeavenExpr, ids: []const expr.Id) ![]u8 {
        self.ensureInit();
        return self.codegen.toC(ids);
    }

    pub fn toLaTeXInline(self: *HeavenExpr, id: expr.Id) ![]u8 {
        self.ensureInit();
        return self.codegen.toLaTeXInline(id);
    }

    pub fn format(self: *HeavenExpr, id: expr.Id) ![]u8 {
        self.ensureInit();
        return self.codegen.format(id);
    }

    // ─── Simplify API (délégation à cmds.simplify_eng) ───

    pub fn simplifyRec(self: *HeavenExpr, id: expr.Id, depth: u32) !expr.Id {
        self.ensureInit();
        return self.cmds.simplify_eng.simplifyRec(id, depth);
    }

    pub fn cmdMcpServe(self: *HeavenExpr, _: []const u8) ![]const u8 {
        self.ensureInit();
        var server = mcp_server_mod.McpServer.init(self.allocator);
        server.ensureHeaven();

        platform.io.print("Starting Heaven MCP Server on stdio...\n", .{});
        platform.io.print("Configure Claude Desktop with:\n", .{});
        platform.io.print("  {{\"mcpServers\": {{\"heaven\": {{\"command\": \"./zig-out/bin/heaven\", \"args\": [\"mcp\"]}}}}}}\n", .{});

        server.run() catch |err| {
            return std.fmt.allocPrint(self.allocator, "MCP server error: {s}", .{@errorName(err)});
        };

        return self.allocator.dupe(u8, "MCP server stopped");
    }
};

fn dumpNode(store: *Store, id: Id, depth: usize) void {
    const node = store.get(id);
    const pool = store.pool.items;

    // Indentation avec boucle
    var i: usize = 0;
    while (i < depth * 2) : (i += 1) platform.debug.print(" ", .{});

    platform.debug.print("[{d}] tag={any}", .{ id, node.tag });

    if (node.tag == .sym) {
        platform.debug.print(" sym_id={d}", .{node.payload});
    }

    if (node.tag == .apply) {
        platform.debug.print(" func_id={d}", .{node.payload});
        const args = node.span_a.slice(pool);
        platform.debug.print(" nargs={d}", .{args.len});
    }

    platform.debug.print("\n", .{});

    // Récursion
    if (node.tag == .apply) {
        const args = node.span_a.slice(pool);
        for (args) |arg| {
            dumpNode(store, arg, depth + 1);
        }
    }
    if (node.tag == .source_file or node.tag == .block) {
        const children = node.span_a.slice(pool);
        for (children) |child| {
            dumpNode(store, child, depth + 1);
        }
    }
}

// ═══════════════════════════════════════════════════ // Tests // ═══════════════════════════════════════════════════

//test "eval canon — x + 0 = x" {
//    const alloc = std.testing.allocator;
//    var he = HeavenExpr.init(alloc);
//    defer he.deinit();
//    const res = try he.eval("x + 0");
//    defer alloc.free(res);
//    try std.testing.expectEqualStrings("x", res);
//}

//test "eval canon — x * 1 = x" {
//    const alloc = std.testing.allocator;
//    var he = HeavenExpr.init(alloc);
//    defer he.deinit();
//    const res = try he.eval("x * 1");
//    defer alloc.free(res);
//    try std.testing.expectEqualStrings("x", res);
//}

//test "eval canon — 3 + 5 = 8" {
//    const alloc = std.testing.allocator;
//    var he = HeavenExpr.init(alloc);
//    defer he.deinit();
//    const res = try he.eval("3 + 5");
//    defer alloc.free(res);
//    try std.testing.expectEqualStrings("8", res);
//}
