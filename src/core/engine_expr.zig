const std = @import("std");
const pattern_mod = @import("pattern");
const Allocator = std.mem.Allocator;
const canon = @import("canon");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Sym = expr.Sym;
const Tag = expr.Tag;
const platform = @import("platform");

const Span = expr.Span;

const PROOF_DEBUG = false;
const log = std.log.scoped(.engine);

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
    UnknownSymbol,
    UnboundVariable,
    ExtensionNotLowered,
};

pub const FunctionClause = struct {
    patterns: [8]expr.Id,
    num_patterns: u8,
    body: expr.Id,
};

pub const FunctionDef = struct {
    clauses: [16]FunctionClause,
    num_clauses: u8,

    pub fn addClause(self: *FunctionDef, patterns: []const Id, body: Id) void {
        if (self.num_clauses >= 16) return;
        var clause = FunctionClause{ .patterns = undefined, .num_patterns = @intCast(@min(patterns.len, 8)), .body = body };
        @memcpy(clause.patterns[0..clause.num_patterns], patterns[0..clause.num_patterns]);
        self.clauses[self.num_clauses] = clause;
        self.num_clauses += 1;
    }
};

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
            const owned = try self.allocator.dupe(u8, name);
            var def = FunctionDef{ .clauses = undefined, .num_clauses = 0 };
            def.addClause(patterns, body);
            try self.functions.put(self.allocator, owned, def);
        }
    }
    pub fn lookup(self: *const FunctionRegistry, name: []const u8) ?*const FunctionDef {
        return self.functions.getPtr(name);
    }
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    store: *Store,
    env: *Env,
    fns: std.StringHashMapUnmanaged(FunctionDef) = .{},
    macros: std.AutoHashMapUnmanaged(expr.Sym, struct {
        params_span: expr.Span,
        body: expr.Id,
    }) = .{},
    actors: std.AutoHashMapUnmanaged(u32, struct {
        state: expr.Id,
        handler: expr.Id,
    }) = .{},
    next_actor_id: u32 = 0,
    green_call_count: u32 = 0,
    green_mode: bool = false,
    fuel: u64 = 1_000_000,
    max_recursion_depth: usize = 1000,
    recursion_depth: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *Store,
        env: *Env,
    ) Engine {
        return .{
            .allocator = allocator,
            .store = store,
            .env = env,
            .fns = .{},
            .fuel = 100_000,
        };
    }

    pub fn deinit(self: *Engine) void {
        var it = self.fns.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.fns.deinit(self.allocator);
        self.macros.deinit(self.allocator);
        self.actors.deinit(self.allocator);
    }

    pub fn eval(self: *Engine, id: Id) EvalError!Id {
        const store = self.store;
        const env = self.env;
        if (self.fuel == 0) return error.RecursionLimitExceeded;
        self.fuel -= 1;
        return evaluate(store, env, self, id, 0);
    }

    pub fn evalFunction(self: *Engine, name: []const u8, args: []const Id) EvalError!Id {
        const store = self.store orelse return error.UnboundVariable;
        const env = &self.env;

        const fn_def = self.fns.get(name) orelse return error.UnknownSymbol;
        if (fn_def.num_clauses == 0) return error.UnknownSymbol;

        for (fn_def.clauses[0..fn_def.num_clauses]) |clause| {
            if (args.len != clause.num_patterns) continue;

            var matched = true;
            for (clause.patterns[0..clause.num_patterns], 0..) |p, i| {
                const arg_val = try evaluate(store, env, self, args[i], 0);
                const p_node = store.get(p);

                if (p_node.tag == .sym) {
                    try env.put(p_node.payload, arg_val);
                } else if (p_node.tag == .lit) {
                    const arg_node = store.get(arg_val);
                    if (arg_node.tag != .lit or !store.lits.items[p_node.aux].eql(store.lits.items[arg_node.aux])) {
                        matched = false;
                        break;
                    }
                } else if (!pattern_mod.exprStructuralEq(store, p, arg_val)) {
                    matched = false;
                    break;
                }
            }

            if (matched) {
                return evaluate(store, env, self, clause.body, 0);
            }
        }
        return error.ArityMismatch;
    }
};

