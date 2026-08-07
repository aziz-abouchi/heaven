const std = @import("std");
const pattern_mod = @import("pattern");
const Allocator = std.mem.Allocator;
const canon = @import("canon");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Sym = expr.Sym;
const platform = @import("platform");

// DEBUG TOGGLE
const PROOF_DEBUG = false;

const log = std.log.scoped(.engine);

// ═══════════════════════════════════════════════════════════════════════════════
// HEAVEN EVALUATOR — NOYAU À 6 PRIMITIVES
//
// L'évaluateur ne manipule JAMAIS que les 6 primitives fondamentales :
//   lit, sym, apply, bind, lambda, relation
//
// Toute extension (let_in, hole, quote, perform, handle, listes, etc.)
// doit être lowered en primitives AVANT d'atteindre eval().
//
// Les "symboles magiques" (if, quote, perform, handle, spawn, etc.)
// sont interceptés dans la branche .apply quand le func évalué est un sym.
// ═══════════════════════════════════════════════════════════════════════════════

pub const Env = struct {
    bindings: std.AutoHashMapUnmanaged(Sym, Id) = .{},
    allocator: Allocator,

    pub fn init(allocator: Allocator) Env {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Env) void {
        self.bindings.deinit(self.allocator);
    }

    pub fn put(self: *Env, s: Sym, val: Id) !void {
        try self.bindings.put(self.allocator, s, val);
    }

    pub fn get(self: *const Env, s: Sym) ?Id {
        return self.bindings.get(s);
    }

    pub fn delete(self: *Env, s: Sym) void {
        _ = self.bindings.remove(s);
    }
};

pub const EvalError = error{
    TypeError,
    ArityMismatch,
    DivisionByZero,
    StackOverflow,
    OutOfMemory,
    RecursionLimitExceeded,
    ActorIdNotLiteral,
    ActorNotFound,
    HandlerFailed,
    EffectPerformed,
    AssertionFailed,
    ExtensionNotLowered,
};

/// Function clause: one definition pattern
pub const FunctionClause = struct {
    patterns: [8]Id,
    num_patterns: u8,
    body: Id,
};

/// Function definition: name + multiple clauses (Idris-style)
pub const FunctionDef = struct {
    clauses: [16]FunctionClause,
    num_clauses: u8,

    pub fn addClause(self: *FunctionDef, patterns: []const Id, body: Id) void {
        if (self.num_clauses >= 16) return;
        var clause = FunctionClause{
            .patterns = undefined,
            .num_patterns = @intCast(@min(patterns.len, 8)),
            .body = body,
        };
        @memcpy(clause.patterns[0..clause.num_patterns], patterns[0..clause.num_patterns]);
        self.clauses[self.num_clauses] = clause;
        self.num_clauses += 1;
    }
};

/// Registry of named functions with pattern-matched clauses
pub const FunctionRegistry = struct {
    functions: std.StringHashMapUnmanaged(FunctionDef),
    allocator: Allocator,

    pub fn init(allocator: Allocator) FunctionRegistry {
        return .{ .functions = .{}, .allocator = allocator };
    }

    pub fn deinit(self: *FunctionRegistry) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.functions.deinit(self.allocator);
    }

    pub fn register(self: *FunctionRegistry, name: []const u8, patterns: []const Id, body: Id) !void {
        if (self.functions.getEntry(name)) |entry| {
            entry.value_ptr.addClause(patterns, body);
        } else {
            const name_copy = try self.allocator.dupe(u8, name);
            var new_def = FunctionDef{ .clauses = undefined, .num_clauses = 0 };
            new_def.addClause(patterns, body);
            try self.functions.put(self.allocator, name_copy, new_def);
        }
    }

    pub fn get(self: *FunctionRegistry, name: []const u8) ?*FunctionDef {
        return self.functions.getPtr(name);
    }
};

pub const RewriteRule = struct {
    lhs: Id,
    rhs: Id,
};

pub const MacroDef = struct {
    params_span: expr.Span,
    body: Id,
};

pub const Actor = struct {
    state: Id,
    handler: Id,
};

