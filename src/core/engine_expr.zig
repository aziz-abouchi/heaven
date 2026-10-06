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

/// Sentinelle TCO : retournée par evalMagic quand un self-tail-call
/// est détecté. Remonte naturellement via return jusqu'à evalFunction.
const TCO_BOUNCE: Id = std.math.maxInt(Id);

/// Spine de queue d'un corps de clause : un self-call n'est un tail-call
/// QUE s'il EST le corps, ou s'il est dans une branche de if. Opérandes
/// d'opérateurs, arguments de constructeurs : positions NON-queue.
fn collectTailSpine(store: *const Store, node_id: Id, fn_name: []const u8, out: *[64]Id, out_len: *u8) void {
    if (out_len.* >= 64) return;
    const node = store.get(node_id);
    if (node.tag != .apply) return;
    const op_node = store.get(node.payload);
    if (op_node.tag != .sym) return;
    const op_name = store.interner.resolve(op_node.payload);
    if (std.mem.eql(u8, op_name, fn_name)) {
        out[out_len.*] = node_id;
        out_len.* += 1;
        return;
    }
    if (std.mem.eql(u8, op_name, "if")) {
        const args = store.applyArgs(node);
        if (args.len == 3) {
            collectTailSpine(store, args[1], fn_name, out, out_len);
            collectTailSpine(store, args[2], fn_name, out, out_len);
        }
    }
}

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
    SuspendRequested,
    TypeError,
    ArityMismatch,
    DivisionByzero,
    StackOverflow,
    OutOfMemory,
    RecursionLimitExceeded,
    ActorIdNotLiteral,
    ActorNotFound,
    ProcessNotFound,
    MailboxEmpty,
    InvalidInput,
    HandlerFailed,
    EffectPerformed,
    AssertionFailed,
    UnknownSymbol,
    UnboundVariable,
    ExtensionNotLowered,
    NotALambda,
};

pub const FunctionClause = struct {
    patterns: [8]expr.Id,
    num_patterns: u8,
    guard: ?Id = null,
    body: expr.Id,
};