/// Évaluateur à 6 branches (primitives fondamentales uniquement).
pub fn evaluate(store: *Store, env: *Env, engine: *Engine, id: Id, depth: u32) EvalError!Id {
    if (depth > 1000) return error.RecursionLimitExceeded;
    const node = store.get(id);

    return switch (node.tag) {
        .lit => id,
        .sym => {
            const name = store.interner.resolve(node.payload);
            if (isFrontendExtension(name)) return error.ExtensionNotLowered;
            if (isMagicSymbol(name)) return id;
            if (env.get(node.payload)) |bound| {
                //platform.debug.print("[DEBUG eval] sym '{s}' trouvé dans env, valeur={d}\n", .{ name, bound });
                return bound;
            }
            //platform.debug.print("[DEBUG eval] sym '{s}' NON trouvé dans env\n", .{name});
            return error.UnboundVariable;
        },
        .apply => {
            const pool = store.pool.items;
            const all_args = node.span_a.slice(pool);
            if (all_args.len == 0) return error.ArityMismatch;

            const op_id = node.payload;
            const op_node = store.get(op_id);

            if (op_node.tag != .sym) {
                const evaled_op = try evaluate(store, env, engine, op_id, depth + 1);
                const new_apply = try store.addNode(.{ .tag = .apply, .payload = evaled_op, .aux = 0, .span_a = node.span_a, .span_b = Span.EMPTY });
                return evaluate(store, env, engine, new_apply, depth + 1);
            }

            const op_name = store.interner.resolve(op_node.payload);
            if (isFrontendExtension(op_name)) return error.ExtensionNotLowered;

            const args = if (all_args.len > 1 and all_args[0] == op_id) all_args[1..] else all_args;
            return try evalMagic(store, env, engine, op_name, args, depth);
        },
        .bind => {
            if (node.span_a.len < 1) return error.ArityMismatch;
            const val = try evaluate(store, env, engine, store.spanSliceConst(node.span_a)[0], depth + 1);
            try env.put(node.payload, val);
            const result = if (node.span_a.len >= 2)
                try evaluate(store, env, engine, store.spanSliceConst(node.span_a)[1], depth + 1)
            else
                val;
            env.delete(node.payload);
            return result;
        },
        .lambda => {
            return id;
        },
        .relation => {
            if (node.span_a.len != 2) return error.ArityMismatch;
            const left = try evaluate(store, env, engine, store.spanSliceConst(node.span_a)[0], depth + 1);
            const right = try evaluate(store, env, engine, store.spanSliceConst(node.span_a)[1], depth + 1);
            const eq = pattern_mod.exprStructuralEq(store, left, right);
            return try store.addNode(.{
                .tag = .lit,
                .payload = 0,
                .aux = try store.addLit(.{ .boolean = eq }),
                .span_a = Span.EMPTY,
                .span_b = Span.EMPTY,
            });
        },
        else => error.ExtensionNotLowered,
    };
}

fn isMagicSymbol(name: []const u8) bool {
    const magics = .{ "+", "-", "*", "/", "%", "&", "|", "!", "=", "!=", "<", ">", "<=", ">=", "if", "seq", "block", "tuple", "add", "sub", "mul", "div", "mod", "and", "or", "eq", "neq", "lt", "gt", "le", "ge" };
    inline for (magics) |m| {
        if (std.mem.eql(u8, name, m)) return true;
    }
    return false;
}

fn isFrontendExtension(name: []const u8) bool {
    if (std.mem.eql(u8, name, "quote")) return true;
    if (std.mem.eql(u8, name, "unquote")) return true;
    if (std.mem.eql(u8, name, "perform")) return true;
    if (std.mem.eql(u8, name, "Nil")) return true;
    if (std.mem.eql(u8, name, "Cons")) return true;
    if (std.mem.startsWith(u8, name, "Type_")) return true;
    return false;
}