pub const Engine = struct {
    store: *Store,
    allocator: Allocator,
    env: Env,
    fns: FunctionRegistry,
    local_rewrites: ?*std.ArrayListUnmanaged(RewriteRule) = null,
    fuel: u32 = 100_000,
    recursion_depth: u32 = 0,
    max_recursion_depth: u32 = 1000,
    evaluating: std.AutoHashMapUnmanaged(Id, void) = .{},
    macros: std.AutoHashMapUnmanaged(Sym, MacroDef) = .{},
    actors: std.AutoHashMapUnmanaged(u32, Actor) = .{},
    next_actor_id: u32 = 1,
    pending_effect: ?struct { name: Sym, args: []Id } = null,
    green_mode: bool = false,
    green_call_count: u32 = 0,

    pub fn init(store: *Store, allocator: Allocator) Engine {
        return .{
            .store = store,
            .allocator = allocator,
            .env = Env.init(allocator),
            .fns = FunctionRegistry.init(allocator),
            .fuel = 10_000,
            .max_recursion_depth = 1000,
            .recursion_depth = 0,
            .evaluating = .{},
        };
    }

    pub fn deinit(self: *Engine) void {
        self.evaluating.deinit(self.allocator);
        self.env.deinit();
        self.fns.deinit();
        self.macros.deinit(self.allocator);
        self.actors.deinit(self.allocator);

        if (self.pending_effect) |eff| {
            self.allocator.free(eff.args);
        }
    }

    pub fn ensureInit(_: *Engine) void {}

    // ─────────────────────────────────────────────────────────
    // EVAL — dispatch sur les 6 primitives uniquement
    // ─────────────────────────────────────────────────────────

    pub fn eval(self: *Engine, id: Id) EvalError!Id {
        if (self.fuel == 0) return EvalError.StackOverflow;
        self.fuel -= 1;

        const node = self.store.get(id);
        const pool = self.store.pool.items;

        // Vérification : l'évaluateur ne voit que des primitives
        const prim = node.tag.asPrimitive() orelse {
            return error.ExtensionNotLowered;
        };

        switch (prim) {
            .lit => return id,

            .sym => {
                if (self.env.get(node.payload)) |bound| {
                    return self.eval(bound);
                }
                return id;
            },

            .bind => {
                const val = try self.eval(node.aux);
                try self.env.put(node.payload, val);
                return val;
            },

            .relation => return id,

            .lambda => return id,

            .apply => {
                if (try self.applyLocalRewrites(id)) |r| return r;

                const func_id = try self.eval(node.payload);
                const func_node = self.store.get(func_id);
                const args = node.span_a.slice(pool);

                // ── Func est un symbole : interception des magiques ──
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);

                    // 1. Macros (expansion sans évaluer les args)
                    if (self.macros.get(func_node.payload)) |macro_def| {
                        var local_env = std.AutoHashMapUnmanaged(Sym, Id){};
                        defer local_env.deinit(self.allocator);
                        var it = self.env.bindings.iterator();
                        while (it.next()) |entry| {
                            try local_env.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                        }
                        const params = macro_def.params_span.slice(self.store.pool.items);
                        for (params, 0..) |p_id, i| {
                            if (i < args.len) {
                                const param_node = self.store.get(p_id);
                                if (param_node.tag == .sym) {
                                    try local_env.put(self.allocator, param_node.payload, args[i]);
                                }
                            }
                        }
                        const saved = self.env.bindings;
                        self.env.bindings = local_env;
                        const expanded_ast = try self.eval(macro_def.body);
                        self.env.bindings = saved;
                        return self.eval(expanded_ast);
                    }

                    // 2. Spéciaux paresseux (n'évaluent pas les args à l'avance)
                    if (std.mem.eql(u8, name, "quote")) {
                        if (args.len != 1) return error.ArityMismatch;
                        return try self.expandQuote(args[0]);
                    }
                    if (std.mem.eql(u8, name, "unquote")) {
                        if (args.len != 1) return error.ArityMismatch;
                        return try self.eval(args[0]);
                    }
                    if (std.mem.eql(u8, name, "if")) {
                        return self.evalIfLazy(args);
                    }
                    if (std.mem.eql(u8, name, "handle")) {
                        if (args.len != 2) return error.ArityMismatch;
                        return self.evalHandle(args[0], args[1]);
                    }

                    // 3. Évaluation stricte des args pour le reste
                    var ea = std.ArrayListUnmanaged(Id){};
                    defer ea.deinit(self.allocator);
                    for (args) |a| try ea.append(self.allocator, try self.eval(a));

                    // 4. perform (effet algébrique)
                    if (std.mem.eql(u8, name, "perform")) {
                        if (ea.items.len < 1) return error.ArityMismatch;
                        const op_node = self.store.get(ea.items[0]);
                        if (op_node.tag != .sym) return error.TypeError;
                        const args_dup = try self.allocator.dupe(Id, ea.items[1..]);
                        self.pending_effect = .{ .name = op_node.payload, .args = args_dup };
                        return error.EffectPerformed;
                    }

                    // 5. Builtins stricts
                    if (try self.evalBuiltin(name, ea.items)) |result| {
                        return result;
                    }

                    // 6. Fonctions utilisateur
                    if (self.fns.get(name) != null) {
                        return self.evalFunction(name, ea.items);
                    }

                    // 7. Reconstruction
                    return self.store.apply(func_id, ea.items);
                }

                // ── Func est un lambda ──
                if (func_node.tag == .lambda) {
                    return self.applyLambda(func_id, args);
                }

                // ── Func est un apply(λ, ...) (multi-param curryfié) ──
                if (func_node.tag == .apply) {
                    const inner = self.store.get(func_node.payload);
                    if (inner.tag == .sym) {
                        const name = self.store.interner.resolve(inner.payload);
                        if (std.mem.eql(u8, name, "\xCE\xBB")) {
                            return self.applyLambda(func_id, args);
                        }
                    }
                }

                // ── Fallback : évaluer les args et reconstruire ──
                var na = std.ArrayListUnmanaged(Id){};
                defer na.deinit(self.allocator);
                for (args) |a| try na.append(self.allocator, try self.eval(a));
                return self.store.apply(func_id, na.items);
            },
        }
    }

    // ─────────────────────────────────────────────────────────
    // HANDLE (effets algébriques)
    // ─────────────────────────────────────────────────────────

    fn evalHandle(self: *Engine, body_id: Id, handler_id: Id) !Id {
        const result = self.eval(body_id) catch |err| {
            if (err == error.EffectPerformed) {
                const effect = self.pending_effect orelse return error.EffectPerformed;
                self.pending_effect = null;

                const saved_green = self.green_mode;
                self.green_mode = false;
                defer self.green_mode = saved_green;

                const handler_node = self.store.get(handler_id);
                const handler_result = blk: {
                    if (handler_node.tag == .sym) {
                        const handler_name = self.store.interner.resolve(handler_node.payload);
                        break :blk self.evalFunction(handler_name, effect.args) catch |e| {
                            self.allocator.free(effect.args);
                            return e;
                        };
                    } else if (handler_node.tag == .lambda) {
                        break :blk self.applyLambda(handler_id, effect.args) catch |e| {
                            self.allocator.free(effect.args);
                            return e;
                        };
                    }
                    self.allocator.free(effect.args);
                    return error.HandlerFailed;
                };
                self.allocator.free(effect.args);
                return handler_result;
            }
            return err;
        };
        return result;
    }

    // ─────────────────────────────────────────────────────────
    // LAMBDA APPLICATION
    // ─────────────────────────────────────────────────────────

    fn applyLambda(self: *Engine, lambda_id: Id, arg_ids: []const Id) !Id {
        const lambda_node = self.store.get(lambda_id);
        if (lambda_node.tag != .lambda) return EvalError.TypeError;

        const body_id = lambda_node.span_a.slice(self.store.pool.items)[0];
        const param_sym = lambda_node.payload;

        var saved = self.env.bindings;
        var nb: std.AutoHashMapUnmanaged(Sym, Id) = .{};
        var iter = saved.iterator();
        while (iter.next()) |e| try nb.put(self.allocator, e.key_ptr.*, e.value_ptr.*);

        if (arg_ids.len > 0) {
            try nb.put(self.allocator, param_sym, try self.eval(arg_ids[0]));
        }

        self.env.bindings = nb;
        const result = self.eval(body_id);
        self.env.bindings.deinit(self.allocator);
        self.env.bindings = saved;
        return result;
    }

    // ─────────────────────────────────────────────────────────
    // PEANO EVALUATION
    // ─────────────────────────────────────────────────────────

    fn evalPeano(self: *Engine, id: Id) Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);

        switch (node.tag.asPrimitive() orelse return id) {
            .sym => {
                const name = self.store.interner.resolve(node.payload);
                if (std.mem.eql(u8, name, "zero")) {
                    return self.store.int(0) catch id;
                }
                return id;
            },
            .apply => {
                const func_id = node.payload;
                const func_node = self.store.get(func_id);
                if (func_node.tag != .sym) return id;
                const fname = self.store.interner.resolve(func_node.payload);
                const args = node.span_a.slice(self.store.pool.items);

                if (std.mem.eql(u8, fname, "succ") and args.len == 1) {
                    const inner = self.evalPeano(args[0]);
                    const inner_node = self.store.get(inner);
                    if (inner_node.tag == .lit) {
                        const lit = self.store.lits.items[inner_node.aux];
                        switch (lit) {
                            .int => |v| return self.store.int(v + 1) catch id,
                            else => {},
                        }
                    }
                    return id;
                }

                if (std.mem.eql(u8, fname, "add") and args.len == 2) {
                    const a = self.evalPeano(args[0]);
                    const b = self.evalPeano(args[1]);
                    const an = self.store.get(a);
                    const bn = self.store.get(b);
                    if (an.tag == .lit and bn.tag == .lit) {
                        const al = self.store.lits.items[an.aux];
                        const bl = self.store.lits.items[bn.aux];
                        switch (al) {
                            .int => |av| switch (bl) {
                                .int => |bv| return self.store.int(av + bv) catch id,
                                else => {},
                            },
                            else => {},
                        }
                    }
                    return id;
                }

                if (std.mem.eql(u8, fname, "mul") and args.len == 2) {
                    const a = self.evalPeano(args[0]);
                    const b = self.evalPeano(args[1]);
                    const an = self.store.get(a);
                    const bn = self.store.get(b);
                    if (an.tag == .lit and bn.tag == .lit) {
                        const al = self.store.lits.items[an.aux];
                        const bl = self.store.lits.items[bn.aux];
                        switch (al) {
                            .int => |av| switch (bl) {
                                .int => |bv| return self.store.int(av * bv) catch id,
                                else => {},
                            },
                            else => {},
                        }
                    }
                    return id;
                }

                return id;
            },
            else => return id,
        }
    }

    // ─────────────────────────────────────────────────────────
    // FUNCTION REGISTRY EVALUATION
    // ─────────────────────────────────────────────────────────

    var depth: u32 = 0;

    pub fn evalFunction(self: *Engine, name: []const u8, args: []const Id) !Id {
        depth += 1;
        if (depth > 1000) return error.StackOverflow;
        defer depth -= 1;

        if (self.fuel == 0) return EvalError.StackOverflow;
        self.fuel -= 1;
        self.recursion_depth += 1;
        if (self.recursion_depth > self.max_recursion_depth) {
            return EvalError.RecursionLimitExceeded;
        }
        defer self.recursion_depth -= 1;

        const fdef = self.fns.get(name) orelse return EvalError.ArityMismatch;

        var ci: u8 = 0;
        while (ci < fdef.num_clauses) : (ci += 1) {
            const clause = fdef.clauses[ci];
            if (PROOF_DEBUG) platform.debug.print("evalFunction name={s} args.len={} clause.num_patterns={}\n", .{ name, args.len, clause.num_patterns });
            if (clause.num_patterns != args.len) continue;

            var local_env = std.AutoHashMapUnmanaged(Sym, Id){};
            defer local_env.deinit(self.allocator);

            var it = self.env.bindings.iterator();
            while (it.next()) |entry| {
                try local_env.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
            }

            var all_matched = true;
            for (0..clause.num_patterns) |pi| {
                const pat = clause.patterns[pi];
                const arg_val = try self.eval(args[pi]);
                if (!try self.matchPattern(pat, arg_val, &local_env)) {
                    all_matched = false;
                    break;
                }
            }
            if (!all_matched) continue;

            const saved = self.env.bindings;
            self.env.bindings = local_env;
            const result = self.eval(clause.body);
            self.env.bindings = saved;
            return result;
        }
        return EvalError.ArityMismatch;
    }

    // ─────────────────────────────────────────────────────────
    // BUILTINS STRICTS — retourne null si ce n'est pas un builtin
    // ─────────────────────────────────────────────────────────

    fn evalBuiltin(self: *Engine, name: []const u8, args: []const Id) !?Id {
        // ── Acteurs ──
        if (std.mem.eql(u8, name, "spawn")) {
            if (args.len != 2) return error.ArityMismatch;
            const new_actor_id = self.next_actor_id;
            self.next_actor_id += 1;
            try self.actors.put(self.allocator, new_actor_id, .{
                .state = args[1],
                .handler = args[0],
            });
            return try self.store.int(@intCast(new_actor_id));
        }
        if (std.mem.eql(u8, name, "send")) {
            if (args.len != 2) return error.ArityMismatch;
            const actor_id_lit = args[0];
            const msg_id = args[1];
            const actor_node = self.store.get(actor_id_lit);
            if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
            const actor_id = self.store.lits.items[actor_node.aux].int;
            const actor = self.actors.getPtr(@intCast(actor_id)) orelse return error.ActorNotFound;
            const state_sym = self.store.interner.intern("state") catch return error.OutOfMemory;
            try self.env.put(state_sym, actor.state);
            self.fuel = 1_000_000;
            const handler_node = self.store.get(actor.handler);
            const result = if (handler_node.tag == .lambda) {
                self.applyLambda(actor.handler, &.{msg_id}) catch |err| return err;
            } else {
                if (handler_node.tag != .sym) return error.HandlerFailed;
                const handler_name = self.store.interner.resolve(handler_node.payload);
                self.evalFunction(handler_name, &.{ actor.state, msg_id }) catch |err| return err;
            };
            actor.state = result;
            return try self.store.unitLit();
        }
        if (std.mem.eql(u8, name, "state")) {
            if (args.len != 1) return error.ArityMismatch;
            const actor_id_lit = args[0];
            const actor_node = self.store.get(actor_id_lit);
            if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
            const actor_id = self.store.lits.items[actor_node.aux].int;
            const actor = self.actors.get(@intCast(actor_id)) orelse return error.ActorNotFound;
            return actor.state;
        }

        // ── Tests natifs ──
        if (std.mem.eql(u8, name, "test")) {
            if (args.len < 2) return error.ArityMismatch;
            const test_name_id = args[0];
            const test_body_id = args[1];
            const test_name_node = self.store.get(test_name_id);
            if (test_name_node.tag == .lit and self.store.lits.items[test_name_node.aux] == .str) {
                const test_name = self.store.interner.resolve(self.store.lits.items[test_name_node.aux].str);
                platform.debug.print("Running test: {s}... ", .{test_name});
            }
            _ = self.eval(test_body_id) catch |err| {
                platform.debug.print("FAIL ({s})\n", .{@errorName(err)});
                return err;
            };
            platform.debug.print("OK\n", .{});
            return try self.store.unitLit();
        }
        if (std.mem.eql(u8, name, "assert_eq")) {
            if (args.len != 2) return error.ArityMismatch;
            if (!expr.exprStructuralEq(self.store, args[0], args[1])) {
                return error.AssertionFailed;
            }
            return try self.store.unitLit();
        }
        if (std.mem.eql(u8, name, "assert_err")) {
            if (args.len != 1) return error.ArityMismatch;
            _ = self.eval(args[0]) catch {
                return try self.store.unitLit();
            };
            return error.AssertionFailed;
        }

        // ── Peano ──
        if (std.mem.eql(u8, name, "zero")) {
            return try self.store.sym("zero");
        }
        if (std.mem.eql(u8, name, "succ") and args.len == 1) {
            return self.store.call("succ", &.{args[0]});
        }

        // ── Arithmétique ──
        const is_arith = std.mem.eql(u8, name, "+") or
            std.mem.eql(u8, name, "-") or
            std.mem.eql(u8, name, "*") or
            std.mem.eql(u8, name, "/");

        if (is_arith and args.len == 2) {
            if (self.green_mode) {
                self.green_call_count += 1;
                const perform_sym = try self.store.sym("perform");
                const consume_sym = try self.store.sym("Consume");
                const op_sym = try self.store.sym(name);
                const cost = try self.store.int(1);
                const effect_args = &.{ consume_sym, op_sym, args[0], args[1], cost };
                const consume_node = try self.store.apply(perform_sym, effect_args);
                return self.eval(consume_node) catch |err| {
                    if (err == error.EffectPerformed) return err;
                    const op: ArithOp = if (std.mem.eql(u8, name, "+")) .add else if (std.mem.eql(u8, name, "-")) .sub else if (std.mem.eql(u8, name, "*")) .mul else .div;
                    return try self.arith(args, op);
                };
            }
            const op: ArithOp = if (std.mem.eql(u8, name, "+")) .add else if (std.mem.eql(u8, name, "-")) .sub else if (std.mem.eql(u8, name, "*")) .mul else .div;
            return try self.arith(args, op);
        }
        if (std.mem.eql(u8, name, "^") and args.len == 2) {
            return try self.arithPow(args);
        }
        if (std.mem.eql(u8, name, "==") or std.mem.eql(u8, name, "=")) {
            return try self.evalEq(args);
        }
        if (std.mem.eql(u8, name, "\xCE\xA3") and args.len == 4) {
            return try self.evalAgg(args, .sum);
        }
        if (std.mem.eql(u8, name, "\xCE\xA0") and args.len == 4) {
            return try self.evalAgg(args, .prod);
        }
        if (std.mem.eql(u8, name, "help")) {
            return try self.evalHelp(args);
        }

        return null;
    }

    const ArithOp = enum { add, sub, mul, div };

    fn arith(self: *Engine, args: []const Id, op: ArithOp) !Id {
        if (args.len != 2) return EvalError.ArityMismatch;
        const an = self.store.get(args[0]);
        const bn = self.store.get(args[1]);
        if (an.tag != .lit or bn.tag != .lit) return EvalError.TypeError;
        const al = self.store.lits.items[an.aux];
        const bl = self.store.lits.items[bn.aux];
        switch (al) {
            .int => |va| switch (bl) {
                .int => |vb| {
                    const r: i64 = switch (op) {
                        .add => std.math.add(i64, va, vb) catch return EvalError.TypeError,
                        .sub => std.math.sub(i64, va, vb) catch return EvalError.TypeError,
                        .mul => std.math.mul(i64, va, vb) catch return EvalError.TypeError,
                        .div => if (vb == 0) return EvalError.DivisionByZero else @divTrunc(va, vb),
                    };
                    return self.store.int(r);
                },
                else => return EvalError.TypeError,
            },
            else => return EvalError.TypeError,
        }
    }

    /// if paresseux : n'évalue que la branche choisie
    fn evalIfLazy(self: *Engine, args: []const Id) !Id {
        if (args.len < 2) return EvalError.ArityMismatch;
        const cond_val = try self.eval(args[0]);
        const cn = self.store.get(cond_val);
        const cond = switch (cn.tag) {
            .lit => switch (self.store.lits.items[cn.aux]) {
                .boolean => |b| b,
                .int => |v| v != 0,
                else => return EvalError.TypeError,
            },
            else => return EvalError.TypeError,
        };
        return if (cond)
            self.eval(args[1])
        else if (args.len > 2)
            self.eval(args[2])
        else
            self.store.unitLit();
    }

    /// Parcourt un AST "quoté" et remplace les apply(unquote, [e]) par eval(e)
    fn expandQuote(self: *Engine, id: Id) !Id {
        const node = self.store.get(id);
        switch (node.tag.asPrimitive() orelse return error.ExtensionNotLowered) {
            .apply => {
                const func_node = self.store.get(node.payload);
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);
                    if (std.mem.eql(u8, name, "unquote")) {
                        const inner_args = node.span_a.slice(self.store.pool.items);
                        if (inner_args.len == 1) {
                            return try self.eval(inner_args[0]);
                        }
                    }
                }
                const new_func = try self.expandQuote(node.payload);
                var new_args = std.ArrayListUnmanaged(Id){};
                defer new_args.deinit(self.allocator);
                for (node.span_a.slice(self.store.pool.items)) |arg| {
                    try new_args.append(self.allocator, try self.expandQuote(arg));
                }
                return self.store.apply(new_func, new_args.items);
            },
            .bind => {
                const new_val = try self.expandQuote(node.aux);
                return self.store.bindSym(node.payload, new_val);
            },
            else => return id,
        }
    }

    const AggOp = enum { sum, prod };

    fn evalAgg(self: *Engine, args: []const Id, op: AggOp) !Id {
        if (args.len != 4) return EvalError.ArityMismatch;
        const vn = self.store.get(args[0]);
        if (vn.tag != .sym) return EvalError.TypeError;
        const vs = vn.payload;
        const lon = self.store.get(args[1]);
        const hin = self.store.get(args[2]);
        if (lon.tag != .lit or hin.tag != .lit) return EvalError.TypeError;
        const lo = switch (self.store.lits.items[lon.aux]) {
            .int => |v| v,
            else => return EvalError.TypeError,
        };
        const hi = switch (self.store.lits.items[hin.aux]) {
            .int => |v| v,
            else => return EvalError.TypeError,
        };
        var acc: i64 = switch (op) {
            .sum => 0,
            .prod => 1,
        };
        var i = lo;
        while (i <= hi) : (i += 1) {
            try self.env.put(vs, try self.store.int(i));
            const br = try self.eval(args[3]);
            const bn = self.store.get(br);
            if (bn.tag != .lit) return EvalError.TypeError;
            switch (self.store.lits.items[bn.aux]) {
                .int => |v| switch (op) {
                    .sum => acc += v,
                    .prod => acc *= v,
                },
                else => return EvalError.TypeError,
            }
        }
        return self.store.int(acc);
    }

    fn arithPow(self: *Engine, args: []const Id) !Id {
        if (args.len != 2) return EvalError.ArityMismatch;
        const an = self.store.get(args[0]);
        const bn = self.store.get(args[1]);
        if (an.tag != .lit or bn.tag != .lit) return EvalError.TypeError;
        const al = self.store.lits.items[an.aux];
        const bl = self.store.lits.items[bn.aux];
        switch (al) {
            .int => |va| switch (bl) {
                .int => |vb| {
                    if (vb < 0) return EvalError.TypeError;
                    var result: i64 = 1;
                    var j: i64 = 0;
                    while (j < vb) : (j += 1) {
                        result = std.math.mul(i64, result, va) catch return EvalError.TypeError;
                    }
                    return self.store.int(result);
                },
                else => return EvalError.TypeError,
            },
            else => return EvalError.TypeError,
        }
    }

    fn evalHelp(self: *Engine, args: []const Id) !Id {
        _ = args;
        return try self.store.unitLit();
    }

    fn evalEq(self: *Engine, args: []const Id) !Id {
        if (args.len != 2) return EvalError.ArityMismatch;
        const an = self.store.get(args[0]);
        const bn = self.store.get(args[1]);

        if (an.tag == .lit and bn.tag == .lit) {
            const al = self.store.lits.items[an.aux];
            const bl = self.store.lits.items[bn.aux];
            return switch (al) {
                .int => |va| switch (bl) {
                    .int => |vb| self.store.int(if (va == vb) 1 else 0),
                    else => self.store.int(0),
                },
                else => self.store.int(0),
            };
        }

        if (an.tag == .sym and bn.tag == .sym) {
            return self.store.int(if (an.payload == bn.payload) 1 else 0);
        }

        return self.store.int(0);
    }

    // ─────────────────────────────────────────────────────────
    // PATTERN MATCHING
    // ─────────────────────────────────────────────────────────

    fn matchPattern(
        self: *Engine,
        pat: Id,
        val: Id,
        env: *std.AutoHashMapUnmanaged(Sym, Id),
    ) !bool {
        const pat_node = self.store.get(pat);
        switch (pat_node.tag.asPrimitive() orelse return false) {
            .sym => {
                const name = self.store.interner.resolve(pat_node.payload);
                const is_var = (name[0] >= 'a' and name[0] <= 'z') and
                    !std.mem.eql(u8, name, "zero") and
                    !std.mem.eql(u8, name, "succ");
                if (is_var) {
                    try env.put(self.allocator, pat_node.payload, val);
                    return true;
                } else {
                    const val_node = self.store.get(val);
                    if (val_node.tag != .sym) return false;
                    return val_node.payload == pat_node.payload;
                }
            },
            .apply => {
                const val_node = self.store.get(val);
                if (val_node.tag != .apply) return false;
                const pat_func = self.store.get(pat_node.payload);
                const val_func = self.store.get(val_node.payload);
                if (pat_func.tag != .sym or val_func.tag != .sym) return false;
                if (pat_func.payload != val_func.payload) return false;
                const p = self.store.pool.items;
                const pat_args = pat_node.span_a.slice(p);
                const val_args = val_node.span_a.slice(p);
                if (pat_args.len != val_args.len) return false;
                for (pat_args, val_args) |pa, va| {
                    if (!try self.matchPattern(pa, va, env)) return false;
                }
                return true;
            },
            .lit => {
                const val_node = self.store.get(val);
                if (val_node.tag != .lit) return false;
                const pl = self.store.lits.items[pat_node.aux];
                const vl = self.store.lits.items[val_node.aux];
                return expr.Lit.eql(pl, vl);
            },
            else => return false,
        }
    }

    fn isTruthy(self: *Engine, id: Id) bool {
        if (is_literal_int(self.store, id)) |val| return val != 0;
        return true;
    }

    fn is_literal_int(store: *const Store, id: Id) ?i64 {
        if (id >= store.len()) return null;
        const node = store.get(id);
        if (node.tag != .lit) return null;
        const lit = store.lits.items[node.aux];
        if (lit == .int) return lit.int;
        return null;
    }

    fn applyLocalRewrites(self: *Engine, id: Id) !?Id {
        const rules = self.local_rewrites orelse return null;

        for (rules.items) |rule| {
            var env = std.AutoHashMapUnmanaged(Sym, Id){};
            defer env.deinit(self.allocator);

            if (try self.matchPattern(rule.lhs, id, &env)) {
                const saved = self.env.bindings;
                self.env.bindings = env;
                const result = try self.eval(rule.rhs);
                self.env.bindings = saved;
                return result;
            }
        }
        return null;
    }
};

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

