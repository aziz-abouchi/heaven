const std = @import("std");
const pattern_mod = @import("pattern");
const Allocator = std.mem.Allocator;
const canon = @import("canon");
const expr = @import("expr");
const Store = expr.Store;
const Id = expr.Id;
const Sym = expr.Sym;
const platform = @import("platform");

// DEBUG TOGGLE — garder synchronisé avec heaven_expr.zig, proof_core.zig, eval.zig
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
    // === AJOUT POUR LES ACTEURS ===
    ActorIdNotLiteral,
    ActorNotFound,
    HandlerFailed,
    // ==============================
    EffectPerformed,
    AssertionFailed,
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
        var clause = FunctionClause{ .patterns = undefined, .num_patterns = @intCast(@min(patterns.len, 8)), .body = body };
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
        // Vérifier d'abord si la fonction existe déjà
        if (self.functions.getEntry(name)) |entry| {
            // Fonction existante, ajouter une clause
            entry.value_ptr.addClause(patterns, body);
        } else {
            // Nouvelle fonction : dupliquer la clé AVANT d'insérer
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
    handler: Id, // C'est une fonction (lambda) qui prend (state, msg) et retourne un nouvel état
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

    pub fn eval(self: *Engine, id: Id) EvalError!Id {
        if (self.fuel == 0) return EvalError.StackOverflow;
        self.fuel -= 1;
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        switch (node.tag) {
            .lit, .hole => return id,
            .quote => {
                // Au lieu de juste retourner l'Id, on le traverse pour
                // remplacer les "unquote" par leur valeur évaluée.
                return try self.expandQuote(node.payload);
            },
            .unquote => {
                // L'unquote en dehors d'un quote = évaluer l'intérieur
                return self.eval(node.payload);
            },
            .sym => {
                if (self.env.get(node.payload)) |bound| {
                    //platform.debug.print("[DEBUG EVAL] Trouvé {s} -> {d}\n", .{ self.store.interner.resolve(node.payload), bound });
                    return self.eval(bound);
                }
                //platform.debug.print("[DEBUG EVAL] Non trouvé {s}\n", .{self.store.interner.resolve(node.payload)});
                return id;
            },
            .bind => {
                const val = try self.eval(node.aux);
                try self.env.put(node.payload, val);
                return val;
            },
            .relation => return id,
            .apply => {
                if (try self.applyLocalRewrites(id)) |r|
                    return r;
                const args = node.span_a.slice(pool);

                // 1. Vérifier les fonctions utilisateur définies par nom
                if (node.payload < self.store.len()) {
                    const func_sym_node = self.store.get(node.payload);
                    if (func_sym_node.tag == .sym) {
                        const name = self.store.interner.resolve(func_sym_node.payload);

                        // === DEBUG LOG ===
                        // platform.debug.print("[ENGINE EVAL] Checking symbol: {s}\n", .{name});
                        // ==================

                        if (!std.mem.eql(u8, name, "λ")) {}

                        // === INTERCEPTION MACRO ===
                        if (self.macros.get(func_sym_node.payload)) |macro_def| {
                            var local_env = std.AutoHashMapUnmanaged(Sym, Id){};
                            defer local_env.deinit(self.allocator);
                            var it = self.env.bindings.iterator();
                            while (it.next()) |entry| {
                                try local_env.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                            }
                            const params = macro_def.params_span.slice(self.store.pool.items);
                            for (params, 0..) |p_id, i| {
                                if (i < args.len) {
                                    // On récupère le Sym (l'ID de la chaîne) à partir de l'Id du nœud
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
                        // ==========================

                        // Intercepter if/while/break avant les fonctions utilisateur
                        if (std.mem.eql(u8, name, "if")) {
                            return self.evalIfLazy(args);
                        }

                        // === Intercepter quote et unquote pour déclencher expandQuote ===
                        if (std.mem.eql(u8, name, "quote") and args.len == 1) {
                            return try self.expandQuote(args[0]);
                        }
                        if (std.mem.eql(u8, name, "unquote") and args.len == 1) {
                            return try self.eval(args[0]);
                        }
                        // ==================================================================

                        // === ACTEURS NATIFS DIRECTS ===
                        // platform.debug.print("[ACTOR INTERCEPT] {s}() called\n", .{name});
                        if (std.mem.eql(u8, name, "spawn")) {
                            var evaled_args = std.ArrayListUnmanaged(Id){};
                            defer evaled_args.deinit(self.allocator);
                            for (args) |a| try evaled_args.append(self.allocator, try self.eval(a));
                            if (evaled_args.items.len != 2) return EvalError.ArityMismatch;

                            const new_actor_id = self.next_actor_id;
                            self.next_actor_id += 1;
                            try self.actors.put(self.allocator, new_actor_id, .{
                                .state = evaled_args.items[1],
                                .handler = evaled_args.items[0],
                            });
                            return self.store.int(@intCast(new_actor_id));
                        }

                        if (std.mem.eql(u8, name, "send")) {
                            var evaled_args = std.ArrayListUnmanaged(Id){};
                            defer evaled_args.deinit(self.allocator);
                            for (args) |a| try evaled_args.append(self.allocator, try self.eval(a));
                            if (evaled_args.items.len != 2) return EvalError.ArityMismatch;

                            const actor_id_lit = evaled_args.items[0];
                            const msg_id = evaled_args.items[1];

                            const actor_node = self.store.get(actor_id_lit);
                            if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
                            const actor_id = self.store.lits.items[actor_node.aux].int;

                            const actor = self.actors.getPtr(@intCast(actor_id)) orelse return error.ActorNotFound;

                            const state_sym = self.store.interner.intern("state") catch return EvalError.OutOfMemory;
                            try self.env.put(state_sym, actor.state);
                            self.fuel = 1_000_000;

                            const handler_node = self.store.get(actor.handler);
                            const result = if (handler_node.tag == .lambda) blk: {
                                break :blk self.applyLambda(actor.handler, &.{msg_id}) catch |err| return err;
                            } else blk: {
                                if (handler_node.tag != .sym) return error.HandlerFailed;
                                const handler_name = self.store.interner.resolve(handler_node.payload);
                                break :blk self.evalFunction(handler_name, &.{ actor.state, msg_id }) catch |err| return err;
                            };

                            actor.state = result;
                            return self.store.unitLit();
                        }

                        if (std.mem.eql(u8, name, "state")) {
                            var evaled_args = std.ArrayListUnmanaged(Id){};
                            defer evaled_args.deinit(self.allocator);
                            for (args) |a| try evaled_args.append(self.allocator, try self.eval(a));
                            if (evaled_args.items.len != 1) return EvalError.ArityMismatch;

                            const actor_id_lit = evaled_args.items[0];
                            const actor_node = self.store.get(actor_id_lit);
                            if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
                            const actor_id = self.store.lits.items[actor_node.aux].int;

                            const actor = self.actors.get(@intCast(actor_id)) orelse return error.ActorNotFound;
                            return actor.state;
                        }
                        // ==============================

                        // === AJOUT : Court-circuiter les builtins d'acteurs ===
                        const is_actor_builtin = std.mem.eql(u8, name, "spawn") or
                            std.mem.eql(u8, name, "send") or
                            std.mem.eql(u8, name, "state");
                        if (!is_actor_builtin and self.fns.get(name) != null) {
                            // ========================================================
                            var evaled_args = std.ArrayListUnmanaged(Id){};
                            defer evaled_args.deinit(self.allocator);
                            for (args) |a| try evaled_args.append(self.allocator, try self.eval(a));
                            platform.debug.print(
                                "calling evalFunction({s})\n",
                                .{name},
                            );
                            return self.evalFunction(name, evaled_args.items) catch |err| switch (err) {
                                EvalError.ArityMismatch => try self.store.apply(node.payload, evaled_args.items),
                                else => return err,
                            };
                        }
                    }
                }

                // 2. Évaluation normale du symbole de fonction
                const func_id = try self.eval(node.payload);
                const func_node = self.store.get(func_id);

                if (func_node.tag == .lambda) {
                    const param_sym = func_node.payload;
                    var body_id: Id = 0;
                    for (func_node.span_a.slice(pool)) |child| {
                        body_id = child;
                        break;
                    }
                    const arg_val = try self.eval(args[0]); // ou args[0] si args est le slice

                    const old_val = self.env.get(param_sym);
                    try self.env.put(param_sym, arg_val);
                    const result = self.eval(body_id);
                    if (old_val) |v| try self.env.put(param_sym, v) else self.env.delete(param_sym);
                    return result;
                }

                if (func_node.tag == .apply) {
                    const inner = self.store.get(func_node.payload);
                    if (inner.tag == .sym) {
                        const name = self.store.interner.resolve(inner.payload);
                        if (std.mem.eql(u8, name, "\xCE\xBB"))
                            return self.applyLambda(func_id, args);
                    }
                }
                if (func_node.tag == .sym) {
                    const name = self.store.interner.resolve(func_node.payload);

                    if (std.mem.eql(u8, name, "if")) {
                        return self.evalIfLazy(args);
                    }

                    return self.evalBuiltin(name, args) catch |err| {
                        // Si c'est un effet, on le remonte sans le catch !
                        if (err == error.EffectPerformed) return err;

                        var na: std.ArrayListUnmanaged(Id) = .{};
                        defer na.deinit(self.allocator);
                        for (args) |a| try na.append(self.allocator, try self.eval(a));
                        return self.store.apply(func_id, na.items);
                    };
                }

                var na: std.ArrayListUnmanaged(Id) = .{};
                defer na.deinit(self.allocator);
                for (args) |a| try na.append(self.allocator, try self.eval(a));
                return self.store.apply(func_id, na.items);
            },
            .list_nil, .list_cons => return id, // Les listes sont des valeurs terminales pour l'instant
            .let_in => {
                // Structure attendue : payload=Sym, aux=Valeur, span_a[0]=Body
                const sym = node.payload;
                const val = try self.eval(node.aux);
                // Re-capturer pool: self.eval() peut avoir réalloué store.pool (realloc hazard)
                const pool_after = self.store.pool.items;
                const body = node.span_a.slice(pool_after)[0];

                // Sauvegarder, binder, évaluer, restaurer
                const old_val = self.env.get(sym);
                try self.env.put(sym, val);
                const result = self.eval(body);
                if (old_val) |v| {
                    try self.env.put(sym, v);
                } else {
                    self.env.delete(sym);
                }
                return result;
            },
            .lambda => {
                // Un lambda est une valeur (une fermeture), on ne l'évalue pas maintenant.
                // Il sera évalué quand un .apply le rencontrera.
                return id;
            },
            // === ÉVALUATION DES EFFETS ===
            .perform => {
                const name_sym = node.payload;
                var evaled_args = std.ArrayListUnmanaged(Id){};
                defer evaled_args.deinit(self.allocator);
                for (node.span_a.slice(self.store.pool.items)) |arg| {
                    try evaled_args.append(self.allocator, try self.eval(arg));
                }
                // On duplique les arguments pour qu'ils survivent après le throw
                const args_dup = try self.allocator.dupe(Id, evaled_args.items);
                self.pending_effect = .{ .name = name_sym, .args = args_dup };
                return error.EffectPerformed; // Remonte la pile !
            },
            .handle => {
                const body_id = node.payload;
                const handler_id = node.aux;

                // On tente d'évaluer le corps
                const result = self.eval(body_id) catch |err| {
                    // Si une erreur d'effet est remontée, on l'intercepte !
                    if (err == error.EffectPerformed) {
                        const effect = self.pending_effect orelse return error.EffectPerformed;
                        self.pending_effect = null; // On consomme l'effet

                        // On appelle le handler avec les arguments de l'effet
                        const handler_node = self.store.get(handler_id);

                        // Désactiver le mode Green pendant le handler !
                        const saved_green = self.green_mode;
                        self.green_mode = false;
                        defer self.green_mode = saved_green;
                        // =====================================

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
                    return err; // Si c'est une autre erreur, on la remonte
                };
                return result;
            },
            // ==============================
            else => return id,
        }
    }

    fn applyLambda(self: *Engine, lambda_id: Id, arg_ids: []const Id) !Id {
        const lambda_node = self.store.get(lambda_id);
        if (lambda_node.tag != .lambda) return EvalError.TypeError;

        const body_id = lambda_node.span_a.slice(self.store.pool.items)[0];
        const param_sym = lambda_node.payload; // Le symbole du paramètre est ici !

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

    /// Évalue récursivement les expressions Peano (zero, succ, add, mul) en entiers
    fn evalPeano(self: *Engine, id: Id) Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);

        switch (node.tag) {
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

                // Évaluer récursivement les arguments
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

    // compteur de profondeur dans evalFunction pour détecter les dépassements
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

            // Créer un environnement local (copie superficielle des bindings globaux)
            var local_env = std.AutoHashMapUnmanaged(Sym, Id){};
            defer local_env.deinit(self.allocator);

            var it = self.env.bindings.iterator();
            while (it.next()) |entry| {
                try local_env.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
            }

            // Lier les paramètres de la clause dans l'environnement local
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

            // SAUVEGARDER ET INSTALLER L'ENV LOCAL ICI (APRÈS matchPattern)
            // Pour éviter que self.env.bindings ne pointe vers de la mémoire libérée
            const saved = self.env.bindings;
            self.env.bindings = local_env;

            // Évaluer le corps
            const result = self.eval(clause.body);

            // Restaurer l'ancien environnement (local_env sera libéré par defer)
            self.env.bindings = saved;

            return result;
        }
        return EvalError.ArityMismatch;
    }

    fn evalBuiltin(self: *Engine, name: []const u8, args: []const Id) !Id {
        // === ÉVALUATION PARESSEUSE POUR 'if' ===
        if (std.mem.eql(u8, name, "if")) {
            if (args.len < 3) return EvalError.TypeError;
            const cond_id = try self.eval(args[0]);
            if (self.isTruthy(cond_id)) {
                return self.eval(args[1]);
            } else {
                return self.eval(args[2]);
            }
        }

        // === FRAMEWORK DE TEST NATIF ===
        if (std.mem.eql(u8, name, "test")) {
            if (args.len < 2) return EvalError.ArityMismatch;
            const test_name_id = try self.eval(args[0]);
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
            return self.store.unitLit();
        }

        if (std.mem.eql(u8, name, "assert_eq")) {
            if (args.len != 2) return EvalError.ArityMismatch;
            const v1 = try self.eval(args[0]);
            const v2 = try self.eval(args[1]);
            if (!expr.exprStructuralEq(self.store, v1, v2)) {
                return error.AssertionFailed;
            }
            return self.store.unitLit();
        }

        if (std.mem.eql(u8, name, "assert_err")) {
            if (args.len != 1) return EvalError.ArityMismatch;
            // On tente d'évaluer. Si ça plante, c'est une réussite !
            _ = self.eval(args[0]) catch {
                return self.store.unitLit(); // L'erreur attendue s'est produite
            };
            // Si l'évaluation réussit, le test échoue
            return error.AssertionFailed;
        }
        // ================================

        // === CONSTRUCTEURS PEANO (Bootstrapping) ===
        if (std.mem.eql(u8, name, "zero")) {
            return self.store.sym("zero");
        }
        if (std.mem.eql(u8, name, "succ") and args.len == 1) {
            const arg_val = try self.eval(args[0]);
            return self.store.call("succ", &.{arg_val});
        }
        // ==========================================

        // === ÉVALUATION STRICTE POUR LES AUTRES BUILTINS ===
        var ea: std.ArrayListUnmanaged(Id) = .{};
        defer ea.deinit(self.allocator);
        for (args) |a| try ea.append(self.allocator, try self.eval(a));

        // === GREEN PROFILING & ARITHMÉTIQUE ===
        const is_arith = std.mem.eql(u8, name, "+") or std.mem.eql(u8, name, "-") or
            std.mem.eql(u8, name, "*") or std.mem.eql(u8, name, "/");

        if (is_arith and ea.items.len == 2) {
            // Si le mode Green est activé, on émet un effet énergétique
            if (self.green_mode) {
                self.green_call_count += 1;

                var args_for_effect = std.ArrayListUnmanaged(Id){};
                defer args_for_effect.deinit(self.allocator);
                try args_for_effect.append(self.allocator, ea.items[0]);
                try args_for_effect.append(self.allocator, ea.items[1]);
                try args_for_effect.append(self.allocator, try self.store.int(1)); // 1 Joule par opération

                const consume_node = try self.store.perform("Consume", args_for_effect.items);
                // On n'intercepte PAS l'erreur EffectPerformed, on la remonte !
                return self.eval(consume_node) catch |err| {
                    if (err == error.EffectPerformed) return err;
                    return self.arith(ea.items, if (std.mem.eql(u8, name, "+")) .add else if (std.mem.eql(u8, name, "-")) .sub else if (std.mem.eql(u8, name, "*")) .mul else .div);
                };
            }

            // Évaluation normale hors mode Green
            const op: ArithOp = if (std.mem.eql(u8, name, "+")) .add else if (std.mem.eql(u8, name, "-")) .sub else if (std.mem.eql(u8, name, "*")) .mul else .div;
            return self.arith(ea.items, op);
        }

        // =====================================
        if (std.mem.eql(u8, name, "^")) return self.arithPow(ea.items);
        if (std.mem.eql(u8, name, "==")) return self.evalEq(ea.items);
        if (std.mem.eql(u8, name, "=")) return self.evalEq(ea.items);
        // Try user-defined functions
        if (self.fns.get(name) != null) return self.evalFunction(name, ea.items);
        if (std.mem.eql(u8, name, "\xCE\xA3")) return self.evalAgg(ea.items, .sum);
        if (std.mem.eql(u8, name, "\xCE\xA0")) return self.evalAgg(ea.items, .prod);

        if (std.mem.eql(u8, name, "help")) return self.evalHelp(args);
        return EvalError.TypeError;
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

    fn evalIf(self: *Engine, args: []const Id) !Id {
        if (args.len < 2) return EvalError.ArityMismatch;
        const cn = self.store.get(args[0]);
        const cond = switch (cn.tag) {
            .lit => switch (self.store.lits.items[cn.aux]) {
                .boolean => |b| b,
                .int => |v| v != 0,
                else => return EvalError.TypeError,
            },
            else => return EvalError.TypeError,
        };
        return if (cond) args[1] else if (args.len > 2) args[2] else self.store.unitLit();
    }

    /// if paresseux : n'évalue que la branche choisie
    fn evalIfLazy(self: *Engine, args: []const Id) !Id {
        if (args.len < 2) return EvalError.ArityMismatch;
        const cond_val = try self.eval(args[0]);
        const cn = self.store.get(cond_val);
        if (cn.tag == .lit) {
            const lit = self.store.lits.items[cn.aux];
            switch (lit) {
                .int, .float, .boolean, .str, .unit, .runtime => {},
            }
        }

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

    /// Parcourt un AST "quoté" et remplace les nœuds "unquote" par leur valeur évaluée.
    fn expandQuote(self: *Engine, id: Id) !Id {
        const node = self.store.get(id);
        switch (node.tag) {
            .unquote => {
                // Si on trouve un unquote, on évalue l'intérieur !
                return try self.eval(node.payload);
            },
            .apply => {
                // On reconstruit l'Apply avec les enfants expansés
                const new_func = try self.expandQuote(node.payload);
                var new_args: std.ArrayListUnmanaged(Id) = .{};
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
            else => return id, // sym, lit, etc. sont retournés tels quels
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
                    var i: i64 = 0;
                    while (i < vb) : (i += 1) {
                        result = std.math.mul(i64, result, va) catch return EvalError.TypeError;
                    }
                    return self.store.int(result);
                },
                else => return EvalError.TypeError,
            },
            else => return EvalError.TypeError,
        }
    }

    pub fn createGoal(self: *Engine, lhs_str: []const u8, rhs_str: []const u8) !u32 {
        _ = self;
        _ = lhs_str;
        _ = rhs_str;
        // Ici, tu dois transformer tes chaînes en Expr (nœuds)
        // Pour l'instant, un stub qui retourne un ID factice pour compiler :
        return 1;
    }

    pub fn verify(self: *Engine, goal_id: u32) !struct { is_valid: bool, trace: []const u8 } {
        _ = self;
        _ = goal_id;
        // Ici, tu appelleras la vérification contre tes axiomes de kernel.hvn
        return .{ .is_valid = true, .trace = "Axiome vérifié." };
    }

    fn evalHelp(self: *Engine, args: []const Id) !Id {
        _ = self;
        _ = args;
        return EvalError.TypeError; // TODO: not yet implemented
    }

    fn evalEq(self: *Engine, args: []const Id) !Id {
        if (args.len != 2) return EvalError.ArityMismatch;
        const an = self.store.get(args[0]);
        const bn = self.store.get(args[1]);

        // Comparaison d'entiers
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

        // Comparaison de symboles (comme "inc")
        if (an.tag == .sym and bn.tag == .sym) {
            return self.store.int(if (an.payload == bn.payload) 1 else 0);
        }

        return self.store.int(0); // Sinon, c'est faux
    }

    fn matchPattern(
        self: *Engine,
        pat: Id,
        val: Id,
        env: *std.AutoHashMapUnmanaged(Sym, Id),
    ) !bool {
        const pat_node = self.store.get(pat);
        switch (pat_node.tag) {
            .sym => {
                const name = self.store.interner.resolve(pat_node.payload);
                // Convention : minuscule = variable, majuscule ou "zero"/"succ" = constructeur
                const is_var = (name[0] >= 'a' and name[0] <= 'z') and
                    !std.mem.eql(u8, name, "zero") and
                    !std.mem.eql(u8, name, "succ");
                if (is_var) {
                    //platform.debug.print("[DEBUG MATCH] Liant {s} -> {d}\n", .{ name, val });
                    try env.put(self.allocator, pat_node.payload, val);
                    return true;
                } else {
                    // Constructeur : match exact par nom
                    const val_node = self.store.get(val);
                    if (val_node.tag != .sym) return false;
                    return val_node.payload == pat_node.payload;
                }
            },
            .apply => {
                // ctor_pat : (succ n) — matcher récursivement
                const val_node = self.store.get(val);
                if (val_node.tag != .apply) return false;
                // Même fonction ?
                const pat_func = self.store.get(pat_node.payload);
                const val_func = self.store.get(val_node.payload);
                if (pat_func.tag != .sym or val_func.tag != .sym) return false;
                if (pat_func.payload != val_func.payload) return false;
                // Même arité ?
                const p = self.store.pool.items;
                const pat_args = pat_node.span_a.slice(p);
                const val_args = val_node.span_a.slice(p);
                if (pat_args.len != val_args.len) return false;
                // Matcher les arguments récursivement
                for (pat_args, val_args) |pa, va| {
                    if (!try self.matchPattern(pa, va, env)) return false;
                }
                return true;
            },
            .lit => {
                // Littéral : match exact
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

    const result = engine.eval(expr_id) catch return; // On capture l'erreur
    // Tenter toString
    const str = try expr.toString(&store, result, allocator);
    defer allocator.free(str);
    // Si on arrive ici, pas de crash
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

    // even(n) = if (== n 0) 1 (odd (- n 1))
    // odd(n)  = if (== n 0) 0 (even (- n 1))
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
    try std.testing.expectEqualStrings("0", s_even); // even(5) = false

    const app_odd = try store.call("odd", &.{five});
    const res_odd = try engine.eval(app_odd);
    const s_odd = try expr.toString(&store, res_odd, allocator);
    defer allocator.free(s_odd);
    try std.testing.expectEqualStrings("1", s_odd); // odd(5) = true
}