fn evalMagic(store: *Store, env: *Env, engine: *Engine, op: []const u8, args: []const Id, depth: u32) EvalError!Id {
    // ═══ 1. FONCTIONS UTILISATEUR EN PREMIER ═══
    if (engine.fns.get(op)) |fn_def| {
        if (fn_def.num_clauses > 0) {
            const clause = fn_def.clauses[0];
            if (args.len == clause.num_patterns) {
                // CORRECTION : Créer un nouvel environnement isolé
                var new_env = Env.init(env.allocator);
                defer new_env.deinit();
                var it = env.bindings.iterator();
                while (it.next()) |entry| {
                    try new_env.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                for (clause.patterns[0..clause.num_patterns], 0..) |p, i| {
                    const arg_val = try evaluate(store, env, engine, args[i], depth + 1);
                    const p_node = store.get(p);
                    if (p_node.tag == .sym) {
                        try new_env.put(p_node.payload, arg_val);
                    }
                }
                return evaluate(store, &new_env, engine, clause.body, depth + 1);
            }
        }
    }

    // ═══ 2. OPÉRATEURS MAGIQUES ═══
    if (std.mem.eql(u8, op, "if")) {
        if (args.len != 3) return error.ArityMismatch;
        const cond = try evaluate(store, env, engine, args[0], depth + 1);
        const cond_node = store.get(cond);
        if (cond_node.tag != .lit) return error.TypeError;
        const lit = store.lits.items[cond_node.aux];
        if (lit != .boolean) return error.TypeError;
        return if (lit.boolean) evaluate(store, env, engine, args[1], depth + 1) else evaluate(store, env, engine, args[2], depth + 1);
    }
    if (std.mem.eql(u8, op, "seq") or std.mem.eql(u8, op, "block")) {
        var last: Id = undefined;
        for (args) |arg| last = try evaluate(store, env, engine, arg, depth + 1);
        return last;
    }
    if (std.mem.eql(u8, op, "tuple")) {
        const new_span = try store.reserveSpan(args.len);
        for (0..args.len) |i| {
            store.pool.items[new_span.start + i] = try evaluate(store, env, engine, args[i], depth + 1);
        }
        const sym = try store.interner.intern("tuple");
        const sym_node = try store.addNode(.{ .tag = .sym, .payload = sym, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
        const apply_span = try store.reserveSpan(1 + args.len);
        store.pool.items[apply_span.start] = sym_node;
        @memcpy(store.pool.items[apply_span.start + 1 .. apply_span.start + 1 + args.len], store.pool.items[new_span.start .. new_span.start + args.len]);
        return store.addNode(.{ .tag = .apply, .payload = sym_node, .aux = 0, .span_a = apply_span, .span_b = Span.EMPTY });
    }

    // ═══ 3. ACTEURS : send et state ═══
    if (std.mem.eql(u8, op, "send")) {
        if (args.len != 2) return error.ArityMismatch;
        const actor_id_val = try evaluate(store, env, engine, args[0], depth + 1);
        const msg_val = try evaluate(store, env, engine, args[1], depth + 1);
        const actor_node = store.get(actor_id_val);
        if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
        const actor_id_lit = store.lits.items[actor_node.aux];
        if (actor_id_lit != .int) return error.ActorIdNotLiteral;
        const actor_ptr = engine.actors.getPtr(@intCast(actor_id_lit.int)) orelse return error.ActorNotFound;
        const handler_node = store.get(actor_ptr.handler);

        if (handler_node.tag == .sym) {
            const handler_name = store.interner.resolve(handler_node.payload);
            if (engine.fns.get(handler_name)) |fn_def| {
                if (fn_def.num_clauses > 0) {
                    const clause = fn_def.clauses[0];

                    // CORRECTION : Créer un nouvel environnement isolé pour l'acteur
                    var new_env = Env.init(env.allocator);
                    defer new_env.deinit();
                    var it = env.bindings.iterator();
                    while (it.next()) |entry| {
                        try new_env.put(entry.key_ptr.*, entry.value_ptr.*);
                    }

                    if (clause.num_patterns >= 1) {
                        const p1 = store.get(clause.patterns[0]);
                        if (p1.tag == .sym) try new_env.put(p1.payload, actor_ptr.state);
                    }
                    if (clause.num_patterns >= 2) {
                        const p2 = store.get(clause.patterns[1]);
                        if (p2.tag == .sym) try new_env.put(p2.payload, msg_val);
                    }
                    const new_state = try evaluate(store, &new_env, engine, clause.body, depth + 1);
                    // platform.debug.print("[DEBUG SEND] handler evaluated to: {d}\n", .{new_state});
                    actor_ptr.state = new_state;
                    // platform.debug.print("[DEBUG SEND] actor state updated to: {d}\n", .{actor_ptr.state});
                    return new_state;
                }
            }
        } else if (handler_node.tag == .lambda) {
            var new_env = Env.init(env.allocator);
            defer new_env.deinit();
            var it = env.bindings.iterator();
            while (it.next()) |entry| {
                try new_env.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            var current_handler = actor_ptr.handler;
            const args_to_bind = [_]Id{ actor_ptr.state, msg_val };
            for (args_to_bind) |arg_val| {
                const h_node = store.get(current_handler);
                if (h_node.tag == .lambda) {
                    try new_env.put(h_node.payload, arg_val);
                    const body_span = h_node.span_a.slice(store.pool.items);
                    if (body_span.len > 0) current_handler = body_span[0];
                }
            }
            const new_state = try evaluate(store, &new_env, engine, current_handler, depth + 1);
            actor_ptr.state = new_state;
            return new_state;
        }
        return error.HandlerFailed;
    }
    if (std.mem.eql(u8, op, "state")) {
        if (args.len != 1) return error.ArityMismatch;
        const actor_id_val = try evaluate(store, env, engine, args[0], depth + 1);
        const actor_node = store.get(actor_id_val);
        if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
        const actor_id_lit = store.lits.items[actor_node.aux];
        if (actor_id_lit != .int) return error.ActorIdNotLiteral;
        const actor_ptr = engine.actors.getPtr(@intCast(actor_id_lit.int)) orelse return error.ActorNotFound;
        // platform.debug.print("[DEBUG STATE] returning state: {d}\n", .{actor_ptr.state});
        return actor_ptr.state;
    }

    // ═══ 3. EFFETS ALGÉBRIQUES : perform et handle ═══
    if (std.mem.eql(u8, op, "perform")) {
        // Si on est en mode "green" (profiling), on compte l'effet
        if (engine.green_mode) {
            engine.green_call_count += 1;
        }
        // Un perform retourne simplement son argument (le calcul évalué)
        if (args.len > 1) return evaluate(store, env, engine, args[1], depth + 1);
        return args[0];
    }

    if (std.mem.eql(u8, op, "handle")) {
        // handle(body, handler)
        // Pour le profiling, on active le mode green pendant l'évaluation du corps
        const old_mode = engine.green_mode;
        engine.green_mode = true;
        engine.green_call_count = 0;

        const result = try evaluate(store, env, engine, args[0], depth + 1);

        engine.green_mode = old_mode;
        // On retourne le résultat (le compteur est stocké dans engine.green_call_count)
        return result;
    }

    // ═══ 5. OPÉRATEURS ARITHMÉTIQUES ═══
    if (args.len == 0) return error.ArityMismatch;
    if (std.mem.eql(u8, op, "!")) {
        if (args.len != 1) return error.ArityMismatch;
        const a = try evaluate(store, env, engine, args[0], depth + 1);
        return evalUnary(store, a, .not);
    }
    if (args.len != 2) return error.ArityMismatch;
    const a = try evaluate(store, env, engine, args[0], depth + 1);
    const b = try evaluate(store, env, engine, args[1], depth + 1);

    // Gérer à la fois les noms natifs (+, *) et lowered (add, mul)
    if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "add")) return evalBinary(store, a, b, .add);
    if (std.mem.eql(u8, op, "-") or std.mem.eql(u8, op, "sub")) return evalBinary(store, a, b, .sub);
    if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "mul")) return evalBinary(store, a, b, .mul);
    if (std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "div")) return evalBinary(store, a, b, .div);
    if (std.mem.eql(u8, op, "%") or std.mem.eql(u8, op, "mod")) return evalBinary(store, a, b, .mod);
    if (std.mem.eql(u8, op, "&") or std.mem.eql(u8, op, "and")) return evalBinary(store, a, b, .and_op);
    if (std.mem.eql(u8, op, "|") or std.mem.eql(u8, op, "or")) return evalBinary(store, a, b, .or_op);
    if (std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "eq")) return evalCmp(store, a, b, .eq);
    if (std.mem.eql(u8, op, "!=") or std.mem.eql(u8, op, "neq")) return evalCmp(store, a, b, .neq);
    if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, "lt")) return evalCmp(store, a, b, .lt);
    if (std.mem.eql(u8, op, ">") or std.mem.eql(u8, op, "gt")) return evalCmp(store, a, b, .gt);
    if (std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, "le")) return evalCmp(store, a, b, .le);
    if (std.mem.eql(u8, op, ">=") or std.mem.eql(u8, op, "ge")) return evalCmp(store, a, b, .ge);

    return error.UnknownSymbol;
}