test "eval — arithmetic" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();
    const sum = try store.binop("+", try store.int(3), try store.int(4));
    const result = try engine.eval(sum);
    const s = try expr.toString(&store, result, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("7", s);
}

test "eval — factorial via prod" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();
    const prod = try store.aggregate("\xCE\xA0", "k", try store.int(1), try store.int(5), try store.sym("k"));
    const result = try engine.eval(prod);
    const s = try expr.toString(&store, result, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("120", s);
}

test "eval — conditional" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();
    const if_e = try store.call("if", &.{ try store.boolean(true), try store.int(42), try store.int(0) });
    const result = try engine.eval(if_e);
    const s = try expr.toString(&store, result, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("42", s);
}

test "crash minimal — x + 0" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();

    const x = try store.sym("x");
    const zero = try store.int(0);
    const expr_id = try store.binop("+", x, zero);

    const result = engine.eval(expr_id) catch return;
    const str = try expr.toString(&store, result, allocator);
    defer allocator.free(str);
}

test "eval — recursive fac" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();

    const n_sym = try store.sym("n");
    const zero = try store.int(0);
    const one = try store.int(1);
    const cond = try store.binop("==", n_sym, zero);
    const minus_one = try store.binop("-", n_sym, one);
    const rec_call = try store.call("fac", &.{minus_one});
    const mul = try store.binop("*", n_sym, rec_call);
    const body = try store.call("if", &.{ cond, one, mul });

    try engine.fns.register("fac", &.{n_sym}, body);

    const five = try store.int(5);
    const app = try store.call("fac", &.{five});
    const result = try engine.eval(app);
    const s = try expr.toString(&store, result, allocator);
    defer allocator.free(s);
    try std.testing.expectEqualStrings("120", s);
}