pub const FunctionDef = struct {
    clauses: [16]FunctionClause,
    num_clauses: u8,
    ctor_arity: ?u8 = null, // null = fonction, sinon constructeur d'arité N

    pub fn addClause(self: *FunctionDef, patterns: []const Id, body: Id) void {
        if (self.num_clauses >= 16) return;
        var clause = FunctionClause{ .patterns = undefined, .num_patterns = @intCast(@min(patterns.len, 8)), .body = body };
        @memcpy(clause.patterns[0..clause.num_patterns], patterns[0..clause.num_patterns]);
        self.clauses[self.num_clauses] = clause;
        self.num_clauses += 1;
    }

    /// Guards : pose la garde sur la dernière clause enregistrée.
    /// (Évite de propager un paramètre à travers toute la chaîne
    /// addClause/register/registerClause et leurs appelants.)
    pub fn setLastGuard(self: *FunctionDef, g: ?Id) void {
        if (self.num_clauses == 0) return;
        self.clauses[self.num_clauses - 1].guard = g;
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

pub const HeavenVTable = struct {
    parse: *const fn (*anyopaque, []const u8) EvalError!Id,
    deriveId: *const fn (*anyopaque, []const u8, []const u8) EvalError!Id,
    simplify: *const fn (*anyopaque, []const u8) EvalError![]const u8,
    /// Appelé par evalMagic pour `(query name arg1 _ ...)`.
    /// Retourne le nombre de solutions comme Id entier.
    /// Nullable — les tests et le bootstrap peuvent la laisser null.
    kanren_query: ?*const fn (*anyopaque, *Store, []const Id) EvalError!Id = null,
};

// Vtable factice pour les tests (ne devrait jamais être appelée)
const testHeavenVTable = HeavenVTable{
    .parse = testParse,
    .deriveId = testDerive,
    .simplify = testSimplify,
};

fn testParse(_: *anyopaque, _: []const u8) EvalError!Id {
    @panic("testParse called unexpectedly");
}
fn testDerive(_: *anyopaque, _: []const u8, _: []const u8) EvalError!Id {
    @panic("testDerive called unexpectedly");
}
fn testSimplify(_: *anyopaque, _: []const u8) EvalError![]const u8 {
    @panic("testSimplify called unexpectedly");
}

pub const IOHandler = *const fn (
    store: *Store,
    label: []const u8,
    arg: ?expr.Id,
) EvalError!?expr.Id;

pub const Process = struct {
    /// File de messages en attente (FIFO). Chaque message est un Id
    /// (expression Core).
    mailbox: std.ArrayListUnmanaged(expr.Id) = .{},
    /// Prototype 2-lite : handler + state attachés au process.
    /// `spawn(fn, init)` les renseigne. `run(pid)` les consomme.
    /// `null` si le process a été créé sans handler.
    handler: ?expr.Id = null,
    state: ?expr.Id = null,

    pub fn deinit(self: *Process, allocator: std.mem.Allocator) void {
        self.mailbox.deinit(allocator);
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
    /// Prototype 1 concurrence (docs/spec/_concurrency.md) :
    /// processes légers = id -> mailbox FIFO. Pas de scheduler,
    /// pas de préemption, pas de distribution. Juste la
    /// communication pure spawn/tell/recv.
    processes: std.AutoHashMapUnmanaged(u32, Process) = .{},
    next_process_id: u32 = 0,
    green_call_count: u32 = 0,
    green_mode: bool = false,
    last_performed: ?expr.Id = null,
    io_handler: ?IOHandler = null,
    in_handle: bool = false,
    fuel: u64 = 1_000_000,
    /// Safepoint budget. Decremente a chaque appel de evaluate().
    /// A 0 -> error.SuspendRequested (abort cooperatif).
    /// Par defaut = maxInt (jamais suspendu) sauf via evalWithBudget.
    reductions: u64 = std.math.maxInt(u64),
    /// TCO : nom de la fonction courante (self-tail-call detection)
    tco_name: ?[]const u8 = null,
    /// TCO : buffer fixe pour args du self-tail-call (max 8)
    tco_args_buf: [8]Id = undefined,
    /// TCO : nombre d'args valides dans le buffer
    tco_args_len: u8 = 0,
    tco_spine_buf: [64]Id = undefined,
    tco_spine_len: u8 = 0,
    max_recursion_depth: usize = 1000,
    recursion_depth: usize = 0,
    heaven_ctx: *anyopaque,
    vtable: *const HeavenVTable,

    pub fn init(
        allocator: std.mem.Allocator,
        store: *Store,
        env: *Env,
        heaven_ctx: *anyopaque,
        vtable: *const HeavenVTable,
    ) Engine {
        return .{
            .allocator = allocator,
            .store = store,
            .env = env,
            .fns = .{},
            .fuel = 100_000,
            .heaven_ctx = heaven_ctx,
            .vtable = vtable,
        };
    }

    pub fn deinit(self: *Engine) void {
        var it = self.fns.iterator();
        while (it.next()) |entry| {
            platform.dbg("[fns.deinit] freeing key='{s}' addr={d}\n", .{ entry.key_ptr.*, @intFromPtr(entry.key_ptr.*.ptr) });
            self.allocator.free(entry.key_ptr.*);
        }

        self.fns.deinit(self.allocator);
        self.macros.deinit(self.allocator);
        self.actors.deinit(self.allocator);
        {
            var proc_it = self.processes.iterator();
            while (proc_it.next()) |entry| entry.value_ptr.deinit(self.allocator);
        }
        self.processes.deinit(self.allocator);
    }

    // Contexte factice pour les tests (ne sera jamais utilisé)
    var test_ctx_dummy: u8 = 0;

    // Fonction d'initialisation pour les tests
    pub fn initTest(allocator: std.mem.Allocator, store: *Store, env: *Env) Engine {
        return init(allocator, store, env, @ptrCast(&test_ctx_dummy), &testHeavenVTable);
    }

    pub fn eval(self: *Engine, id: Id) EvalError!Id {
        const store = self.store;
        const env = self.env;
        if (self.fuel == 0) return error.RecursionLimitExceeded;
        self.fuel -= 1;
        return evaluate(store, env, self, id, 0);
    }

    pub const EvalOutcome = union(enum) {
        done: Id,
        /// Budget epuise a un safepoint. Pas de reprise automatique
        /// (3a-3 minimal). Le caller peut relancer avec un budget
        /// plus grand, ou abandonner.
        suspended,
    };

    /// Evalue avec un budget de reductions. Si le budget est epuise,
    /// retourne `suspended` au lieu d'une erreur. Le fuel top-level
    /// n'est pas touche.
    /// Evalue avec un budget de reductions. Si le budget est epuise,
    /// retourne `suspended` au lieu d'une erreur. Le fuel top-level
    /// et les reductions sont restaures : cet appel n'affecte pas
    /// l'etat global du moteur.
    pub fn evalWithBudget(self: *Engine, id: Id, budget: u64) EvalError!EvalOutcome {
        const saved_reductions = self.reductions;
        const saved_fuel = self.fuel;
        defer {
            self.reductions = saved_reductions;
            self.fuel = saved_fuel;
        }
        self.reductions = budget;
        const result_id = self.eval(id) catch |e| switch (e) {
            error.SuspendRequested => return .suspended,
            else => return e,
        };
        return .{ .done = result_id };
    }

    /// B (2026-10-02) : premier consommateur du safepoint.
    /// Relance l'evaluation avec un budget croissant jusqu'a
    /// completion ou epuisement du budget maximal. Modele
    /// redemarrable : chaque tentative repart du debut (pas de
    /// reprise exacte). Valide uniquement pour du calcul pur.
    ///
    /// Retourne l'Id du resultat, ou null si le budget maximal
    /// est atteint sans terminer.
    pub fn evalWithRetry(
        self: *Engine,
        id: Id,
        initial_budget: u64,
        max_budget: u64,
    ) EvalError!?Id {
        // Cas trivial : si max_budget == 0, on ne peut rien faire.
        if (max_budget == 0) return null;
        var budget = initial_budget;
        var attempt: u32 = 0;
        while (attempt < 64) : (attempt += 1) {
            const outcome = try self.evalWithBudget(id, budget);
            switch (outcome) {
                .done => |result_id| return result_id,
                .suspended => {
                    if (budget >= max_budget) return null;
                    // Growth strict : evite la boucle infinie quand
                    // budget == 0 (0 * 2 == 0). On ajoute 1 pour
                    // garantir une progression.
                    const next = @max(budget * 2, budget + 1);
                    budget = @min(next, max_budget);
                },
            }
        }
        return null;
    }

    pub fn evalFunction(self: *Engine, caller_env: *Env, name: []const u8, args: []const Id) EvalError!Id {
        const store = self.store;
        const fn_def = self.fns.get(name) orelse return error.UnknownSymbol;
        if (fn_def.num_clauses == 0) return error.UnknownSymbol;

        // Snapshot args AVANT toute évaluation récursive.
        const args_snap = try self.store.snapshotArgs(self.allocator, args);
        defer self.allocator.free(args_snap);

        // Buffer fixe pour current_args (max 8)
        var current_args_buf: [8]Id = undefined;
        const current_args_len = @min(args_snap.len, 8);
        for (args_snap[0..current_args_len], 0..) |a_, i_| {
            current_args_buf[i_] = try evaluate(store, caller_env, self, a_, 0);
        }

        // ─── TCO : sauvegarder / restaurer le contexte ───
        const old_tco_name = self.tco_name;
        const old_tco_buf = self.tco_args_buf;
        const old_tco_len = self.tco_args_len;
        const old_tco_spine_buf = self.tco_spine_buf;
        const old_tco_spine_len = self.tco_spine_len;
        self.tco_name = name;
        self.tco_args_len = 0;
        self.tco_spine_len = 0;
        defer {
            self.tco_name = old_tco_name;
            self.tco_args_buf = old_tco_buf;
            self.tco_args_len = old_tco_len;
            self.tco_spine_buf = old_tco_spine_buf;
            self.tco_spine_len = old_tco_spine_len;
        }

        var new_env = Env.init(self.allocator);
        defer new_env.deinit();

        // Copier caller_env UNE SEULE FOIS avant la boucle TCO
        {
            var it = caller_env.bindings.iterator();
            while (it.next()) |entry| {
                try new_env.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        tco_loop: while (true) {
            self.tco_args_len = 0;

            for (fn_def.clauses[0..fn_def.num_clauses]) |clause| {
                if (current_args_len != clause.num_patterns) continue;

                // Tracker les bindings ajoutés par le pattern (pour nettoyage TCO)
                var bound_syms: [8]Sym = undefined;
                var bound_count: u8 = 0;

                var matched = true;
                for (clause.patterns[0..clause.num_patterns], 0..) |p, i| {
                    if (std.mem.eql(u8, name, "id2")) {
                        platform.dbg("[ho-dbg] clause id2 : num_patterns={d} current_args={d}\n", .{ clause.num_patterns, current_args_len });
                    }
                    const arg_val = current_args_buf[i]; // déjà évalué
                    const p_node = store.get(p);

                    if (p_node.tag == .hole or p_node.tag == .evar) {
                        continue;
                    }
                    if (p_node.tag == .sym) {
                        const p_name = store.interner.resolve(p_node.payload);
                        if (self.fns.get(p_name)) |pfn| {
                            if (pfn.ctor_arity) |arity| {
                                const a_node = store.get(arg_val);
                                if (arity == 0) {
                                    if (a_node.tag != .sym or a_node.payload != p_node.payload) {
                                        matched = false;
                                        break;
                                    }
                                } else {
                                    matched = false;
                                    break;
                                }
                                continue;
                            }
                        }
                        try new_env.put(p_node.payload, arg_val);
                        if (std.mem.eql(u8, name, "id2")) {
                            const bn = store.get(arg_val);
                            platform.dbg("[ho-dbg] binding f <- tag={s}\n", .{@tagName(bn.tag)});
                        }
                if (bound_count < 8) {
                    bound_syms[bound_count] = p_node.payload;
                    bound_count += 1;
                }
                    } else if (p_node.tag == .lit) {
                        const arg_node = store.get(arg_val);
                        if (arg_node.tag != .lit or !store.lits.items[p_node.aux].eql(store.lits.items[arg_node.aux])) {
                            matched = false;
                            break;
                        }
                    } else if (p_node.tag == .apply) {
                        const p_args = store.spanSliceConst(p_node.span_a);
                        const a_node = store.get(arg_val);
                        if (a_node.tag != .apply) {
                            matched = false;
                            break;
                        }
                        const a_args = store.spanSliceConst(a_node.span_a);
                        if (p_args.len != a_args.len) {
                            matched = false;
                            break;
                        }
                        for (p_args, a_args, 0..) |pp, aa, arg_idx| {
                            if (arg_idx == 0) {
                                if (!pattern_mod.exprStructuralEq(store, pp, aa)) {
                                    matched = false;
                                    break;
                                }
                                continue;
                            }
                            const pp_node = store.get(pp);
                            if (pp_node.tag == .hole or pp_node.tag == .evar) {
                                continue;
                            }
                            if (pp_node.tag == .sym) {
                                const pp_name = store.interner.resolve(pp_node.payload);
                                if (self.fns.get(pp_name)) |sub_def| {
                                    if (sub_def.ctor_arity != null) {
                                        if (!pattern_mod.exprStructuralEq(store, pp, aa)) {
                                            matched = false;
                                            break;
                                        }
                                        continue;
                                    }
                                }
                                try new_env.put(pp_node.payload, aa);
                        if (bound_count < 8) {
                            bound_syms[bound_count] = pp_node.payload;
                            bound_count += 1;
                        }
                            } else if (!pattern_mod.exprStructuralEq(store, pp, aa)) {
                                matched = false;
                                break;
                            }
                        }
                    }
                }

                if (matched) {
                    // ─── Guard : clause gardée (f p | cond = body) ───
                    // Évaluée dans new_env (captures visibles). != true →
                    // même nettoyage que non-match, clause suivante.
                    if (clause.guard) |g| {
                        const gv = try evaluate(store, &new_env, self, g, 0);
                        const gn = store.get(gv);
                        var guard_ok = false;
                        if (gn.tag == .lit) {
                            switch (store.lits.items[gn.aux]) {
                                .boolean => |b| guard_ok = b,
                                else => {},
                            }
                        }
                        if (!guard_ok) {
                            for (bound_syms[0..bound_count]) |sym| {
                                new_env.delete(sym);
                            }
                            continue;
                        }
                    }
                    // TCO : spine de queue = seules positions légitimes de bounce
                    self.tco_spine_len = 0;
                    collectTailSpine(store, clause.body, name, &self.tco_spine_buf, &self.tco_spine_len);

                    const result = try evaluate(store, &new_env, self, clause.body, 0);

                    // ─── TCO : self-tail-call détecté → boucler ───
                    if (self.tco_args_len > 0) {
                        // Nettoyer les bindings de cette clause avant de reboucler
                        for (bound_syms[0..bound_count]) |sym| {
                            new_env.delete(sym);
                        }
                        @memcpy(current_args_buf[0..self.tco_args_len], self.tco_args_buf[0..self.tco_args_len]);
                        continue :tco_loop;
                    }

                    return result;
                }
                // Clause non matchée : nettoyer les bindings ajoutés pendant le matching
                for (bound_syms[0..bound_count]) |sym| {
                    new_env.delete(sym);
                }
            }

            // ─── Currying partiel ───
            var min_patterns: usize = 32;
            for (fn_def.clauses[0..fn_def.num_clauses]) |clause| {
                if (clause.num_patterns < min_patterns) {
                    min_patterns = clause.num_patterns;
                }
            }
            platform.dbg(
                "[call] name='{s}' args={d} clauses={d} min_patterns={d}\n",
                .{ name, current_args_len, fn_def.num_clauses, min_patterns },
            );
            if (current_args_len < min_patterns and min_patterns != 32) {
                const missing = min_patterns - current_args_len;
                const new_params = try self.allocator.alloc([]const u8, missing);
                defer {
                    for (new_params) |p| self.allocator.free(p);
                    self.allocator.free(new_params);
                }
                for (0..missing) |i| {
                    new_params[i] = try std.fmt.allocPrint(self.allocator, "__curry_{d}", .{i});
                }
                const call_args = try self.allocator.alloc(Id, min_patterns);
                defer self.allocator.free(call_args);
                @memcpy(call_args[0..current_args_len], current_args_buf[0..current_args_len]);
                for (0..missing) |i| {
                    call_args[current_args_len + i] = try store.sym(new_params[i]);
                }
                const name_sym = try store.sym(name);
                const body = try store.apply(name_sym, call_args);
                return try store.lambda(new_params, body);
            }

            // ─── Fallback : clause 0-pattern (f = λx.body) ───
            // Si aucune clause ne matche par arité, mais qu'une clause a
            // 0 pattern, on évalue son corps puis on applique les args au
            // résultat. Ex : `f = λx. x ; f 42` → (λx.x) 42 → 42.
            for (fn_def.clauses[0..fn_def.num_clauses]) |clause| {
                if (clause.num_patterns != 0) continue;
                if (clause.guard != null) continue;
                const body_val = try evaluate(store, caller_env, self, clause.body, 0);
                if (current_args_len == 0) return body_val;
                const bv_node = store.get(body_val);
                if (bv_node.tag != .lambda) continue;
                const applied = try store.apply(body_val, current_args_buf[0..current_args_len]);
                return try evaluate(store, caller_env, self, applied, 0);
            }

            return error.ArityMismatch;
        }
    }

};

/// Évaluateur à 6 branches (primitives fondamentales uniquement).
pub fn evaluate(store: *Store, env: *Env, engine: *Engine, id: Id, depth: u32) EvalError!Id {
    // Safepoint (3a-3) : budget de reductions. A 0 -> suspend.
    // Le `try` des 56 sites recursifs propage automatiquement.
    if (engine.reductions == 0) return error.SuspendRequested;
    engine.reductions -= 1;

    if (platform.target.is_debug and id == 0xAAAAAAAA) {
        @panic("poison Id at evaluate entry");
    }

    if (depth > 1000) return error.RecursionLimitExceeded;
    const node = store.get(id);

    return switch (node.tag) {
        .lit => id,
        .sym => {
            const name = store.interner.resolve(node.payload);
            if (isFrontendExtension(name)) return error.ExtensionNotLowered;
            if (isMagicSymbol(name)) return id;
            if (env.get(node.payload)) |bound| {
                //platform.dbg("[DEBUG eval] sym '{s}' trouvé dans env, valeur={d}\n", .{ name, bound });
                return bound;
            }
            if (name.len > 0 and name[0] >= 'A' and name[0] <= 'Z') return id;
            // Fix C3 : un ctor déclaré (data / bootstrap) est une valeur
            // légitime quelle que soit la casse. nil/cons/some/ok/...
            // minuscules étaient rejetés ici (seuls zero/succ/quote
            // étaient whitelistés, et les majuscules par heuristique).
            if (engine.fns.get(name)) |fd| {
                if (fd.ctor_arity != null) return id;
            }
            // Ordre supérieur : un symbole désignant une FONCTION USER
            // s'évalue en lui-même (valeur). Le binding de pattern le
            // stocke tel quel, et l'appel (f x) le résout via ENV-BOUND
            // Cas 1 (symbole lié à un symbole de fonction). Sans ceci,
            // evaluate(isBig) = UnboundVariable -- TCO/evalFunction
            // évaluant leurs args tuaient tout appel ordre supérieur
            // (filter/map/take : le bug "application partielle" du 28/09).
            if (engine.fns.get(name)) |fd| {
                if (fd.num_clauses > 0 and fd.ctor_arity == null) {
                    return id;
                }
            }
            if (engine.fns.get(name)) |fd| {
                if (fd.num_clauses > 0 and fd.ctor_arity == null) {
                    return id; // symbole-fonction user = valeur appelable
                }
            }
            const known_ctors = [_][]const u8{ "zero", "succ", "quote" };
            for (known_ctors) |kc| {
                if (std.mem.eql(u8, name, kc)) return id;
            }
            platform.dbg("[DEBUG eval] sym '{s}' NON trouvé dans env\n", .{name}); // ← ici
            return error.UnboundVariable;
        },
        .apply => {
            const pool = store.pool.items;
            const all_args = node.span_a.slice(pool);
            if (all_args.len == 0) {
                return error.ArityMismatch;
            }

            const op_id = node.payload;
            const op_node = store.get(op_id);

            if (op_node.tag != .sym) {
                const evaled_op = try evaluate(store, env, engine, op_id, depth + 1);
                const evaled_node = store.get(evaled_op);

                // Beta-réduction directe : (\x -> body) arg → body[x := arg]
                if (evaled_node.tag == .lambda) {
                    if (all_args.len < 2) return error.ArityMismatch;
                    const arg_val = try evaluate(store, env, engine, all_args[1], depth + 1);
                    const lam_span = store.spanSliceConst(evaled_node.span_a);
                    if (lam_span.len != 1) return error.NotALambda;
                    const param_sym = evaled_node.payload;
                    {
                        const pn = store.interner.resolve(param_sym);
                        platform.dbg("[ho-dbg] beta : param='{s}' arg_val_tag={s}\n", .{ pn, @tagName(store.get(arg_val).tag) });
                    }
                    // Substitution AST (capture env, évite les closures).
                    // Necessaire pour les lambdas imbriquees :
                    // f = λx. λy. (+ x y) ; f 3 doit produire λy. (+ 3 y).
                    const substituted = try store.substSym(lam_span[0], param_sym, arg_val);

                    if (all_args.len == 2) {
                        return evaluate(store, env, engine, substituted, depth + 1);
                    }

                    // Args excedentaires : reappliquer recursivement.
                    // f 3 4 -> (f 3) 4 -> ((λy. (+ 3 y)) 4) -> 7
                    const rest_args = all_args[2..];
                    const reapplied = try store.apply(substituted, rest_args);
                    return evaluate(store, env, engine, reapplied, depth + 1);
                }

                const new_apply = try store.addNode(.{ .tag = .apply, .payload = evaled_op, .aux = 0, .span_a = node.span_a, .span_b = Span.EMPTY });
                return evaluate(store, env, engine, new_apply, depth + 1);
            }

            const op_name = store.interner.resolve(op_node.payload);
            if (isFrontendExtensionApply(op_name)) return error.ExtensionNotLowered;

            const args = if (all_args.len > 1 and all_args[0] == op_id) all_args[1..] else all_args;

            // ─── TCO : bounce UNIQUEMENT depuis une position de queue ───
            if (engine.tco_name) |tco_name| {
                if (std.mem.eql(u8, op_name, tco_name) and args.len > 0 and args.len <= 8) {
                    var in_spine = false;
                    for (engine.tco_spine_buf[0..engine.tco_spine_len]) |sid| {
                        if (sid == id) {
                            in_spine = true;
                            break;
                        }
                    }
                    if (in_spine) {
                        if (engine.fns.get(op_name)) |fd| {
                            if (fd.num_clauses > 0 and fd.ctor_arity == null) {
                                for (args, 0..) |a_, i_| {
                                    engine.tco_args_buf[i_] = try evaluate(store, env, engine, a_, depth + 1);
                                }
                                engine.tco_args_len = @intCast(args.len);
                                return TCO_BOUNCE;
                            }
                        }
                    }
                }
            }
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
        .letrec => {
            // letrec : la variable est visible dans sa propre valeur (pour récursion)
            if (node.span_a.len < 1) return error.ArityMismatch;

            // Créer un placeholder pour le binding (permet la référence circulaire)
            const placeholder = try store.sym("__letrec_placeholder__");
            try env.put(node.payload, placeholder);

            // Évaluer la valeur avec le binding déjà présent (pour récursion)
            const val = try evaluate(store, env, engine, store.spanSliceConst(node.span_a)[0], depth + 1);

            // Mettre à jour le binding avec la vraie valeur
            env.delete(node.payload);
            try env.put(node.payload, val);

            // Évaluer le body
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
    const magics = .{ "+", "-", "*", "/", "%", "&", "|", "!", "=", "!=", "<", ">", "<=", ">=", ">>>", "if", "seq", "block", "tuple", "add", "sub", "mul", "div", "mod", "and", "or", "eq", "neq", "lt", "gt", "le", "ge" };
    inline for (magics) |m| {
        if (std.mem.eql(u8, name, m)) return true;
    }
    return false;
}

fn isFrontendExtension(name: []const u8) bool {
    if (std.mem.eql(u8, name, "unquote")) return true;
    if (std.mem.eql(u8, name, "perform")) return true;
    if (std.mem.eql(u8, name, "handle")) return true;
    if (std.mem.startsWith(u8, name, "Type_")) return true;
    return false;
}

fn isFrontendExtensionApply(name: []const u8) bool {
    if (std.mem.eql(u8, name, "unquote")) return true;
    if (std.mem.startsWith(u8, name, "Type_")) return true;
    return false;
}

fn evalMagic(store: *Store, env: *Env, engine: *Engine, op: []const u8, args: []const Id, depth: u32) EvalError!Id {
    platform.dbg("[ho-dbg] evalMagic op={s} args={d}\n", .{ op, args.len });
    // Buffer stack-local : zéro allocation pour args ≤ 8 (limite patterns).
    // Les appels récursifs à evaluate() peuvent realloc pool.items,
    // rendant la slice `args` dangling. On copie sur la stack.
    var args_buf: [8]Id = undefined;
    if (args.len > 8) return error.ArityMismatch;
    @memcpy(args_buf[0..args.len], args);
    const args_snap: []const Id = args_buf[0..args.len];

    // ═══ KANREN QUERY — intercepte TOUT de suite ═══
    // (query name arg1 _ ...) evalue en nombre de solutions.
    //
    // Note : on intercepte `query` mais PAS `fact`. `fact` est un
    // nom de fonction plausible (voir tests/verify_book.hvn ou
    // `fact 0 = 1` definit une fonction utilisateur). En revanche
    // `query` n'est jamais un nom de fonction utilisateur — c'est
    // deja le nom d'une commande top-level (`evalQuery`), donc
    // l'intercepter au niveau evalMagic est sur.
    if (std.mem.eql(u8, op, "query")) {
        if (engine.vtable.kanren_query) |f| {
            return f(engine.heaven_ctx, store, args_snap);
        }
        return error.UnknownSymbol;
    }
    // ═══ 0. CONSTRUCTEURS ═══
    if (engine.fns.get(op)) |fn_def| {
        //platform.dbg("[ctor-branch] op='{s}' clauses={d} ctor_arity={?d} args_snap.len={d}\n", .{ op, fn_def.num_clauses, fn_def.ctor_arity, args_snap.len });

        if (fn_def.ctor_arity) |arity| {
            if (args_snap.len != arity) {
                platform.debug.print("--> ArityMismatch: attendu {d}, reçu {d}\n", .{ arity, args_snap.len });
                return error.ArityMismatch;
            }
            const op_sym = store.interner.lookup(op) orelse return error.UnknownSymbol;
            const op_id = try store.symId(op_sym);
            if (args_snap.len == 0) return try store.apply(op_id, &.{});
            const evaled = try engine.allocator.alloc(Id, args_snap.len);
            defer engine.allocator.free(evaled);
            for (args_snap, 0..) |a, i| {
                evaled[i] = try evaluate(store, env, engine, a, depth + 1);
            }
            return try store.apply(op_id, evaled);
        } else {
            //platform.dbg("[ctor-branch] op='{s}' NOT IN FNS MAP\n", .{op});
        }
    }

    // ═══ DISPATCH ENV : head lié à une fonction ou expression ═══
    if (store.interner.lookup(op)) |op_sym| {
        if (env.get(op_sym)) |bound| {
            const bound_node = store.get(bound);

            // Cas 1 : symbole lié à un autre symbole de fonction connue
            //   map inc → f = inc_sym → dispatch vers evalFunction("inc")
            if (bound_node.tag == .sym) {
                const target = store.interner.resolve(bound_node.payload);
                if (engine.fns.get(target) != null) {
                    // TCO alias : décidé dans evaluate(.apply) via la spine
                    return engine.evalFunction(env, target, args_snap);
                }
            }

            // Cas 2 : symbole lié à une expression (ex : >>> produit un apply)
            //   map (inc >>> dbl) → f = apply(>>>, [inc, dbl])
            //   → on reconstruit apply(f, args_snap) et on laisse evaluate gérer
            if (bound_node.tag == .apply or bound_node.tag == .lambda) {
                const new_apply = try store.apply(bound, args_snap);
                return evaluate(store, env, engine, new_apply, depth + 1);
            }
        }
    }

    // ═══ `>>>` : composition de fonctions ═══
    // f >>> g = \__pipe_x -> g (f __pipe_x)
    if (std.mem.eql(u8, op, ">>>")) {
        if (args_snap.len != 2) return error.ArityMismatch;
        const f = args_snap[0];
        const g = args_snap[1];
        const x_sym_id = try store.sym("__pipe_x");
        const fx = try store.apply(f, &.{x_sym_id});
        const gfx = try store.apply(g, &.{fx});
        return try store.lambdaNative(&.{"__pipe_x"}, gfx);
    }

    // ENV-BOUND LAMBDA — EN PREMIER, avant tout autre check
    // (récursion locale : (let fact (lambda n ...) (fact 5)))
    if (args_snap.len == 1) {
        if (store.interner.lookup(op)) |op_sym| {
            if (env.get(op_sym)) |bound| {
                const bound_node = store.get(bound);
                if (bound_node.tag == .lambda) {
                    const lam_span = bound_node.span_a.slice(store.pool.items);
                    platform.dbg("[ho-dbg] ENV-BOUND lambda : op={s} args={d} lam_span={d}\n", .{ op, args_snap.len, lam_span.len });
                    if (lam_span.len == 1) {
                        const arg_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
                        try env.put(bound_node.payload, arg_val);
                        // (defer delete retiré : thunk)
                        return evaluate(store, env, engine, lam_span[0], depth + 1);
                    }
                }
                // NOUVEAU : symbole lié à un autre symbole de fonction
                if (bound_node.tag == .sym) {
                    const target = store.interner.resolve(bound_node.payload);
                    if (engine.fns.get(target) != null) {
                        // TCO alias : décidé dans evaluate(.apply) via la spine
                        return engine.evalFunction(env, target, args_snap);
                    }
                }
            }
        }
    }

    // ═══ MACROS ═══
    if (store.interner.lookup(op)) |op_sym| {
        if (engine.macros.get(op_sym)) |m| {
            const params = m.params_span.slice(store.pool.items);
            if (args_snap.len != params.len) {
                platform.debug.print("--> ArityMismatch: attendu {d}, reçu {d}\n", .{ params.len, args_snap.len });
                return error.ArityMismatch;
            }
            const expansion = try expandMacro(store, engine.allocator, m.body, params, args_snap);
            return evaluate(store, env, engine, expansion, depth + 1);
        }
    }

    // ═══ 1. FONCTIONS UTILISATEUR — délégué à evalFunction ═══
    if (engine.fns.get(op)) |fn_def| {
        if (fn_def.num_clauses > 0 and fn_def.ctor_arity == null) {
            // TCO : décidé dans evaluate(.apply) via la spine de queue
            return engine.evalFunction(env, op, args_snap);
        }
    }

    if (std.mem.eql(u8, op, "derive")) {
        if (args_snap.len != 1) {
            platform.debug.print("--> ArityMismatch: attendu {d}, reçu {d}\n", .{ 1, args_snap.len });
            return error.ArityMismatch;
        }
        const expr_str = try expr.toString(store, args_snap[0], engine.allocator);
        defer engine.allocator.free(expr_str);
        return try engine.vtable.deriveId(engine.heaven_ctx, expr_str, "x");
    }
    if (std.mem.eql(u8, op, "simplify")) {
        if (args_snap.len != 1) {
            platform.debug.print("--> ArityMismatch: attendu {d}, reçu {d}\n", .{ 1, args_snap.len });
            return error.ArityMismatch;
        }
        const expr_str = try expr.toString(store, args_snap[0], engine.allocator);
        defer engine.allocator.free(expr_str);
        const result_str = try engine.vtable.simplify(engine.heaven_ctx, expr_str);
        defer engine.allocator.free(result_str);
        const result_id = try engine.vtable.parse(engine.heaven_ctx, result_str);
        return result_id;
    }

    // ═══ 2. OPÉRATEURS MAGIQUES ═══
    if (std.mem.eql(u8, op, "if")) {
        if (args_snap.len != 3) return error.ArityMismatch;
        const cond = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const cond_node = store.get(cond);
        if (cond_node.tag != .lit) return error.TypeError;
        const lit = store.lits.items[cond_node.aux];
        if (lit != .boolean) return error.TypeError;
        return if (lit.boolean) evaluate(store, env, engine, args_snap[1], depth + 1) else evaluate(store, env, engine, args_snap[2], depth + 1);
    }
    if (std.mem.eql(u8, op, "seq") or std.mem.eql(u8, op, "block")) {
        var last: Id = undefined;
        for (args_snap) |arg| last = try evaluate(store, env, engine, arg, depth + 1);
        return last;
    }
    if (std.mem.eql(u8, op, "tuple")) {
        const new_span = try store.reserveSpan(args_snap.len);
        for (0..args_snap.len) |i| {
            store.pool.items[new_span.start + i] = try evaluate(store, env, engine, args_snap[i], depth + 1);
        }
        const sym = try store.interner.intern("tuple");
        const sym_node = try store.addNode(.{ .tag = .sym, .payload = sym, .aux = 0, .span_a = Span.EMPTY, .span_b = Span.EMPTY });
        const apply_span = try store.reserveSpan(1 + args_snap.len);
        store.pool.items[apply_span.start] = sym_node;
        @memcpy(store.pool.items[apply_span.start + 1 .. apply_span.start + 1 + args_snap.len], store.pool.items[new_span.start .. new_span.start + args_snap.len]);
        return store.addNode(.{ .tag = .apply, .payload = sym_node, .aux = 0, .span_a = apply_span, .span_b = Span.EMPTY });
    }

    // ═══ 3. ACTEURS : send et state ═══
    if (std.mem.eql(u8, op, "send")) {
        if (args_snap.len != 2) return error.ArityMismatch;
        const actor_id_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const msg_val = try evaluate(store, env, engine, args_snap[1], depth + 1);
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
                    // platform.dbg("[DEBUG SEND] handler evaluated to: {d}\n", .{new_state});
                    actor_ptr.state = new_state;
                    // platform.dbg("[DEBUG SEND] actor state updated to: {d}\n", .{actor_ptr.state});
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
    // ═══ PROTOTYPE 1 CONCURRENCE : spawn / tell / recv ═══
    // Voir docs/spec/_concurrency.md. Modèle minimal : un process
    // est une mailbox FIFO. Pas de handler, pas de scheduler, pas
    // de distribution. Sert à valider que les 3 primitives
    // composables fonctionnent ensemble.

    if (std.mem.eql(u8, op, "spawn")) {
        // spawn(handler_fn, init_state) → pid
        // Prototype 2-lite : on stocke handler + state. run(pid)
        // les consomme pour traiter la mailbox.
        if (args_snap.len != 2) return error.ArityMismatch;
        const handler_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const init_val = try evaluate(store, env, engine, args_snap[1], depth + 1);

        const pid = engine.next_process_id;
        engine.next_process_id += 1;
        try engine.processes.put(engine.allocator, pid, .{
            .handler = handler_val,
            .state = init_val,
        });
        return try store.int(@intCast(pid));
    }

    if (std.mem.eql(u8, op, "tell")) {
        // tell(pid, msg) → msg (dépose dans la mailbox du process)
        if (args_snap.len != 2) return error.ArityMismatch;
        const pid_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const msg_val = try evaluate(store, env, engine, args_snap[1], depth + 1);

        const pid_node = store.get(pid_val);
        if (pid_node.tag != .lit) return error.ActorIdNotLiteral;
        const pid_lit = store.lits.items[pid_node.aux];
        if (pid_lit != .int) return error.ActorIdNotLiteral;

        const proc = engine.processes.getPtr(@intCast(pid_lit.int)) orelse
            return error.ProcessNotFound;
        try proc.mailbox.append(engine.allocator, msg_val);
        return msg_val;
    }

    if (std.mem.eql(u8, op, "recv")) {
        // recv(pid) → msg (pop la prochaine valeur de la mailbox)
        if (args_snap.len != 1) return error.ArityMismatch;
        const pid_val = try evaluate(store, env, engine, args_snap[0], depth + 1);

        const pid_node = store.get(pid_val);
        if (pid_node.tag != .lit) return error.ActorIdNotLiteral;
        const pid_lit = store.lits.items[pid_node.aux];
        if (pid_lit != .int) return error.ActorIdNotLiteral;

        const proc = engine.processes.getPtr(@intCast(pid_lit.int)) orelse
            return error.ProcessNotFound;
        if (proc.mailbox.items.len == 0) return error.MailboxEmpty;
        return proc.mailbox.orderedRemove(0);
    }

    if (std.mem.eql(u8, op, "run")) {
        // run(pid) → state final. Draine la mailbox en appelant le
        // handler (fn symbol) avec (state, msg) pour chaque message.
        // NON-PRÉEMPTIF : caller-driven, synchrone. Pour la
        // préemption, voir Prototype 3 (nécessite continuations).
        if (args_snap.len != 1) return error.ArityMismatch;
        const pid_val = try evaluate(store, env, engine, args_snap[0], depth + 1);

        const pid_node = store.get(pid_val);
        if (pid_node.tag != .lit) return error.ActorIdNotLiteral;
        const pid_lit = store.lits.items[pid_node.aux];
        if (pid_lit != .int) return error.ActorIdNotLiteral;

        const proc = engine.processes.getPtr(@intCast(pid_lit.int)) orelse
            return error.ProcessNotFound;

        const handler_val = proc.handler orelse return error.HandlerFailed;
        const handler_node = store.get(handler_val);
        if (handler_node.tag != .sym) return error.HandlerFailed;
        const handler_name = store.interner.resolve(handler_node.payload);
        const fn_def = engine.fns.get(handler_name) orelse return error.HandlerFailed;
        if (fn_def.num_clauses == 0) return error.HandlerFailed;
        const clause = fn_def.clauses[0];

        var current_state: expr.Id = proc.state orelse 0;

        while (proc.mailbox.items.len > 0) {
            const msg_val = proc.mailbox.orderedRemove(0);

            var new_env = Env.init(engine.allocator);
            defer new_env.deinit();
            var it_env = env.bindings.iterator();
            while (it_env.next()) |entry| {
                try new_env.put(entry.key_ptr.*, entry.value_ptr.*);
            }

            if (clause.num_patterns >= 1) {
                const p1 = store.get(clause.patterns[0]);
                if (p1.tag == .sym) try new_env.put(p1.payload, current_state);
            }
            if (clause.num_patterns >= 2) {
                const p2 = store.get(clause.patterns[1]);
                if (p2.tag == .sym) try new_env.put(p2.payload, msg_val);
            }

            current_state = try evaluate(store, &new_env, engine, clause.body, depth + 1);
        }

        proc.state = current_state;
        return current_state;
    }

    // ═══ SCOPED EFFECTS (docs/spec/_effects.md) ═══
    // Synchrone, pas de continuation. `bracket`/`local`/`catch`
    // fournissent les primitives de portée (setup/teardown,
    // shadow local, rattrapage d'erreur) sans toucher au noyau.

    if (std.mem.eql(u8, op, "bracket")) {
        // bracket(setup, body, teardown) → résultat de body
        // Évalue setup, body, teardown dans l'ordre. Retourne le
        // résultat de body. Si teardown échoue, l'erreur remonte
        // (le résultat de body est perdu).
        if (args_snap.len != 3) return error.ArityMismatch;
        _ = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const body_result = try evaluate(store, env, engine, args_snap[1], depth + 1);
        _ = try evaluate(store, env, engine, args_snap[2], depth + 1);
        return body_result;
    }

    if (std.mem.eql(u8, op, "local")) {
        // local(name, val, body) → bind name := val, évalue body,
        // restaure le binding précédent (ou retire si absent).
        // `name` est un string lit ("x") ou un sym nu.
        if (args_snap.len != 3) return error.ArityMismatch;
        const name_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const bound_val = try evaluate(store, env, engine, args_snap[1], depth + 1);

        const name_node = store.get(name_val);
        var sym: ?expr.Sym = null;
        if (name_node.tag == .sym) {
            sym = name_node.payload;
        } else if (name_node.tag == .lit) {
            const lit = store.lits.items[name_node.aux];
            if (lit == .str) {
                sym = store.interner.lookup(store.interner.resolve(lit.str));
            }
        }
        if (sym == null) return error.InvalidInput;

        const sym_id = sym.?;
        const old_binding = env.get(sym_id);

        try env.put(sym_id, bound_val);
        defer {
            if (old_binding) |old| {
                env.put(sym_id, old) catch {};
            } else {
                env.delete(sym_id);
            }
        }

        return try evaluate(store, env, engine, args_snap[2], depth + 1);
    }

    if (std.mem.eql(u8, op, "catch")) {
        // catch(body, default) → résultat de body, ou résultat de
        // default si body lève une erreur.
        // Catch-all : y compris OutOfMemory, RecursionLimitExceeded,
        // etc. (comme un try/catch runtime).
        if (args_snap.len != 2) return error.ArityMismatch;
        const body_result = evaluate(store, env, engine, args_snap[0], depth + 1) catch {
            return try evaluate(store, env, engine, args_snap[1], depth + 1);
        };
        return body_result;
    }

    if (std.mem.eql(u8, op, "state")) {
        if (args_snap.len != 1) return error.ArityMismatch;
        const actor_id_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
        const actor_node = store.get(actor_id_val);
        if (actor_node.tag != .lit) return error.ActorIdNotLiteral;
        const actor_id_lit = store.lits.items[actor_node.aux];
        if (actor_id_lit != .int) return error.ActorIdNotLiteral;
        const actor_ptr = engine.actors.getPtr(@intCast(actor_id_lit.int)) orelse return error.ActorNotFound;
        // platform.dbg("[DEBUG STATE] returning state: {d}\n", .{actor_ptr.state});
        return actor_ptr.state;
    }

    // ═══ 3. EFFETS ALGÉBRIQUES : perform et handle ═══
    if (std.mem.eql(u8, op, "perform")) {
        if (engine.green_mode) engine.green_call_count += 1;

        // 1. Toujours évaluer le dernier argument (exposé à un handle
        //    éventuel via last_performed, mécanisme one-shot existant).
        var last_val: ?expr.Id = null;
        if (args_snap.len > 1) {
            last_val = try evaluate(store, env, engine, args_snap[1], depth + 1);
            engine.last_performed = last_val;
        }

        // 2. Si pas dans un handle explicite et qu'un handler IO est
        //    installé : dispatcher sur le label.
        if (!engine.in_handle) {
            if (engine.io_handler) |handler| {
                if (args_snap.len > 0) {
                    const label_node = store.get(args_snap[0]);
                    if (label_node.tag == .lit) {
                        const lit = store.lits.items[label_node.aux];
                        if (lit == .str) {
                            const label = store.interner.resolve(lit.str);
                            if (try handler(store, label, last_val)) |result| {
                                return result;
                            }
                        }
                    }
                }
            }
        }

        // 3. Fallback : comportement historique.
        return last_val orelse args_snap[0];
    }

    if (std.mem.eql(u8, op, "handle")) {
        const old_mode = engine.green_mode;
        engine.green_mode = true;
        engine.green_call_count = 0;
        const old_performed = engine.last_performed;
        engine.last_performed = null;
        const old_in_handle = engine.in_handle;
        engine.in_handle = true;

        const result = evaluate(store, env, engine, args_snap[0], depth + 1) catch |err| {
            engine.green_mode = old_mode;
            engine.last_performed = old_performed;
            engine.in_handle = old_in_handle;
            return err;
        };

        const performed = engine.last_performed;
        engine.green_mode = old_mode;
        engine.last_performed = old_performed;
        engine.in_handle = old_in_handle;

        if (performed) |val| {
            if (args_snap.len > 1) {
                const call_id = try store.apply(args_snap[1], &.{val});
                return evaluate(store, env, engine, call_id, depth + 1);
            }
        }
        return result;
    }

    // ═══ 5. OPÉRATEURS ARITHMÉTIQUES ═══
    if (args_snap.len == 0) return error.ArityMismatch;
    if (std.mem.eql(u8, op, "!")) {
        if (args_snap.len != 1) return error.ArityMismatch;
        const a = try evaluate(store, env, engine, args_snap[0], depth + 1);
        return evalUnary(store, a, .not);
    }
    if (args_snap.len != 2) return error.ArityMismatch;
    const a = try evaluate(store, env, engine, args_snap[0], depth + 1);
    const b = try evaluate(store, env, engine, args_snap[1], depth + 1);

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

    // ═══ ENV-BOUND LAMBDA : (f arg) où f est une lambda dans l'env ═══
    // Permet la récursion locale : (let fact (lambda n ...) (fact 5))
    // L'engine résout fact via l'env, applique la lambda récursivement.
    if (store.interner.lookup(op)) |op_sym| {
        if (env.get(op_sym)) |bound| {
            platform.dbg("[engine-lambda] op='{s}' found!\n", .{op});
            const bound_node = store.get(bound);
            if (bound_node.tag == .lambda and args_snap.len == 1) {
                const lam_span = bound_node.span_a.slice(store.pool.items);
                if (lam_span.len == 1) {
                    const arg_val = try evaluate(store, env, engine, args_snap[0], depth + 1);
                    try env.put(bound_node.payload, arg_val);
                    // (defer delete retiré : thunk)
                    return evaluate(store, env, engine, lam_span[0], depth + 1);
                }
            }
        }
    }

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
                .div => if (vb == 0) return error.DivisionByzero else .{ .int = @divTrunc(va, vb) },
                .mod => if (vb == 0) return error.DivisionByzero else .{ .int = @mod(va, vb) },
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

pub fn expandMacro(store: *expr.Store, allocator: Allocator, body: expr.Id, params: []const expr.Id, args: []const expr.Id) !expr.Id {
    const node = store.get(body);
    switch (node.tag) {
        .sym => {
            for (params, 0..) |p, i| {
                if (i >= args.len) break;
                const pn = store.get(p);
                if (pn.tag == .sym and pn.payload == node.payload) return args[i];
            }
            return body;
        },
        .lit => return body,
        .apply => {
            const fnode = store.get(node.payload);
            var head: []const u8 = "";
            if (fnode.tag == .sym) head = store.interner.resolve(fnode.payload);
            const children = store.spanSliceConst(node.span_a);
            if (std.mem.eql(u8, head, "quote") and children.len == 2)
                return expandMacro(store, allocator, children[1], params, args);
            if (std.mem.eql(u8, head, "unquote") and children.len == 2)
                return expandMacro(store, allocator, children[1], params, args);
            if (children.len < 2) return body;
            var new_args: std.ArrayListUnmanaged(expr.Id) = .{};
            defer new_args.deinit(allocator);
            for (children[1..]) |c| {
                try new_args.append(allocator, try expandMacro(store, allocator, c, params, args));
            }
            return store.apply(node.payload, new_args.items);
        },
        else => return body,
    }
}

test "engine rejects non-lowered frontend expressions" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    // Contrat mis à jour : les SYMBOLES NUS restent du sucre non-lowered.
    // Les apply (quote x 0) / (perform ...) sont devenus ÉVALUABLES
    // (expandMacro + branches effets dans evalMagic) — c'est ce qui
    // fait marcher macro_double et effect_handle.

    // quote n'est plus une extension frontend — c'est un constructeur de données
    // Il s'auto-évalue comme un symbole ordinaire (pas d'erreur)
    const quote_nu = try engine.store.sym("quote");
    const quote_result = try engine.eval(quote_nu);
    try std.testing.expectEqual(quote_nu, quote_result);

    const perform_nu = try engine.store.sym("perform");
    try std.testing.expectError(
        error.ExtensionNotLowered,
        engine.eval(perform_nu),
    );

    const handle_nu = try engine.store.sym("handle");
    try std.testing.expectError(
        error.ExtensionNotLowered,
        engine.eval(handle_nu),
    );

    const unquote_nu = try engine.store.sym("unquote");
    try std.testing.expectError(
        error.ExtensionNotLowered,
        engine.eval(unquote_nu),
    );

    //    const nil_nu = try engine.store.sym("Nil");
    //    try std.testing.expectError(
    //        error.ExtensionNotLowered,
    //        engine.eval(nil_nu),
    //    );

    // En apply, unquote reste rejeté (hors expansion de macro)
    const x = try engine.store.sym("x");
    const zero = try engine.store.int(0);
    const unquote_apply = try engine.store.binop("unquote", x, zero);
    try std.testing.expectError(
        error.ExtensionNotLowered,
        engine.eval(unquote_apply),
    );
}

test "engine evaluates lowered expression" {
    const allocator = std.testing.allocator;

    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    const x = try engine.store.int(2);
    const y = try engine.store.int(3);
    const frontend = try engine.store.binop("+", x, y);
    const lowered = try engine.store.lowerRec(frontend);
    try engine.store.assertCoreExpr(lowered);
    _ = try engine.eval(lowered);
}

test "Env.get ne crash pas après init" {
    var env = Env.init(std.testing.allocator);
    defer env.deinit();
    try env.put(42, 0);
    try std.testing.expectEqual(@as(?Id, 0), env.get(42));
}

test "safepoint : evalWithBudget suspend si budget insuffisant" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    // Expression simple : 2 + 3
    const x = try engine.store.int(2);
    const y = try engine.store.int(3);
    const frontend = try engine.store.binop("+", x, y);
    const lowered = try engine.store.lowerRec(frontend);

    // Budget 0 : suspend immediatement (le premier appel de evaluate
    // consomme 1 reduction avant meme d'evaluer).
    const outcome = try engine.evalWithBudget(lowered, 0);
    try std.testing.expectEqual(Engine.EvalOutcome.suspended, outcome);
}

test "safepoint : evalWithBudget termine avec budget suffisant" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    const x = try engine.store.int(2);
    const y = try engine.store.int(3);
    const frontend = try engine.store.binop("+", x, y);
    const lowered = try engine.store.lowerRec(frontend);

    // Budget large : termine normalement.
    const outcome = try engine.evalWithBudget(lowered, 1000);
    try std.testing.expect(outcome == .done);
}

test "safepoint : fuel top-level non affecte par evalWithBudget" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    const fuel_before = engine.fuel;
    const reductions_before = engine.reductions;

    const x = try engine.store.int(2);
    const y = try engine.store.int(3);
    const frontend = try engine.store.binop("+", x, y);
    const lowered = try engine.store.lowerRec(frontend);

    _ = try engine.evalWithBudget(lowered, 1000);

    // Le fuel top-level n'a pas bouge.
    try std.testing.expectEqual(fuel_before, engine.fuel);
    // Les reductions sont restaurees (saved via defer).
    try std.testing.expectEqual(reductions_before, engine.reductions);
}

test "evalWithRetry : budget initial suffisant" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    const expr_id = try store.int(42);
    const result = try engine.evalWithRetry(expr_id, 1000, 100_000);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(expr_id, result.?);
}

test "evalWithRetry : budget initial insuffisant, retry reussit" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    // Construit (+ 1 2) : plusieurs safepoints necessaires.
    const one = try store.int(1);
    const two = try store.int(2);
    const plus_sym = try store.sym("+");
    const expr_id = try store.apply(plus_sym, &.{ one, two });

    const result = try engine.evalWithRetry(expr_id, 0, 100_000);
    try std.testing.expect(result != null);
}

test "evalWithRetry : budget max atteint retourne null" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    const expr_id = try store.int(42);
    // Budget initial = max = 0 : ne peut pas evaluer un seul noeud.
    const result = try engine.evalWithRetry(expr_id, 0, 0);
    try std.testing.expect(result == null);
}

test "safepoint : reductions restaurees apres evalWithBudget" {
    const allocator = std.testing.allocator;
    var store = Store.init(allocator);
    defer store.deinit();
    var env = Env.init(allocator);
    defer env.deinit();
    var engine = Engine.initTest(allocator, &store, &env);
    defer engine.deinit();

    // Modifie reductions manuellement
    engine.reductions = 42;

    const x = try engine.store.int(1);
    _ = try engine.evalWithBudget(x, 1000);

    // Restaure a 42, pas a maxInt.
    try std.testing.expectEqual(@as(u64, 42), engine.reductions);
}