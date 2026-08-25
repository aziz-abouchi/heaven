//! Frontend Heaven - intégration du moteur de simplification EGraph
const std = @import("std");
const expr = @import("expr");
const engine = @import("engine_expr");
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
} || std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine.EvalError;

pub const Heaven = struct {
    allocator: std.mem.Allocator,
    store: *Store,
    env: engine.Env,
    type_env: types.TypeEnv,
    engine: engine.Engine,
    kb: *transform_mod.KnowledgeBase,
    simplify_eng: simplify_engine_mod.SimplifyEngine,
    proof_core: proof.ProofEnv,
    pending_proof_request: ?[]const u8 = null,
    // Nouveaux champs pour les mathématiques
    bridge: *matrix_bridge.MatrixBridge,
    parser: *parse_mod.Parser,
    math: math_mod.Math,

    pub fn init(allocator: std.mem.Allocator) !Heaven {
        // Allouer le Store sur le tas
        const store = allocator.create(Store) catch @panic("Out of memory allocating Store");
        store.* = Store.init(allocator);
        var env = engine.Env.init(allocator);
        const type_env = types.TypeEnv.init(allocator);
        var eng = engine.Engine{
            .allocator = allocator,
            .store = store,
            .env = &env,
        };

        // Allouer et initialiser le bridge
        const bridge = try allocator.create(matrix_bridge.MatrixBridge);
        bridge.* = matrix_bridge.MatrixBridge.init(store, allocator);

        // Allouer et initialiser le parser
        const parser = try allocator.create(parse_mod.Parser);
        parser.* = parse_mod.Parser.init(store, &eng, &env, allocator);

        const math = math_mod.Math.init(store, &eng, bridge, parser, allocator);

        const kb = try allocator.create(transform_mod.KnowledgeBase);
        kb.* = transform_mod.KnowledgeBase.init(allocator);

        const simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, &eng, &env, kb, allocator);
        const proof_core = proof.ProofEnv.init(allocator);

        var heaven = Heaven{
            .allocator = allocator,
            .store = store,
            .env = env,
            .type_env = type_env,
            .engine = eng,
            .kb = kb,
            .simplify_eng = simplify_eng,
            .proof_core = proof_core,
            .pending_proof_request = null,
            .bridge = bridge,
            .parser = parser,
            .math = math,
        };

        try heaven.addDefaultRules();
        return heaven;
    }

    pub fn deinit(self: *Heaven) void {
        self.store.deinit();
        self.allocator.destroy(self.store);
        self.env.deinit();
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
    }

    pub fn ensureInit(self: *Heaven) void {
        _ = self;
    }

    pub fn eval(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "");

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
            // Par défaut variable "x"
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

        return self.allocator.dupe(u8, trimmed);
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

        //platform.debug.print("[Heaven.simplify] input: {s}\n", .{trimmed});
        //platform.debug.print("[Heaven.simplify] kb.rules.len = {d}\n", .{self.kb.rules.items.len});

        const raw_id = try self.parseExpression(trimmed);
        const id = try self.ensureLowered(raw_id);
        const normalized = try self.ensureLowered(id);

        //platform.debug.print("[Heaven.simplify] parsed id = {d}, normalized id = {d}, store.len = {d}\n", .{ id, normalized, self.store.len() });

        //platform.debug.print("[Heaven.simplify] USING SIMPLIFY_WITH_EGRAPH avec QttCost\n", .{});
        //var qtt = egraph_mod.QttCost{};
        //defer qtt.deinit(self.allocator);

        //const add_sym = try self.store.interner.intern("+");
        //const add_id = try self.store.symId(add_sym);
        //try qtt.quantities.put(self.allocator, add_id, 3); // pénalité max

        //const simplified = try self.simplify_eng.simplifyWithEGraph(normalized, &qtt);
        const simplified = try self.simplify_eng.simplifyWithEGraph(normalized, null, null);
        const result_str = try expr.toStringInfix(self.store, simplified, self.allocator);
        return result_str;
    }

    // ─── Parsing robuste ───
    pub fn importExpr(self: *Heaven, src: []const u8) HeavenError!Id {
        return self.parseExpression(src);
    }

    pub fn parseExpression(self: *Heaven, input: []const u8) HeavenError!Id {
        const trimmed = std.mem.trim(u8, input, " \t");
        if (trimmed.len == 0) return error.InvalidInput;

        if (std.fmt.parseInt(i64, trimmed, 10)) |val| {
            return self.store.int(val);
        } else |_| {}

        if (trimmed[0] != '(') {
            return self.store.sym(trimmed);
        }

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
        platform.debug.print("[parseSExpr] first token: '{s}' (len={d})\n", .{ first, first.len });

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
            platform.debug.print("[parseSExpr] detected lambda\n", .{});
            if (tokens.items.len < 3) return error.InvalidLambda;
            const body_str = tokens.items[tokens.items.len - 1];
            const body_id = try self.parseExpression(body_str);
            const params = tokens.items[1 .. tokens.items.len - 1];
            if (params.len == 0) return error.InvalidLambda;
            const param_name = params[0];
            const result = try self.store.lambdaNative(&.{param_name}, body_id);
            platform.debug.print("[parseSExpr] created lambda id = {d}\n", .{result});
            return result;
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
        return self.allocator.dupe(u8, src);
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
        return self.math.derive(expr_str, var_name);
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
        return self.allocator.dupe(u8, src);
    }
    pub fn substExpr(self: *Heaven, expression: []const u8, var_name: []const u8, val: []const u8) HeavenError![]u8 {
        _ = var_name;
        _ = val;
        return self.allocator.dupe(u8, expression);
    }
    pub fn listRules(self: *Heaven) HeavenError![]u8 {
        return self.allocator.dupe(u8, "[]");
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
        return engine.evaluate(self.store, &self.env, &self.engine, id, 0);
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
    fn addDefaultRules(self: *Heaven) !void {
        const store = self.store;
        const kb = self.kb;

        // Règle : (+ x 0) -> x
        {
            const x = try store.sym("x");
            const zero = try store.int(0);
            const lhs = try store.binop("+", x, zero);
            const rhs = x;
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle : (+ 0 x) -> x
        {
            const x = try store.sym("x");
            const zero = try store.int(0);
            const lhs = try store.binop("+", zero, x);
            const rhs = x;
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle : (* x 1) -> x
        {
            const x = try store.sym("x");
            const one = try store.int(1);
            const lhs = try store.binop("*", x, one);
            const rhs = x;
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle : (* 1 x) -> x
        {
            const x = try store.sym("x");
            const one = try store.int(1);
            const lhs = try store.binop("*", one, x);
            const rhs = x;
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle : (+ x x) -> (* 2 x)
        {
            const x = try store.sym("x");
            const two = try store.int(2);
            const lhs = try store.binop("+", x, x);
            const rhs = try store.binop("*", two, x);
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle : (* 2 x) -> (+ x x) (optionnelle, symétrique pour l'EGraph)
        {
            const x = try store.sym("x");
            const two = try store.int(2);
            const lhs = try store.binop("*", two, x);
            const rhs = try store.binop("+", x, x);
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règle d'associativité : (+ (+ a b) c) -> (+ a (+ b c))
        {
            const a = try store.sym("a");
            const b = try store.sym("b");
            const c = try store.sym("c");
            const ab = try store.binop("+", a, b);
            const lhs = try store.binop("+", ab, c);
            const bc = try store.binop("+", b, c);
            const rhs = try store.binop("+", a, bc);
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }

        // Règles contextuelles pour éliminer les zéros dans les additions
        {
            const a = try store.sym("a");
            const b = try store.sym("b");
            const zero = try store.int(0);

            // (+ (+ 0 a) b) => (+ a b)
            {
                const inner = try store.binop("+", zero, a);
                const lhs = try store.binop("+", inner, b);
                const rhs = try store.binop("+", a, b);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // (+ b (+ 0 a)) => (+ b a)
            {
                const inner = try store.binop("+", zero, a);
                const lhs = try store.binop("+", b, inner);
                const rhs = try store.binop("+", b, a);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // (+ (+ a 0) b) => (+ a b)
            {
                const inner = try store.binop("+", a, zero);
                const lhs = try store.binop("+", inner, b);
                const rhs = try store.binop("+", a, b);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // (+ b (+ a 0)) => (+ b a)
            {
                const inner = try store.binop("+", a, zero);
                const lhs = try store.binop("+", b, inner);
                const rhs = try store.binop("+", b, a);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }
        }

        // ================================================================
        // NOUVELLES RÈGLES AVANCÉES (distributivité, associativité, etc.)
        // ================================================================
        {
            const a = try store.sym("a");
            const b = try store.sym("b");
            const c = try store.sym("c");

            // Distributivité : (* a (+ b c)) -> (+ (* a b) (* a c))
            {
                const bc = try store.binop("+", b, c);
                const lhs = try store.binop("*", a, bc);
                const ab = try store.binop("*", a, b);
                const ac = try store.binop("*", a, c);
                const rhs = try store.binop("+", ab, ac);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // Factorisation : (+ (* a b) (* a c)) -> (* a (+ b c))
            {
                const ab = try store.binop("*", a, b);
                const ac = try store.binop("*", a, c);
                const lhs = try store.binop("+", ab, ac);
                const bc = try store.binop("+", b, c);
                const rhs = try store.binop("*", a, bc);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // Associativité de * : (* (* a b) c) -> (* a (* b c))
            {
                const ab = try store.binop("*", a, b);
                const lhs = try store.binop("*", ab, c);
                const bc = try store.binop("*", b, c);
                const rhs = try store.binop("*", a, bc);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }

            // Inverse : (* a (* b c)) -> (* (* a b) c)
            {
                const bc = try store.binop("*", b, c);
                const lhs = try store.binop("*", a, bc);
                const ab = try store.binop("*", a, b);
                const rhs = try store.binop("*", ab, c);
                const rule = try store.relation("rule", &.{lhs}, &.{rhs});
                try kb.rules.append(self.allocator, rule);
            }
        }
        // Commutativité de +
        {
            const a = try store.sym("a");
            const b = try store.sym("b");
            const lhs = try store.binop("+", a, b);
            const rhs = try store.binop("+", b, a);
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }
        // Commutativité de *
        {
            const a = try store.sym("a");
            const b = try store.sym("b");
            const lhs = try store.binop("*", a, b);
            const rhs = try store.binop("*", b, a);
            const rule = try store.relation("rule", &.{lhs}, &.{rhs});
            try kb.rules.append(self.allocator, rule);
        }
    }
};