test "eval — mutual recursion" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var engine = Engine.init(&store, allocator);
    defer engine.deinit();

    const n = try store.sym("n");
    const zero = try store.int(0);
    const one = try store.int(1);
    const cond_even = try store.binop("==", n, zero);
    const dec = try store.binop("-", n, one);
    const odd_call = try store.call("odd", &.{dec});
    const even_body = try store.call("if", &.{ cond_even, one, odd_call });
    try engine.fns.register("even", &.{n}, even_body);

    const cond_odd = try store.binop("==", n, zero);
    const even_call = try store.call("even", &.{dec});
    const odd_body = try store.call("if", &.{ cond_odd, zero, even_call });
    try engine.fns.register("odd", &.{n}, odd_body);

    const five = try store.int(5);
    const app_even = try store.call("even", &.{five});
    const res_even = try engine.eval(app_even);
    const s_even = try expr.toString(&store, res_even, allocator);
    defer allocator.free(s_even);
    try std.testing.expectEqualStrings("0", s_even);

    const app_odd = try store.call("odd", &.{five});
    const res_odd = try engine.eval(app_odd);
    const s_odd = try expr.toString(&store, res_odd, allocator);
    defer allocator.free(s_odd);
    try std.testing.expectEqualStrings("1", s_odd);
}