const BinOp = enum { add, sub, mul, div, mod, and_op, or_op };
const CmpOp = enum { eq, neq, lt, gt, le, ge };

fn evalBinary(store: *Store, a: Id, b: Id, op: BinOp) EvalError!Id {
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != .lit or nb.tag != .lit) return error.TypeError;
    const la = store.lits.items[na.aux];
    const lb = store.lits.items[nb.aux];

    const result_lit: expr.Lit = switch (la) {
        .int => |va| switch (lb) {
            .int => |vb| switch (op) {
                .add => .{ .int = va + vb },
                .sub => .{ .int = va - vb },
                .mul => .{ .int = va * vb },
                .div => if (vb == 0) return error.DivisionByZero else .{ .int = @divTrunc(va, vb) },
                .mod => if (vb == 0) return error.DivisionByZero else .{ .int = @mod(va, vb) },
                .and_op, .or_op => return error.TypeError,
            },
            else => return error.TypeError,
        },
        .boolean => |va| switch (lb) {
            .boolean => |vb| switch (op) {
                .and_op => .{ .boolean = va and vb },
                .or_op => .{ .boolean = va or vb },
                else => return error.TypeError,
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    };

    return store.addNode(.{
        .tag = .lit,
        .payload = 0,
        .aux = try store.addLit(result_lit),
        .span_a = Span.EMPTY,
        .span_b = Span.EMPTY,
    });
}

fn evalUnary(store: *Store, a: Id, op: enum { not }) EvalError!Id {
    _ = op;
    const na = store.get(a);
    if (na.tag != .lit) return error.TypeError;
    const la = store.lits.items[na.aux];
    if (la != .boolean) return error.TypeError;
    return store.addNode(.{
        .tag = .lit,
        .payload = 0,
        .aux = try store.addLit(.{ .boolean = !la.boolean }),
        .span_a = Span.EMPTY,
        .span_b = Span.EMPTY,
    });
}

fn evalCmp(store: *Store, a: Id, b: Id, op: CmpOp) EvalError!Id {
    const na = store.get(a);
    const nb = store.get(b);
    if (na.tag != .lit or nb.tag != .lit) return error.TypeError;
    const la = store.lits.items[na.aux];
    const lb = store.lits.items[nb.aux];

    const result = switch (la) {
        .int => |va| switch (lb) {
            .int => |vb| switch (op) {
                .eq => va == vb,
                .neq => va != vb,
                .lt => va < vb,
                .gt => va > vb,
                .le => va <= vb,
                .ge => va >= vb,
            },
            else => return error.TypeError,
        },
        else => return error.TypeError,
    };

    return store.addNode(.{
        .tag = .lit,
        .payload = 0,
        .aux = try store.addLit(.{ .boolean = result }),
        .span_a = Span.EMPTY,
        .span_b = Span.EMPTY,
    });
}

test "engine rejects non-lowered frontend expressions" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.init(allocator, &store, &env);
    defer engine.deinit();

    const x = try engine.store.sym("x");
    const zero = try engine.store.int(0);
    const frontend = try engine.store.binop("quote", x, zero);

    try std.testing.expectError(
        error.ExtensionNotLowered,
        engine.eval(frontend),
    );
}

test "engine evaluates lowered expression" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.init(allocator, &store, &env);
    defer engine.deinit();

    const x = try engine.store.int(2);
    const y = try engine.store.int(3);
    const frontend = try engine.store.binop("+", x, y);
    const lowered = try engine.store.lowerRec(frontend);
    try engine.store.assertCoreExpr(lowered);
    _ = try engine.eval(lowered);
}
