//! Frontend Heaven - intégration du moteur de simplification EGraph
const std = @import("std");
const expr = @import("expr");
const hole_mod = @import("hole");
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
const proof_state_mod = @import("proof_state");
const tactics_mod = @import("tactics");
const type_registry_mod = @import("type_registry");
const agent_mod = @import("agent");

const elab_mod = @import("elab");
const profiler_mod = @import("profiler");
const io_handler_mod = @import("io_handler");
const expr_parser_mod = @import("expr_parser");
const std_loader = @import("std_loader");
const import_mod = @import("import");
const ImportState = import_mod.ImportState;
const kanren_expr_mod = @import("kanren");
const unify_proof_mod = @import("tactics").unify_proof;
const hole_runtime_mod = @import("hole_runtime");

/// Réexport de commodité : les consommateurs historiques (`commands.zig`,
/// WASM entry) importaient ce symbole depuis `heaven_expr`. La fonction
/// vit désormais dans `io_handler.zig`, mais reste accessible via cette
/// façade tant que RFC-0001 n'est pas achevé.
pub const defaultIOHandler = io_handler_mod.defaultIOHandler;

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
    UnboundHole,
    UnknownHole,
} || std.mem.Allocator.Error || platform.fs.File.OpenError || platform.fs.File.ReadError || mir.MirError || engine_expr.EvalError;

const MacroDef = struct {
    params: []const []const u8,
    body: Id,
};

pub const HoleInfo = struct {
    id: u32,
    /// Dernière expression racine où ce trou a été observé (pour l'affichage).
    seen_in: ?Id = null,
};


// ImportState extrait dans import.zig (RFC-0001 5/5).
// Alias local ci-dessous : const ImportState = import_mod.ImportState;

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
    hole_state: hole_mod.HoleState,
    last_root_expr: ?Id = null,
    /// Namespace courant (`module M` → "M"). Utilisé pour aliasser les
    /// théorèmes sous `M.name` dans proof_core.
    current_module: ?[]const u8 = null,
    /// Registre des types de données (v0 #type-dep).
    type_registry: type_registry_mod.TypeRegistry,
    /// Pile de modules en cours de chargement — détection de cycles.
    loading_modules: std.ArrayListUnmanaged([]const u8) = .{},
    /// v3a : mode strict opt-in. Quand actif, les définitions faites
    /// pendant un `module M` ne sont enregistrées que sous `M.x`,
    /// et `eval` refuse de résoudre `x` nu en top-level.
    strict_modules: bool = false,
    /// Noms cachés par le mode strict (accessible seulement via `M.x`).
    hidden_names: std.StringHashMapUnmanaged(void) = .{},
    /// v2a : arité des constructeurs (nom → nombre d'args).
    ctor_arities: std.StringHashMapUnmanaged(u8) = .{},
    /// v2a : arité des fonctions déclarées via `sig name : ...`.
    fn_arities: std.StringHashMapUnmanaged(u8) = .{},
    /// Parseur d'expressions (extrait RFC-0001).
    expr_parser: expr_parser_mod.ExprParser,
    /// Runtime des trous (extrait RFC-0001).
    hole_runtime: hole_runtime_mod.HoleRuntime,
    /// v2b : type parent de chaque ctor (`Cons` → `Vec`).
    ctor_parents: std.StringHashMapUnmanaged([]const u8) = .{},
    /// v2d : forme du résultat d'un ctor paramétré (ex. `Cons` →
    /// `"Vec (succ _)"`, `Nil` → `"Vec zero"`). Sert à unifier
    /// le domaine déclaré (`Vec (succ n)`) avec la forme du ctor
    /// pour accumuler les bindings d'indexes dépendants avant
    /// d'instancier le RHS de l'équation.
    ctor_results: std.StringHashMapUnmanaged([]const u8) = .{},
    /// Etape 1 pipeline logique unifie (kanren_expr) : faits + query
    /// par pattern matching simple (SLD sans regles pour l'instant).
    kanren: kanren_expr_mod.Kanren,
    /// v2b : heads des domaines d'une signature (`sig f : A -> B -> C`
    /// stocke `"A B"`).
    fn_domains: std.StringHashMapUnmanaged([]const u8) = .{},
    /// v2c : domaines complets d'une signature, séparés par `\x1f`.
    /// Ex. : `"Nat\x1fVec (succ n)\x1fa"` pour `A -> B -> C`.
    fn_domains_full: std.StringHashMapUnmanaged([]const u8) = .{},
    /// État d'import en cours (v2a : `export`). null hors import.
    import_state: ?*ImportState = null,
    /// Cache d'idempotence (v2b) : chemin résolu → nom du module.
    imported_files: std.StringHashMapUnmanaged([]const u8) = .{},

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
            .hole_state = hole_mod.HoleState.init(allocator),
            .expr_parser = undefined,
            .hole_runtime = undefined,
            .type_registry = type_registry_mod.TypeRegistry.init(allocator),
            .kanren = undefined,
            .loading_modules = .{},
        };

        self.expr_parser = expr_parser_mod.ExprParser.init(
            store,
            allocator,
            &self.hole_state,
            &self.last_root_expr,
        );
        self.kanren = kanren_expr_mod.Kanren.init(store, allocator);

        self.hole_runtime = hole_runtime_mod.HoleRuntime.init(
            store,
            allocator,
            &self.hole_state,
            &self.last_root_expr,
        );

        // Définir la vtable
        const heaven_vtable = engine_expr.HeavenVTable{
            .parse = parseHeavenExpr,
            .deriveId = deriveIdHeavenExpr,
            .simplify = simplifyHeavenExpr,
        };

        // Initialiser l'engine DANS self.engine (champ stable du heap)
        self.engine = engine_expr.Engine.init(allocator, store, &self.env, @ptrCast(self), &heaven_vtable);
        self.engine.io_handler = io_handler_mod.defaultIOHandler;

        // Tous les composants qui ont besoin de l'engine pointent sur self.engine,
        // pas sur une variable locale (sinon dangling pointer dès qu'init retourne).
        parser.* = parse_mod.Parser.init(store, &self.engine, &self.env, allocator);
        self.math = math_mod.Math.init(store, &self.engine, bridge, parser, allocator);

        // Initialiser kb, simplify_eng, proof_core
        const kb = try allocator.create(transform_mod.KnowledgeBase);
        kb.* = transform_mod.KnowledgeBase.init(allocator);
        self.kb = kb;

        self.simplify_eng = simplify_engine_mod.SimplifyEngine.init(store, &self.engine, &self.env, kb, allocator);

        const proof_core = proof.ProofEnv.init(allocator);
        self.proof_core = proof_core;

        // Ajouter les règles par défaut
        try self.addDefaultRules();

        // Charger le noyau logique (bootstrap.hvn) dans le FunctionRegistry
        self.loadBootstrap();

        // Charger les wrappers IO (print, readFile, writeFile, readLine)
        // dans le FunctionRegistry de l'engine.
        self.loadStdIO();

        const ctors = [_]struct { name: []const u8, arity: u8 }{
            .{ .name = "zero", .arity = 0 },  .{ .name = "Zero", .arity = 0 },
            .{ .name = "nil", .arity = 0 },   .{ .name = "Nil", .arity = 0 },
            .{ .name = "true", .arity = 0 },  .{ .name = "True", .arity = 0 },
            .{ .name = "false", .arity = 0 }, .{ .name = "False", .arity = 0 },
            .{ .name = "unit", .arity = 0 },  .{ .name = "Unit", .arity = 0 },
            .{ .name = "succ", .arity = 1 },  .{ .name = "Succ", .arity = 1 },
        };

        for (ctors) |ctor| {
            const owned = try self.allocator.dupe(u8, ctor.name);
            const gop = try self.engine.fns.getOrPut(self.allocator, owned);
            if (gop.found_existing) {
                self.allocator.free(owned);
            } else {
                gop.value_ptr.* = .{
                    .clauses = undefined,
                    .num_clauses = 0,
                };
            }

            gop.value_ptr.ctor_arity = ctor.arity;
            //platform.dbg("[ctor-reg] {s} arity={d}\n", .{ ctor.name, ctor.arity });
        }

        // v2b : parents des ctors built-in (utilisés par la vérif de kind).
        const builtin_parents = [_]struct { ctor: []const u8, parent: []const u8 }{
            .{ .ctor = "zero",  .parent = "Nat"  },
            .{ .ctor = "Zero",  .parent = "Nat"  },
            .{ .ctor = "succ",  .parent = "Nat"  },
            .{ .ctor = "Succ",  .parent = "Nat"  },
            .{ .ctor = "nil",   .parent = "List" },
            .{ .ctor = "Nil",   .parent = "List" },
            .{ .ctor = "cons",  .parent = "List" },
            .{ .ctor = "Cons",  .parent = "List" },
            .{ .ctor = "true",  .parent = "Bool" },
            .{ .ctor = "True",  .parent = "Bool" },
            .{ .ctor = "false", .parent = "Bool" },
            .{ .ctor = "False", .parent = "Bool" },
        };
        for (builtin_parents) |bp| {
            const k = try self.allocator.dupe(u8, bp.ctor);
            const v = try self.allocator.dupe(u8, bp.parent);
            const gop = try self.ctor_parents.getOrPut(self.allocator, k);
            if (gop.found_existing) {
                self.allocator.free(k);
                self.allocator.free(@constCast(gop.value_ptr.*));
                gop.value_ptr.* = v;
            } else {
                gop.value_ptr.* = v;
            }
        }

        //if (self.engine.fns.get("succ")) |def| {
        //platform.dbg("[ctor-verify] succ.ctor_arity = {?d}\n", .{def.ctor_arity});
        //}

        //platform.dbg("[ctor-check] fns registered:\n", .{});
        var it = self.engine.fns.iterator();
        while (it.next()) |e| {
            platform.dbg("  - '{s}' ({d} clauses)\n", .{ e.key_ptr.*, e.value_ptr.num_clauses });
        }

        return self;
    }

    fn loadBootstrap(self: *Heaven) void {
        const source = platform.fs.cwd().readFileAlloc(
            self.allocator,
            "core/bootstrap.hvn",
            64 * 1024,
        ) catch |err| {
            platform.dbg("[loadBootstrap] readFileAlloc failed: {}\n", .{err});
            return;
        };
        defer self.allocator.free(source);

        var tmp_registry = engine_expr.FunctionRegistry.init(self.allocator);
        defer tmp_registry.deinit();

        _ = elab_mod.elaborateSource(
            self.allocator,
            self.store,
            source,
            &tmp_registry,
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

    /// Charge `core/io.hvn` dans le FunctionRegistry de l'engine,
    /// en évaluant chaque ligne via `evalEquation`. La fonction
    /// `print`, `readFile`, etc. deviennent ainsi accessibles au REPL.
    /// Charge io.hvn + les std/*.hvn ligne par ligne via Heaven.eval.
    /// Ce chemin passe par evalDataDecl (qui enregistre correctement
    /// les ctor_arity) contrairement à ingest/elab.
    fn loadStdIO(self: *Heaven) void {
        std_loader.loadAll(self);
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

        if (self.current_module) |m| self.allocator.free(m);
        for (self.loading_modules.items) |m| self.allocator.free(m);
        self.loading_modules.deinit(self.allocator);
        {
            var it = self.hidden_names.keyIterator();
            while (it.next()) |k| self.allocator.free(k.*);
        }
        self.hidden_names.deinit(self.allocator);
        {
            var it = self.ctor_arities.keyIterator();
            while (it.next()) |k| self.allocator.free(k.*);
        }
        self.ctor_arities.deinit(self.allocator);
        {
            var it = self.fn_arities.keyIterator();
            while (it.next()) |k| self.allocator.free(k.*);
        }
        self.fn_arities.deinit(self.allocator);
        {
            var it = self.ctor_parents.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(@constCast(e.value_ptr.*));
            }
        }
        self.ctor_parents.deinit(self.allocator);
        {
            var it = self.fn_domains.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(@constCast(e.value_ptr.*));
            }
        }
        self.fn_domains.deinit(self.allocator);
        {
            var it = self.fn_domains_full.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(@constCast(e.value_ptr.*));
            }
        }
        self.fn_domains_full.deinit(self.allocator);
        {
            var it = self.ctor_results.iterator();
            while (it.next()) |e| {
                self.allocator.free(e.key_ptr.*);
                self.allocator.free(@constCast(e.value_ptr.*));
            }
        }
        self.ctor_results.deinit(self.allocator);
        var imp_it = self.imported_files.iterator();
        while (imp_it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.allocator.free(e.value_ptr.*);
        }
        self.imported_files.deinit(self.allocator);
        self.kanren.deinit();
        self.type_registry.deinit();
        self.hole_state.deinit();
    }

    pub fn ensureInit(self: *Heaven) void {
        _ = self;
    }

    pub fn registerClause(self: *Heaven, name: []const u8, patterns: []const Id, body: Id) !void {
        const owned_key = try self.engine.allocator.dupe(u8, name);
        const result = try self.engine.fns.getOrPut(self.engine.allocator, owned_key);
        if (result.found_existing) {
            self.engine.allocator.free(owned_key); // ← clé redondante, getOrPut garde l'existante
        } else {
            result.value_ptr.* = .{ .clauses = undefined, .num_clauses = 0 };
        }
        result.value_ptr.addClause(patterns, body);
    }

    /// v2e : remplace les `Tag.hole` par des `Tag.evar` frais,
    /// recursivement dans les `.apply`. Permet a `unify_proof.unify`
    /// de lier les indexes dependants (`_` devient evar). Sans cette
    /// transformation, `unify` ne voit que des holes et echoue
    /// silencieusement (aucun binding dans la substitution).
    fn holesToEvars(self: *Heaven, id: Id) HeavenError!Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        switch (node.tag) {
            .hole => return self.store.mkEvar() catch return error.OutOfMemory,
            .apply => {
                const new_fn = try self.holesToEvars(node.payload);
                const all = self.store.spanSliceConst(node.span_a);
                if (all.len < 1) return id;
                var args = try self.allocator.alloc(Id, all.len - 1);
                defer self.allocator.free(args);
                var changed = (new_fn != node.payload);
                for (all[1..], 0..) |a, i| {
                    args[i] = try self.holesToEvars(a);
                    if (args[i] != a) changed = true;
                }
                if (!changed) return id;
                return self.store.apply(new_fn, args) catch return error.OutOfMemory;
            },
            else => return id,
        }
    }

    pub fn eval(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t\n\r");
        if (trimmed.len == 0) return self.allocator.dupe(u8, "");

        // ─── v3a : mode strict — refus des noms cachés ───
        if (self.hidden_names.count() > 0) {
            var i: usize = 0;
            while (i < trimmed.len and
                (std.ascii.isAlphanumeric(trimmed[i]) or trimmed[i] == '_')) : (i += 1)
            {}
            const first_word = trimmed[0..i];
            if (first_word.len > 0 and self.hidden_names.contains(first_word)) {
                return std.fmt.allocPrint(
                    self.allocator,
                    "✗ '{s}' inaccessible (défini dans un module en mode strict ; utilisez <module>.{s})",
                    .{ first_word, first_word },
                );
            }
        }

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
            std.mem.startsWith(u8, trimmed, "rules");

        if (is_command) {
            // Le shell va traiter ces commandes ; on ne les évalue pas ici.
            return self.allocator.dupe(u8, trimmed);
        }

        // `meta` a été supprimé (2026-09-24). Alias vers `rules`.
        if (std.mem.eql(u8, trimmed, "meta") or
            std.mem.startsWith(u8, trimmed, "meta "))
        {
            return self.allocator.dupe(u8, "meta supprimé, utilisez rules");
        }

        // ─── export name1 [name2 ...] : marque des noms exportés ───
        // Hors import : no-op silencieux (utile pour taper `export x` au REPL).
        // Pendant un import : les noms sont déjà collectés par le pre-scan
        // de evalImport, donc ici on retourne juste un accusé.
        if (std.mem.startsWith(u8, trimmed, "export ")) {
            if (self.import_state) |_| {
                return self.allocator.dupe(u8, "✓ export (déjà pris en compte)");
            }
            return self.allocator.dupe(u8, "✗ export hors import (no-op)");
        }

        // ─── module M : ouvre un namespace ───
        if (std.mem.startsWith(u8, trimmed, "module ")) {
            const name = std.mem.trim(u8, trimmed["module ".len..], " \t");
            if (name.len == 0)
                return self.allocator.dupe(u8, "usage: module <nom>");
            if (self.current_module) |old| self.allocator.free(old);
            self.current_module = try self.allocator.dupe(u8, name);
            return std.fmt.allocPrint(self.allocator, "✓ module {s} ouvert", .{name});
        }

        // ─── import "path" [as Name] : charge un fichier dans un namespace ───
        if (std.mem.startsWith(u8, trimmed, "import ")) {
            return self.evalImport(trimmed["import ".len..]);
        }

        // ─── sig name : type ───
        if (std.mem.startsWith(u8, trimmed, "sig ")) {
            const rest = std.mem.trim(u8, trimmed["sig ".len..], " \t");
            const colon = std.mem.indexOfScalar(u8, rest, ':') orelse
                return self.allocator.dupe(u8, "usage: sig <name> : <type>");
            const sname = std.mem.trim(u8, rest[0..colon], " \t");
            const sty_str = std.mem.trim(u8, rest[colon + 1 ..], " \t");
            if (sname.len == 0 or sty_str.len == 0)
                return self.allocator.dupe(u8, "usage: sig <name> : <type>");

            var heads_buf = std.ArrayListUnmanaged(u8){};
            defer heads_buf.deinit(self.allocator);
            var full_buf = std.ArrayListUnmanaged(u8){};
            defer full_buf.deinit(self.allocator);

            var arity: u8 = 0;
            var depth: usize = 0;
            var start: usize = 0;
            var i: usize = 0;
            while (i < sty_str.len) {
                const c = sty_str[i];
                if (c == '(') { depth += 1; i += 1; continue; }
                if (c == ')') { if (depth > 0) depth -= 1; i += 1; continue; }
                if (c == '-' and i + 1 < sty_str.len and
                    sty_str[i + 1] == '>' and depth == 0)
                {
                    const domain_str = std.mem.trim(u8, sty_str[start..i], " \t");
                    const head = extractHeadName(domain_str);
                    if (heads_buf.items.len > 0)
                        try heads_buf.append(self.allocator, ' ');
                    try heads_buf.appendSlice(self.allocator, head);

                    // v2c : domaine complet (extrait le type d'un binder
                    // `(n : T)` → `T`).
                    const full_dom = extractBinderType(domain_str);
                    if (full_buf.items.len > 0)
                        try full_buf.append(self.allocator, 0x1f);
                    try full_buf.appendSlice(self.allocator, full_dom);

                    arity += 1;
                    i += 2;
                    start = i;
                    continue;
                }
                i += 1;
            }

            // fn_arities
            {
                const owned = try self.allocator.dupe(u8, sname);
                const gop = try self.fn_arities.getOrPut(self.allocator, owned);
                if (gop.found_existing) self.allocator.free(owned);
                gop.value_ptr.* = arity;
            }
            // fn_domains (heads space-separated)
            {
                const k = try self.allocator.dupe(u8, sname);
                const v = try self.allocator.dupe(u8, heads_buf.items);
                const gop = try self.fn_domains.getOrPut(self.allocator, k);
                if (gop.found_existing) {
                    self.allocator.free(k);
                    self.allocator.free(@constCast(gop.value_ptr.*));
                    gop.value_ptr.* = v;
                } else {
                    gop.value_ptr.* = v;
                }
            }
            // fn_domains_full (domaines complets, \x1f-separated)
            {
                const k = try self.allocator.dupe(u8, sname);
                const v = try self.allocator.dupe(u8, full_buf.items);
                const gop = try self.fn_domains_full.getOrPut(self.allocator, k);
                if (gop.found_existing) {
                    self.allocator.free(k);
                    self.allocator.free(@constCast(gop.value_ptr.*));
                    gop.value_ptr.* = v;
                } else {
                    gop.value_ptr.* = v;
                }
            }

            return std.fmt.allocPrint(self.allocator, "✓ sig {s} : {d} arg(s)", .{ sname, arity });
        }

        // ─── strict on|off : toggle du mode strict ───
        // En mode strict, les définitions faites pendant un `module M`
        // sont enregistrées seulement sous `M.x` (pas `x` nu).
        if (std.mem.startsWith(u8, trimmed, "strict ")) {
            const arg = std.mem.trim(u8, trimmed["strict ".len..], " \t");
            if (std.mem.eql(u8, arg, "on")) {
                self.strict_modules = true;
                return self.allocator.dupe(u8, "✓ strict mode on");
            } else if (std.mem.eql(u8, arg, "off")) {
                self.strict_modules = false;
                return self.allocator.dupe(u8, "✓ strict mode off");
            }
            return self.allocator.dupe(u8, "usage: strict on|off");
        }

        // Théorèmes / preuves / axiomes → chemin dédié (elab.zig + ProofCore)
        if (std.mem.startsWith(u8, trimmed, "theorem ")) {
            return self.evalTheorem(trimmed["theorem ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "prove ")) {
            return self.evalProve(trimmed["prove ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "skill ")) {
            return self.evalSkill(trimmed["skill ".len..]);
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
                const body = std.mem.trim(u8, rest_native[in_pos + 4 ..], " \t");

                if (std.mem.indexOfScalar(u8, binding, '=')) |eq| {
                    const name = std.mem.trim(u8, binding[0..eq], " \t:");
                    const val = std.mem.trim(u8, binding[eq + 1 ..], " \t");

                    var buf = std.ArrayListUnmanaged(u8){};
                    defer buf.deinit(self.allocator);
                    const head = if (qtt_kw) |kw|
                        try std.fmt.allocPrint(self.allocator, "let-{s}", .{kw})
                    else
                        try self.allocator.dupe(u8, "let");
                    defer self.allocator.free(head);
                    try buf.writer(self.allocator).print("({s} {s} {s} {s})", .{ head, name, val, body });

                    if (self.parseExpression(buf.items)) |id| {
                        // (à faire pour chaque parse réussi)
                        self.last_root_expr = id;
                        const result = self.interpForAssert(id) catch id;
                        return try expr.toStringInfix(self.store, result, self.allocator);
                    } else |err| switch (err) {
                        error.LinearViolation => return std.fmt.allocPrint(self.allocator, "linear violation: '{s}' declared {s}, used wrong number of times", .{ name, qtt_kw orelse "many" }),
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

        // Assertions natives :
        //   test "name": lhs == rhs
        //   test "name": assert_err expr
        //   assert_eq lhs == rhs
        //   assert_err expr
        if (std.mem.startsWith(u8, trimmed, "test \"") or
            std.mem.startsWith(u8, trimmed, "assert_eq ") or
            std.mem.startsWith(u8, trimmed, "assert_err "))
        {
            return self.evalAssertionNative(trimmed);
        }

        // ROUTING S-EXPR : (let ...) / (lambda ...) / (+ 1 2) / toute S-expr pure
        if (trimmed.len > 0 and trimmed[0] == '(') {
            // let/lambda → interpForAssert (engine ne gère pas bind au top-level)
            if (std.mem.indexOf(u8, trimmed, "let ") != null or
                std.mem.indexOf(u8, trimmed, "lambda") != null)
            {
                if (self.bridge.importExpr(trimmed)) |id| {
                    const result = self.interpForAssert(id) catch id;
                    return try expr.toStringInfix(self.store, result, self.allocator);
                } else |_| {}
            }
            // Autres S-expr : parse + engine.eval direct
            // Fix 2026-09-25 : utiliser parseExpression (pas bridge.importExpr).
            // Le bridge a son propre parser qui ne gere pas les lambdas
            // `(\x. ...)` : il produit apply(sym("\x.x"), ...) au lieu de
            // apply(lambda, ...), d'ou l'ArityMismatch en beta-reduction.
            if (self.parseExpression(trimmed)) |id| {
                self.engine.fuel = 1_000_000;
                const evaluated = self.engine.eval(id) catch |err| {
                    return std.fmt.allocPrint(self.allocator, "[eval error] {}", .{err});
                };
                const result_str = try expr.toStringInfix(self.store, evaluated, self.allocator);
                return result_str;
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

        // ─── Logic : fact / query (etape 1 pipeline logique unifie) ───
        if (std.mem.startsWith(u8, trimmed, "fact ")) {
            return self.evalFact(trimmed["fact ".len..]);
        }
        if (std.mem.startsWith(u8, trimmed, "query ")) {
            return self.evalQuery(trimmed["query ".len..]);
        }

        // ─── Déclaration de type : data Name params = C1 | C2 args | ... ───
        if (std.mem.startsWith(u8, trimmed, "data ")) {
            return self.evalDataDecl(trimmed["data ".len..]);
        }

        // ─── DÉFINITION DE FONCTION (syntaxe équationnelle) ───
        // Vérifier d'abord := (walrus) avant = pour éviter la confusion
        if (std.mem.indexOf(u8, trimmed, ":=")) |walrus_pos| {
            // := trouvé : convertir en = et traiter comme équation
            const before = trimmed[0..walrus_pos];
            const after = trimmed[walrus_pos + 2 ..];
            const converted = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ before, after });
            defer self.allocator.free(converted);
            // Re-parser la string convertie
            if (std.mem.indexOfScalar(u8, converted, '=')) |eq_pos| {
                const lhs = std.mem.trim(u8, converted[0..eq_pos], " ");
                const rhs = std.mem.trim(u8, converted[eq_pos + 1 ..], " ");
                if (!std.mem.startsWith(u8, lhs, "(") and lhs.len > 0 and rhs.len > 0) {
                    return self.evalEquation(lhs, rhs);
                }
            }
        } else if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
            // Pas de :=, chercher = simple
            // Vérifier que ce n'est pas == ou !=
            if (eq_pos + 1 < trimmed.len and trimmed[eq_pos + 1] == '=') {
                // C'est ==, pas une définition
            } else {
                const lhs = std.mem.trim(u8, trimmed[0..eq_pos], " ");
                const rhs = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " ");
                if (!std.mem.startsWith(u8, lhs, "(") and lhs.len > 0 and rhs.len > 0) {
                    return self.evalEquation(lhs, rhs);
                }
            }
        }

        if (std.mem.startsWith(u8, trimmed, "latex ")) {
            const inner = std.mem.trim(u8, trimmed["latex ".len..], " \t");
            if (self.ensureCommands()) |cmds| {
                return cmds.evalLatex(inner) catch |err| switch (err) {
                    error.OutOfMemory => HeavenError.OutOfMemory,
                    else => HeavenError.EvaluationFailed,
                };
            }
            return self.allocator.dupe(u8, "✗ commands unavailable");
        }

        // ─── ÉVALUATION GÉNÉRIQUE (infixe + application) ───
        // 0. Si la chaîne commence par '(', c'est du S-expr explicite.
        //    Parser via parseExpression puis engine.eval. Nécessaire pour
        //    les cas comme `((\x.x) 42)` où nativeToSExpr échoue (lexer
        //    rejette `\`) et où le fallback tokenize ne voit qu'UN token
        //    (à cause des parens imbriquées) et retourne la chaîne brute.
        if (trimmed[0] == '(') {
            const id = self.parseExpression(trimmed) catch {
                return self.allocator.dupe(u8, trimmed);
            };
            const evaluated = self.engine.eval(id) catch |err| {
                return std.fmt.allocPrint(self.allocator, "[eval error] {}", .{err});
            };
            return expr.toStringInfix(self.store, evaluated, self.allocator);
        }

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
                if (depth == 0 and !in_token) {
                    start = i;
                    in_token = true;
                }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, trimmed[start .. i + 1]);
                    in_token = false;
                    start = i + 1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, trimmed[start..i]);
                    in_token = false;
                }
                start = i + 1;
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
                if (std.mem.eql(u8, func_name, op)) {
                    is_op = true;
                    break;
                }
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
        // Atome nu : lookup dans l'env avant de retourner tel quel.
        // `x` doit résoudre vers la valeur liée par `let x := 5`.
        if (trimmed.len > 0 and trimmed[0] != '(' and
            std.mem.indexOfScalar(u8, trimmed, ' ') == null)
        {
            if (self.store.interner.lookup(trimmed)) |sym| {
                if (self.env.get(sym)) |val| {
                    return expr.toStringInfix(self.store, val, self.allocator);
                }
            }
        }
        return self.allocator.dupe(u8, trimmed);
    }

    /// import "path" [as Name] :
    ///   - lit le fichier ligne par ligne,
    ///   - évalue chaque ligne avec current_module = Name,
    ///   - les fn/let/theorem sont aliasés sous `Name.x` dans
    ///     engine.fns (fn/let) ou proof_core.theorems (theorem).
    /// Le nom de module est déduit du basename (sans extension) si
    /// `as Name` est absent.
    fn evalImport(self: *Heaven, src: []const u8) HeavenError![]u8 {
        return import_mod.evalImport(self, src) catch |err| switch (err) {
            error.OutOfMemory => HeavenError.OutOfMemory,
        };
    }

    /// Etape 1 pipeline logique unifie : `fact name arg1 arg2 ...`
    /// enregistre un fait dans le KB kanren. Chaque arg est une
    /// expression parseable (sym, lit, etc.).
    fn evalFact(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t");
        if (trimmed.len == 0)
            return self.allocator.dupe(u8, "usage: fact name arg1 arg2 ...");

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        const name = it.next() orelse
            return self.allocator.dupe(u8, "usage: fact name arg1 arg2 ...");

        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);

        while (it.next()) |tok| {
            const id = self.parseExpression(tok) catch |err| {
                return std.fmt.allocPrint(
                    self.allocator,
                    "\u{2717} fact {s}: arg '{s}' invalide: {}",
                    .{ name, tok, err },
                );
            };
            try args.append(self.allocator, id);
        }

        const rel = self.store.relation(name, args.items, &.{}) catch {
            return self.allocator.dupe(u8, "\u{2717} fact: construction relation echouee");
        };
        self.kanren.assertFact(rel) catch return error.OutOfMemory;

        return std.fmt.allocPrint(
            self.allocator,
            "\u{2713} fact {s} ({d} arg(s))",
            .{ name, args.items.len },
        );
    }

    /// Etape 1 pipeline logique unifie : `query name arg1 arg2 ...`
    /// ou `_` designe une variable de pattern. Retourne le nombre
    /// de solutions trouvees dans le KB kanren.
    fn evalQuery(self: *Heaven, src: []const u8) HeavenError![]u8 {
        const trimmed = std.mem.trim(u8, src, " \t");
        if (trimmed.len == 0)
            return self.allocator.dupe(u8, "usage: query name arg1 arg2 ...");

        var it = std.mem.tokenizeAny(u8, trimmed, " \t");
        const name = it.next() orelse
            return self.allocator.dupe(u8, "usage: query name arg1 arg2 ...");

        var args = std.ArrayListUnmanaged(Id){};
        defer args.deinit(self.allocator);
        var hole_idx: u32 = 0;

        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "_")) {
                const h = self.store.hole(hole_idx) catch return error.OutOfMemory;
                try args.append(self.allocator, h);
                hole_idx += 1;
            } else {
                const id = self.parseExpression(tok) catch |err| {
                    return std.fmt.allocPrint(
                        self.allocator,
                        "\u{2717} query {s}: arg '{s}' invalide: {}",
                        .{ name, tok, err },
                    );
                };
                try args.append(self.allocator, id);
            }
        }

        const pat = self.store.relation(name, args.items, &.{}) catch {
            return self.allocator.dupe(u8, "\u{2717} query: construction pattern echouee");
        };
        var stream = self.kanren.queryPattern(pat) catch return error.OutOfMemory;
        defer stream.deinit();

        if (stream.len() == 0)
            return std.fmt.allocPrint(self.allocator, "\u{2717} query {s}: aucune solution", .{name});

        return std.fmt.allocPrint(
            self.allocator,
            "\u{2713} query {s}: {d} solution(s)",
            .{ name, stream.len() },
        );
    }

    fn evalDataDecl(self: *Heaven, src: []const u8) HeavenError![]u8 {
        // Syntaxe supportée (v0) :
        //   data Name = C1 | C2 args | ...
        //   data Name a b = C1 | ...
        //   data Name (n : Nat) = C1 | ...
        //   data Name (n : Nat) (m : Nat) = ...
        //   Mix possible : data Name a (n : Nat) = ...
        const eq_pos = std.mem.indexOfScalar(u8, src, '=') orelse
            return self.allocator.dupe(u8, "syntax error in data: '=' manquant");
        const head = std.mem.trim(u8, src[0..eq_pos], " \t");
        const rhs = std.mem.trim(u8, src[eq_pos + 1 ..], " \t");

        // 1. Parse la partie gauche : nom + params.
        //    Parcours caractère par caractère pour gérer proprement
        //    les params parenthésés équilibrés (parenthèses imbriquées
        //    incluses : (n : Vec a), (f : a -> b), etc.).
        var cursor: usize = 0;

        // 1a. Nom du type : suite jusqu'au 1er espace ou '('.
        while (cursor < head.len and
            head[cursor] != ' ' and head[cursor] != '\t') : (cursor += 1)
        {}
        const type_name = head[0..cursor];
        if (type_name.len == 0)
            return self.allocator.dupe(u8, "syntax error: nom de type manquant");

        var params: std.ArrayListUnmanaged(type_registry_mod.ParamInfo) = .{};
        defer {
            for (params.items) |p| self.allocator.free(p.name);
            params.deinit(self.allocator);
        }

        // 1b. Params : boucle jusqu'à la fin de `head`.
        while (cursor < head.len) {
            // Skip les espaces.
            while (cursor < head.len and
                (head[cursor] == ' ' or head[cursor] == '\t')) : (cursor += 1)
            {}
            if (cursor >= head.len) break;

            if (head[cursor] == '(') {
                // Param typé : extraire le bloc parenthésé équilibré.
                const open = cursor;
                cursor += 1;
                var depth: usize = 1;
                while (cursor < head.len and depth > 0) : (cursor += 1) {
                    if (head[cursor] == '(') depth += 1 else if (head[cursor] == ')') depth -= 1;
                }
                if (depth != 0)
                    return self.allocator.dupe(u8, "syntax error: '(' non fermée dans params");
                // Bloc = head[open..cursor] (inclus les deux parenthèses).
                const inner = std.mem.trim(u8, head[open + 1 .. cursor - 1], " \t");
                const colon = std.mem.indexOfScalar(u8, inner, ':') orelse
                    return self.allocator.dupe(u8, "syntax error: ':' attendu dans (nom : Type)");
                const pname = std.mem.trim(u8, inner[0..colon], " \t");
                const ptype_str = std.mem.trim(u8, inner[colon + 1 ..], " \t");
                if (pname.len == 0 or ptype_str.len == 0)
                    return self.allocator.dupe(u8, "syntax error: param vide");

                const ptype = self.parseExpression(ptype_str) catch
                    return self.allocator.dupe(u8, "syntax error: type de param invalide");
                try params.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, pname),
                    .ty = ptype,
                });
            } else {
                // Param non typé : identifiant jusqu'au prochain espace ou '('.
                const start = cursor;
                while (cursor < head.len and
                    head[cursor] != ' ' and
                    head[cursor] != '\t' and
                    head[cursor] != '(') : (cursor += 1)
                {}
                if (cursor == start) break; // sécurité
                const pname = head[start..cursor];
                try params.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, pname),
                    .ty = null,
                });
            }
        }

        // 2. Parse les constructeurs.
        var ctors: std.ArrayListUnmanaged(type_registry_mod.CtorInfo) = .{};
        defer {
            for (ctors.items) |c| {
                self.allocator.free(c.name);
                self.allocator.free(c.arg_types);
            }
            ctors.deinit(self.allocator);
        }

        var it = std.mem.splitScalar(u8, rhs, '|');
        while (it.next()) |raw| {
            const ctor_str = std.mem.trim(u8, raw, " \t");
            if (ctor_str.len == 0) continue;

            // Nom = premier token.
            var name_end: usize = 0;
            while (name_end < ctor_str.len and
                ctor_str[name_end] != ' ' and
                ctor_str[name_end] != '\t') : (name_end += 1)
            {}
            const ctor_name = ctor_str[0..name_end];

            // Args (v0 : tokens séparés par espaces, en respectant les parens).
            var arg_types: std.ArrayListUnmanaged(Id) = .{};
            errdefer arg_types.deinit(self.allocator);

            var i = name_end;
            while (i < ctor_str.len) {
                while (i < ctor_str.len and
                    (ctor_str[i] == ' ' or ctor_str[i] == '\t')) : (i += 1)
                {}
                if (i >= ctor_str.len) break;

                if (ctor_str[i] == '(') {
                    var depth: usize = 1;
                    const arg_start = i;
                    i += 1;
                    while (i < ctor_str.len and depth > 0) : (i += 1) {
                        if (ctor_str[i] == '(') depth += 1 else if (ctor_str[i] == ')') depth -= 1;
                    }
                    const arg_str = ctor_str[arg_start..i];
                    const arg_id = self.parseExpression(arg_str) catch
                        try self.store.sym(arg_str);
                    try arg_types.append(self.allocator, arg_id);
                } else {
                    const arg_start = i;
                    while (i < ctor_str.len and
                        ctor_str[i] != ' ' and
                        ctor_str[i] != '\t') : (i += 1)
                    {}
                    const arg_str = ctor_str[arg_start..i];
                    const arg_id = self.parseExpression(arg_str) catch
                        try self.store.sym(arg_str);
                    try arg_types.append(self.allocator, arg_id);
                }
            }

            // Capture l'arité AVANT toOwnedSlice : la méthode vide la
            // liste, donc une lecture ultérieure donnerait 0.
            const arity: u8 = @intCast(arg_types.items.len);

            try ctors.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, ctor_name),
                .arity = arity,
                .arg_types = try arg_types.toOwnedSlice(self.allocator),
            });

            // v3a : en mode strict pendant un module, on enregistre
            // le ctor sous `M.Ctor` au lieu de `Ctor`. Sinon comportement
            // historique.
            const in_strict_module = self.strict_modules and self.current_module != null;

            if (in_strict_module) {
                const qualified = try std.fmt.allocPrint(
                    self.allocator, "{s}.{s}", .{ self.current_module.?, ctor_name },
                );
                const owned = qualified;
                const gop = try self.engine.fns.getOrPut(self.allocator, owned);
                if (gop.found_existing) {
                    self.allocator.free(owned);
                } else {
                    gop.value_ptr.* = .{ .clauses = undefined, .num_clauses = 0 };
                }
                gop.value_ptr.ctor_arity = arity;

                // Cacher le nom nu
                const hidden_key = try self.allocator.dupe(u8, ctor_name);
                const hgop = self.hidden_names.getOrPut(self.allocator, hidden_key) catch {
                    self.allocator.free(hidden_key);
                    return error.OutOfMemory;
                };
                if (hgop.found_existing) self.allocator.free(hidden_key);
            } else {
                const owned = try self.allocator.dupe(u8, ctor_name);
                const gop = try self.engine.fns.getOrPut(self.allocator, owned);
                if (gop.found_existing) {
                    self.allocator.free(owned);
                } else {
                    gop.value_ptr.* = .{ .clauses = undefined, .num_clauses = 0 };
                }
                gop.value_ptr.ctor_arity = arity;
            }

            // v2a : peupler ctor_arities (nom → arité) — inconditionnel.
            // Utilisé par evalEquation pour vérifier la forme des patterns.
            {
                const k = try self.allocator.dupe(u8, ctor_name);
                const g = try self.ctor_arities.getOrPut(self.allocator, k);
                if (g.found_existing) self.allocator.free(k);
                g.value_ptr.* = arity;
            }
            // v2b : parent du ctor (nom du type déclaré).
            {
                const k = try self.allocator.dupe(u8, ctor_name);
                const v = try self.allocator.dupe(u8, type_name);
                const g = try self.ctor_parents.getOrPut(self.allocator, k);
                if (g.found_existing) {
                    self.allocator.free(k);
                    self.allocator.free(@constCast(g.value_ptr.*));
                    g.value_ptr.* = v;
                } else {
                    g.value_ptr.* = v;
                }
            }

            // v2d : forme du résultat du ctor pour les types
            // paramétrés (convention pour types à un seul paramètre
            // indexé, ex. Vec) :
            //   arity 0  → "<TypeName> zero"
            //   arity >0 → "<TypeName> (succ _)"
            if (params.items.len >= 1) {
                const result_str = if (arity == 0)
                    try std.fmt.allocPrint(self.allocator, "{s} zero", .{type_name})
                else
                    try std.fmt.allocPrint(self.allocator, "{s} (succ _)", .{type_name});
                const k = try self.allocator.dupe(u8, ctor_name);
                const g = try self.ctor_results.getOrPut(self.allocator, k);
                if (g.found_existing) {
                    self.allocator.free(k);
                    self.allocator.free(@constCast(g.value_ptr.*));
                    g.value_ptr.* = result_str;
                } else {
                    g.value_ptr.* = result_str;
                }
            }
        }

        // 3. Enregistre dans le TypeRegistry.
        const info = type_registry_mod.TypeInfo{
            .name = try self.allocator.dupe(u8, type_name),
            .params = try params.toOwnedSlice(self.allocator),
            .ctors = try ctors.toOwnedSlice(self.allocator),
        };
        try self.type_registry.register(info);

        return std.fmt.allocPrint(
            self.allocator,
            "✓ data {s} registered ({d} param(s), {d} constructor(s))",
            .{ type_name, info.params.len, info.ctors.len },
        );
    }

    const CtorKind = enum { base, step, unparam };
    const DomainKind = enum { base, step, any, unparam };

    /// v2c : classifie un ctor d'un type paramétré.
    /// - arity 0 → base (`Nil : Vec zero`)
    /// - arity > 0 → step (`Cons : Vec (succ _)`)
    /// - type non paramétré → unparam (pas de convention)
    fn ctorKind(self: *Heaven, ctor: []const u8) CtorKind {
        const arity = self.ctor_arities.get(ctor) orelse return .unparam;
        const parent = self.ctor_parents.get(ctor) orelse return .unparam;
        const info = self.type_registry.get(parent) orelse return .unparam;
        if (info.params.len == 0) return .unparam;
        return if (arity == 0) .base else .step;
    }

    /// v2c : classifie un domaine `Vec zero` (base) vs `Vec (succ _)` (step).
    fn domainKind(self: *Heaven, domain: Id, parent_name: []const u8) DomainKind {
        if (domain >= self.store.len()) return .any;
        const node = self.store.get(domain);
        if (node.tag == .sym) {
            const nm = self.store.interner.resolve(node.payload);
            if (std.mem.eql(u8, nm, parent_name)) return .unparam;
            return .any;
        }
        if (node.tag != .apply) return .any;
        const head = self.store.get(node.payload);
        if (head.tag != .sym) return .any;
        const head_name = self.store.interner.resolve(head.payload);
        if (!std.mem.eql(u8, head_name, parent_name)) return .any;
        const args = self.store.spanSliceConst(node.span_a);
        // args[0] = head (sym Parent), args[1] = index
        if (args.len < 2) return .any;
        const idx = args[1];
        if (idx >= self.store.len()) return .any;
        const idx_node = self.store.get(idx);
        if (idx_node.tag == .sym) {
            const nm = self.store.interner.resolve(idx_node.payload);
            if (std.mem.eql(u8, nm, "zero")) return .base;
            return .any;
        }
        if (idx_node.tag == .apply) {
            const fnode = self.store.get(idx_node.payload);
            if (fnode.tag == .sym) {
                const nm = self.store.interner.resolve(fnode.payload);
                if (std.mem.eql(u8, nm, "succ")) return .step;
            }
            return .any;
        }
        return .any;
    }

    /// v2c : vérifie que `ctor` peut matcher un domaine décrit par `domain_str`.
    /// Retourne true si compatible (ou si on ne peut pas trancher).
    fn checkCtorDomainKind(self: *Heaven, ctor: []const u8, domain_str: []const u8) bool {
        const ck = self.ctorKind(ctor);
        if (ck == .unparam) return true;
        const parent = self.ctor_parents.get(ctor) orelse return true;
        const d_id = self.parseExpression(domain_str) catch return true;
        const dk = self.domainKind(d_id, parent);
        if (dk == .any or dk == .unparam) return true;
        return switch (ck) {
            .base => dk == .base,
            .step => dk == .step,
            .unparam => true,
        };
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
                if (depth == 0 and !in_token) {
                    start = i;
                    in_token = true;
                }
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0 and in_token) {
                    try tokens.append(self.allocator, lhs[start .. i + 1]);
                    in_token = false;
                    start = i + 1;
                }
            } else if (c == ' ' and depth == 0) {
                if (in_token) {
                    try tokens.append(self.allocator, lhs[start..i]);
                    in_token = false;
                }
                start = i + 1;
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

        // ─── v2a : vérification d'arité / forme des patterns ───
        // Si une signature a été déclarée via `sig name : ...`, vérifier :
        //  1. le nombre de patterns = arité attendue
        //  2. chaque pattern `(Ctor args)` a le bon nombre d'args
        if (self.fn_arities.get(name)) |expected| {
            if (patterns.items.len != expected) {
                return std.fmt.allocPrint(
                    self.allocator,
                    "✗ arity mismatch : {s} attend {d} pattern(s), reçu {d}",
                    .{ name, expected, patterns.items.len },
                );
            }
        }
        for (patterns.items) |p| {
            const pn = self.store.get(p);
            if (pn.tag != .apply) continue;
            const p_all = self.store.spanSliceConst(pn.span_a);
            if (p_all.len < 1) continue;
            const head_node = self.store.get(pn.payload);
            if (head_node.tag != .sym) continue;
            const head_name = self.store.interner.resolve(head_node.payload);
            if (self.ctor_arities.get(head_name)) |ctor_arity| {
                const n_args = p_all.len - 1;
                if (n_args != ctor_arity) {
                    return std.fmt.allocPrint(
                        self.allocator,
                        "✗ ctor {s} attend {d} arg(s), reçu {d}",
                        .{ head_name, ctor_arity, n_args },
                    );
                }
            }
        }

        // ─── v2b : vérifier que chaque ctor pattern appartient au bon type ───
        if (self.fn_domains.get(name)) |heads_str| {
            var hit = std.mem.tokenizeScalar(u8, heads_str, ' ');
            var idx: usize = 0;
            while (hit.next()) |expected_head| : (idx += 1) {
                if (idx >= patterns.items.len) break;
                const p_id = patterns.items[idx];
                const pn2 = self.store.get(p_id);
                var p_ctor_name: ?[]const u8 = null;
                if (pn2.tag == .sym) {
                    const nm = self.store.interner.resolve(pn2.payload);
                    if (self.ctor_parents.contains(nm)) p_ctor_name = nm;
                } else if (pn2.tag == .apply) {
                    const fn2 = self.store.get(pn2.payload);
                    if (fn2.tag == .sym) {
                        const nm = self.store.interner.resolve(fn2.payload);
                        if (self.ctor_parents.contains(nm)) p_ctor_name = nm;
                    }
                }
                if (p_ctor_name) |cn| {
                    const parent = self.ctor_parents.get(cn) orelse continue;
                    if (!std.mem.eql(u8, parent, expected_head)) {
                        return std.fmt.allocPrint(
                            self.allocator,
                            "✗ pattern {d} : ctor {s} appartient à {s}, attendu {s}",
                            .{ idx + 1, cn, parent, expected_head },
                        );
                    }
                }
            }
        }

        // ─── v2c : vérifier la compatibilité base/step avec le domaine ───
        if (self.fn_domains_full.get(name)) |domains_str| {
            var hit = std.mem.tokenizeScalar(u8, domains_str, 0x1f);
            var idx: usize = 0;
            while (hit.next()) |domain_str| : (idx += 1) {
                if (idx >= patterns.items.len) break;
                const p_id = patterns.items[idx];
                const pn3 = self.store.get(p_id);
                var p_ctor_name: ?[]const u8 = null;
                if (pn3.tag == .sym) {
                    const nm = self.store.interner.resolve(pn3.payload);
                    if (self.ctor_parents.contains(nm)) p_ctor_name = nm;
                } else if (pn3.tag == .apply) {
                    const fn3 = self.store.get(pn3.payload);
                    if (fn3.tag == .sym) {
                        const nm = self.store.interner.resolve(fn3.payload);
                        if (self.ctor_parents.contains(nm)) p_ctor_name = nm;
                    }
                }
                if (p_ctor_name) |cn| {
                    if (!self.checkCtorDomainKind(cn, domain_str)) {
                        return std.fmt.allocPrint(
                            self.allocator,
                            "✗ pattern {d} : {s} incompatible avec le domaine '{s}'",
                            .{ idx + 1, cn, domain_str },
                        );
                    }
                }
            }
        }

        // ─── v2d : unification d'indexes dépendants ───
        // Pour chaque pattern ctor dont le parent est un type paramétré,
        // on unifie la forme du résultat du ctor (`Vec (succ _)`) avec
        // le domaine déclaré (`Vec (succ n)`), accumulant les bindings
        // dans `subst_v2d`. Le body est ensuite instancié sous cette
        // substitution.
        //
        // Best-effort : si l'unification échoue ou n'est pas applicable
        // (parse error, côté non reconnu), on ne rejette pas — v2c a
        // déjà validé la compatibilité base/step.
        var subst_v2d: unify_proof_mod.Subst = .{};
        defer subst_v2d.deinit(self.allocator);
        const uctx_v2d = unify_proof_mod.Ctx{
            .store = self.store,
            .allocator = self.allocator,
        };
        if (self.fn_domains_full.get(name)) |domains_str_v2d| {
            var hit_v2d = std.mem.tokenizeScalar(u8, domains_str_v2d, 0x1f);
            var idx_v2d: usize = 0;
            while (hit_v2d.next()) |domain_str_v2d| : (idx_v2d += 1) {
                if (idx_v2d >= patterns.items.len) break;
                const p_id_v2d = patterns.items[idx_v2d];
                const pn_v2d = self.store.get(p_id_v2d);
                var ctor_name_v2d: ?[]const u8 = null;
                if (pn_v2d.tag == .sym) {
                    const nm = self.store.interner.resolve(pn_v2d.payload);
                    if (self.ctor_results.contains(nm)) ctor_name_v2d = nm;
                } else if (pn_v2d.tag == .apply) {
                    const fn_v2d = self.store.get(pn_v2d.payload);
                    if (fn_v2d.tag == .sym) {
                        const nm = self.store.interner.resolve(fn_v2d.payload);
                        if (self.ctor_results.contains(nm)) ctor_name_v2d = nm;
                    }
                }
                if (ctor_name_v2d) |cn| {
                    const result_str = self.ctor_results.get(cn) orelse continue;
                    const result_raw = self.parseExpression(result_str) catch continue;
                    const domain_raw = self.parseExpression(domain_str_v2d) catch continue;
                    // v2e : holes -> evars pour que unify puisse lier.
                    const result_id = self.holesToEvars(result_raw) catch continue;
                    const domain_id = self.holesToEvars(domain_raw) catch continue;
                    _ = unify_proof_mod.unify(&uctx_v2d, result_id, domain_id, &subst_v2d) catch continue;
                }
            }
        }
        const body_used: Id = if (subst_v2d.count() > 0)
            (unify_proof_mod.instantiate(&uctx_v2d, body, &subst_v2d) catch body)
        else
            body;

        // v3a : en mode strict ET pendant un module, on n'enregistre
        // PAS le nom nu. On enregistre seulement l'alias `M.name` plus bas,
        // et on trace le nom nu dans hidden_names pour le bloquer au REPL.
        const in_strict_module = self.strict_modules and self.current_module != null;
        if (!in_strict_module) {
            try self.registerClause(name, patterns.items, body_used);
        } else {
            const owned = try self.allocator.dupe(u8, name);
            const gop = self.hidden_names.getOrPut(self.allocator, owned) catch {
                self.allocator.free(owned);
                return error.OutOfMemory;
            };
            if (gop.found_existing) self.allocator.free(owned);
        }

        // Si un module est ouvert (import en cours), aliaser sous `M.name`,
        // sauf si le fichier importé déclare des exports et que ce nom n'en
        // fait pas partie (v2a).
        if (self.current_module) |m| {
            const should_alias = if (self.import_state) |ist|
                ist.isExported(name)
            else
                true;
            if (should_alias) {
                const qualified = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{s}",
                    .{ m, name },
                );
                defer self.allocator.free(qualified);
                self.registerClause(qualified, patterns.items, body_used) catch {};
            }
        }

        const subst_n = subst_v2d.count();
        if (subst_n > 0) {
            return std.fmt.allocPrint(
                self.allocator,
                "✓ clause enregistrée pour '{s}' (subst: {d})",
                .{ name, subst_n },
            );
        }
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
        const id = self.expr_parser.parseExpression(input) catch |err| {
            return switch (err) {
                error.InvalidInput => error.InvalidInput,
                error.InvalidSyntax => error.InvalidSyntax,
                error.InvalidLambda => error.InvalidLambda,
                error.LinearViolation => error.LinearViolation,
                error.OutOfMemory => error.OutOfMemory,
                error.StackOverflow => error.StackOverflow,
                else => error.UnsupportedExpr,
            };
        };
        return id;
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
        var trimmed = std.mem.trim(u8, src, " \t");
        if (std.mem.startsWith(u8, trimmed, "skill ")) {
            trimmed = std.mem.trim(u8, trimmed["skill ".len..], " \t");
        }
        if (trimmed.len == 0)
            return self.allocator.dupe(u8, "usage: skill <name> [on <var>]");

        var name: []const u8 = trimmed;
        var var_name: []const u8 = "n";
        if (std.mem.indexOf(u8, name, " on ")) |pos| {
            var_name = std.mem.trim(u8, name[pos + 4 ..], " \t");
            name = std.mem.trim(u8, name[0..pos], " \t");
        }
        if (name.len == 0)
            return self.allocator.dupe(u8, "usage: skill <name> [on <var>]");

        const thm_name = self.active_theorem orelse
            return self.allocator.dupe(u8, "✗ no active theorem (tapez `theorem ...` d'abord)");

        _ = self.ensureCommands();
        const sk = self.skills orelse
            return self.allocator.dupe(u8, "✗ skills unavailable");
        const skill = sk.get(name) orelse
            return std.fmt.allocPrint(self.allocator, "✗ unknown skill: {s}", .{name});
        const body = skill.body;

        // Substitution {var}
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        var i: usize = 0;
        while (i < body.len) {
            if (std.mem.startsWith(u8, body[i..], "{var}")) {
                try buf.appendSlice(self.allocator, var_name);
                i += 5;
            } else {
                try buf.append(self.allocator, body[i]);
                i += 1;
            }
        }

        const session = try self.startProof(thm_name);
        defer session.deinit();

        const report = session.applyLine(buf.items) catch |err| {
            return std.fmt.allocPrint(self.allocator, "✗ skill error: {}", .{err});
        };
        defer self.allocator.free(report);

        const proved = try session.finish();
        if (proved) {
            return std.fmt.allocPrint(
                self.allocator,
                "✓ [{s}] '{s}' proved via skill\n{s}",
                .{ name, thm_name, report },
            );
        }
        return std.fmt.allocPrint(
            self.allocator,
            "✗ [{s}] '{s}' unproved\n{s}",
            .{ name, thm_name, report },
        );
    }
    // ═══ Tactics v1 ═══

    /// Construit un Goal à partir du statement textuel du théorème, parse
    /// un bloc de tactiques `t1; t2; ...`, l'applique, et retourne un
    /// rapport. Si tous les buts sont résolus, marque le théorème comme
    /// vérifié dans ProofCore.
    pub fn runTacticsBlock(
        self: *Heaven,
        theorem_name: []const u8,
        block_src: []const u8,
    ) HeavenError![]u8 {
        _ = self.ensureCommands();
        const pc = self.proof_core_inst orelse
            return error.Unexpected;
        const thm = pc.theorems.getPtr(theorem_name) orelse
            return error.UnknownVariable;

        // 1. Découper "lhs = rhs"
        const stmt = thm.statement;
        const eq_pos = std.mem.indexOf(u8, stmt, " = ") orelse
            return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " \t");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 3 ..], " \t");

        const lhs_id = try self.parseExpression(lhs_str);
        const rhs_id = try self.parseExpression(rhs_str);
        const eq_sym = try self.store.sym("=");
        const target = try self.store.apply(eq_sym, &.{ lhs_id, rhs_id });

        // 2. ProofState + aréna
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        var state = proof_state_mod.ProofState.init(
            self.allocator,
            &arena,
            self.store,
            theorem_name,
        );
        defer state.deinit();

        try state.appendGoal(.{
            .hyps = try state.dupHyps(
                &.{},
            ),
            .target = target,
            .label = try state.dupLabel("main"),
        });

        // 3. Parse + apply
        const tactic = tactics_mod.parseTacticsBlock(arena.allocator(), block_src) catch |err| {
            return std.fmt.allocPrint(self.allocator, "✗ tactic parse error: {}\n", .{err});
        };

        var ctx = tactics_mod.TacticCtx{
            .allocator = self.allocator,
            .store = self.store,
            .heaven = @ptrCast(self),
            .simplifyFn = tacticsSimplifyCb,
            .eqFn = tacticsEqCb,
            .peanoFn = tacticsPeanoCb,
            .substFn = tacticsSubstCb,
        };

        tactics_mod.applyTactic(&state, tactic, &ctx) catch |err| {
            const pp = try state.pp(self.allocator);
            defer self.allocator.free(pp);
            return std.fmt.allocPrint(self.allocator, "✗ tactic failed: {} — {d} goal(s) remaining:\n{s}", .{ err, state.goals.items.len, pp });
        };

        // 4. Vérifier
        if (state.solved()) {
            thm.verified = true;
            return std.fmt.allocPrint(self.allocator, "✓ [{s}] proved (tactics)\n", .{theorem_name});
        }
        const pp = try state.pp(self.allocator);
        defer self.allocator.free(pp);
        return std.fmt.allocPrint(self.allocator, "✗ {d} goal(s) remaining:\n{s}", .{ state.goals.items.len, pp });
    }

    // ─── Callbacks pour TacticCtx ───

    fn tacticsSimplifyCb(ctx: *tactics_mod.TacticCtx, input: []const u8) anyerror![]u8 {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return self.simplify(input);
    }

    fn tacticsEqCb(ctx: *tactics_mod.TacticCtx, a: Id, b: Id) anyerror!bool {
        if (a == b) return true;
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return expr.structuralEql(self.store, a, b);
    }

    fn tacticsPeanoCb(ctx: *tactics_mod.TacticCtx, k: i64) anyerror!Id {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        if (k <= 0) return self.store.sym("zero");
        const inner = try tacticsPeanoCb(ctx, k - 1);
        return self.store.call("succ", &.{inner});
    }

    fn tacticsSubstCb(
        ctx: *tactics_mod.TacticCtx,
        e: Id,
        name: []const u8,
        repl: Id,
    ) anyerror!Id {
        const self: *Heaven = @ptrCast(@alignCast(ctx.heaven));
        return substSymByName(self.store, self.allocator, e, name, repl);
    }

    // ═══ REPL interactif de preuve (ProofSession) ═══

    pub const ProofSession = struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        state: proof_state_mod.ProofState,
        ctx: tactics_mod.TacticCtx,
        theorem_name: []const u8,
        heaven: *Heaven,

        pub fn deinit(self: *ProofSession) void {
            self.state.deinit();
            self.arena.deinit();
            self.allocator.destroy(self.arena);
            self.allocator.free(self.theorem_name);
            self.allocator.destroy(self);
        }

        /// Parse une ligne (peut contenir plusieurs tactiques séparées par `;`)
        /// et l'applique. Retourne un rapport formatté pour affichage.
        pub fn applyLine(self: *ProofSession, line: []const u8) ![]u8 {
            const tactic = tactics_mod.parseTacticsBlock(self.arena.allocator(), line) catch |err| {
                return std.fmt.allocPrint(self.allocator, "✗ parse error: {}\n", .{err});
            };
            tactics_mod.applyTactic(&self.state, tactic, &self.ctx) catch |err| {
                const state_pp = try self.state.pp(self.allocator);
                defer self.allocator.free(state_pp);
                return std.fmt.allocPrint(self.allocator, "✗ {}\n{s}", .{ err, state_pp });
            };
            if (self.state.solved()) {
                return self.allocator.dupe(u8, "✓ All goals solved. Tapez '}' ou 'qed' pour valider.\n");
            }
            const state_pp = try self.state.pp(self.allocator);
            defer self.allocator.free(state_pp);
            return std.fmt.allocPrint(self.allocator, "{s}", .{state_pp});
        }

        /// Vérifie que tous les buts sont résolus et marque le théorème.
        pub fn finish(self: *ProofSession) !bool {
            if (!self.state.solved()) return false;
            _ = self.heaven.ensureCommands();
            const pc = self.heaven.proof_core_inst orelse return false;
            const thm = pc.theorems.getPtr(self.theorem_name) orelse return false;
            thm.verified = true;
            return true;
        }

        pub fn pp(self: *ProofSession) ![]u8 {
            return self.state.pp(self.allocator);
        }
    };

    /// Démarre une session de preuve interactive pour un théorème déjà déclaré.
    /// L'appelant est responsable d'appeler session.deinit().
    pub fn startProof(self: *Heaven, theorem_name: []const u8) HeavenError!*ProofSession {
        _ = self.ensureCommands();
        const pc = self.proof_core_inst orelse return error.Unexpected;
        const thm = pc.theorems.getPtr(theorem_name) orelse return error.UnknownVariable;

        // Parse "lhs = rhs" (au premier " = ")
        const stmt = thm.statement;
        const eq_pos = std.mem.indexOf(u8, stmt, " = ") orelse return error.InvalidSyntax;
        const lhs_str = std.mem.trim(u8, stmt[0..eq_pos], " \t");
        const rhs_str = std.mem.trim(u8, stmt[eq_pos + 3 ..], " \t");

        const lhs_id = try self.parseExpression(lhs_str);
        const rhs_id = try self.parseExpression(rhs_str);
        const eq_sym = try self.store.sym("=");
        const target = try self.store.apply(eq_sym, &.{ lhs_id, rhs_id });

        const session = try self.allocator.create(ProofSession);
        errdefer self.allocator.destroy(session);

        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);

        session.* = .{
            .allocator = self.allocator,
            .arena = arena,
            .state = proof_state_mod.ProofState.init(
                self.allocator,
                arena,
                self.store,
                theorem_name,
            ),
            .ctx = undefined,
            .theorem_name = try self.allocator.dupe(u8, theorem_name),
            .heaven = self,
        };
        errdefer self.allocator.free(session.theorem_name);

        try session.state.appendGoal(.{
            .hyps = try session.state.dupHyps(&.{}),
            .target = target,
            .label = try session.state.dupLabel("main"),
        });

        session.ctx = tactics_mod.TacticCtx{
            .allocator = self.allocator,
            .store = self.store,
            .heaven = @ptrCast(self),
            .simplifyFn = tacticsSimplifyCb,
            .eqFn = tacticsEqCb,
            .peanoFn = tacticsPeanoCb,
            .substFn = tacticsSubstCb,
        };

        return session;
    }

    pub fn evalProve(self: *Heaven, src: []const u8) HeavenError![]u8 {
        // ─── Tactics v1 : `prove <name> by { t1; t2; ... }` ───
        // Intercepté AVANT le chemin classique pour ne pas casser
        // `by simplify` / `by eval` / `by induction x` (compat).
        if (std.mem.indexOf(u8, src, " by {")) |pos| {
            const name = std.mem.trim(u8, src[0..pos], " \t");
            if (name.len == 0) return error.InvalidSyntax;
            const rest = src[pos + " by {".len ..];
            const close = std.mem.lastIndexOfScalar(u8, rest, '}') orelse
                return error.InvalidSyntax;
            const body = rest[0..close];
            return self.runTacticsBlock(name, body);
        }

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
            const result = cmds.evalTheorem(src) catch |err| {
                return switch (err) {
                    error.OutOfMemory => HeavenError.OutOfMemory,
                    else => HeavenError.EvaluationFailed,
                };
            };

            // Si un module est ouvert, aliaser le théorème sous `M.name`.
            // IMPORTANT : dupliquer `statement` pour que proof_core.deinit
            // puisse libérer chaque entrée indépendamment. `name` = clé,
            // libérée via entry.key_ptr.* (pas de partage).
            if (self.current_module) |m| {
                if (std.mem.indexOfScalar(u8, src, ':')) |colon| {
                    const thm_name = std.mem.trim(u8, src[0..colon], " \t");
                    const should_alias = if (self.import_state) |ist|
                        ist.isExported(thm_name)
                    else
                        true;
                    if (thm_name.len > 0 and should_alias) {
                        if (self.proof_core_inst) |pc| {
                            if (pc.theorems.getPtr(thm_name)) |thm| {
                                const qualified = std.fmt.allocPrint(
                                    self.allocator,
                                    "{s}.{s}",
                                    .{ m, thm_name },
                                ) catch return result;

                                const owned_stmt = self.allocator.dupe(u8, thm.statement) catch {
                                    self.allocator.free(qualified);
                                    return result;
                                };

                                const gop = pc.theorems.getOrPut(self.allocator, qualified) catch {
                                    self.allocator.free(qualified);
                                    self.allocator.free(owned_stmt);
                                    return result;
                                };
                                if (gop.found_existing) {
                                    self.allocator.free(qualified);
                                    self.allocator.free(owned_stmt);
                                } else {
                                    gop.value_ptr.* = .{
                                        .name = qualified, // = clé
                                        .statement = owned_stmt, // dupe indépendante
                                        .lhs = thm.lhs,
                                        .rhs = thm.rhs,
                                        .proof = thm.proof,
                                        .verified = thm.verified,
                                    };
                                }
                            }
                        }
                    }
                }
            }
            return result;
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
        if (platform.target.is_debug and id == 0xAAAAAAAA) {
            @panic("poison Id at evaluate entry");
        }

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

        // ─── Trou : résolu ou erreur ───
        if (node.tag == .hole) {
            if (self.hole_state.resolve(node.payload)) |resolved| {
                return resolved;
            }
            return error.UnboundHole;
        }

        // ─── Cas .bind Core : (bind name [val, body]) ───
        if (node.tag == .bind) {
            const args = self.store.spanSliceConst(node.span_a);
            if (args.len == 0) return id;
            const val = self.evaluateExpr(args[0]) catch args[0];
            try self.env.put(node.payload, val);
            defer self.env.delete(node.payload);
            if (args.len >= 2) {
                return self.interpForAssert(args[1]) catch id;
            }
            return val;
        }

        if (node.tag != .apply) {
            return self.evaluateExpr(id) catch id; // Fix 1 : syms nus évalués
        }

        const all = self.store.spanSliceConst(node.span_a);
        if (all.len < 1) return id;
        const args = all[1..];

        const fnode = self.store.get(node.payload);

        //platform.dbg("[preFix2] func_tag={s} args.len={d}\n", .{ @tagName(fnode.tag), args.len });

        // Fix 2a : FUNC = LAMBDA NODE (lambdaNative : payload=param, span_a=[body])
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

        // Fix 2b : FUNC = APPLY sym"lambda" (structure alternative du parser)
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

        // Fix 3 : FONCTION ENV-BOUND (f arg) où f est une lambda dans l'env
        // L'engine ne cherche l'env que pour les syms nus — pas les appels.
        {
            //platform.dbg("[fix3-enter] fnode.payload={d} env has: ", .{fnode.payload});
            if (self.env.get(fnode.payload)) |bound| {
                platform.dbg("YES bound.tag={s}\n", .{@tagName(self.store.get(bound).tag)});
                // bound = la valeur liée (peut être un nœud .lambda !)
                const bound_node = self.store.get(bound);

                // Cas .lambda : appliquer directement (payload=param, span_a=[body])
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

                // Cas .apply sym"lambda" (structure alternative)
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

        if (fnode.tag != .sym) {
            return self.evaluateExpr(id) catch id;
        }
        const head = self.store.interner.resolve(fnode.payload);

        // DUMP : la structure complète du nœud
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
        if (node.tag == .bind) {
            if (args.len == 2) {
                const val = self.evaluateExpr(args[0]) catch args[0];
                try self.env.put(node.payload, val);
                defer self.env.delete(node.payload);
                return self.interpForAssert(args[1]) catch id;
            }
        }

        // ═══ 2. LAMBDA SYMBOLE : ((lambda x body) arg) — le func est apply(sym"lambda") ═══
        {
            const func_node = self.store.get(node.payload);
            if (func_node.tag == .apply) {
                const inner = self.store.get(func_node.payload);
                if (inner.tag == .sym and std.mem.eql(u8, self.store.interner.resolve(inner.payload), "lambda")) {
                    const lam_args = self.store.spanSliceConst(func_node.span_a);
                    if (lam_args.len == 3) { // [lambda, param, body]
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
        } else |_| {
            //platform.dbg("[interp-err] id={d} err={}\n", .{ id, err });
        }

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

    /// Cherche ` == ` au niveau 0 (hors parenthèses et strings).
    fn splitTopLevelEq(inner: []const u8) ?struct { a: []const u8, b: []const u8 } {
        var depth: usize = 0;
        var in_str = false;
        var i: usize = 0;
        while (i + 3 < inner.len) : (i += 1) {
            const c = inner[i];
            if (c == '"') {
                in_str = !in_str;
                continue;
            }
            if (in_str) continue;
            if (c == '(') {
                depth += 1;
                continue;
            }
            if (c == ')') {
                if (depth > 0) depth -= 1;
                continue;
            }
            if (depth == 0 and c == ' ' and
                inner[i + 1] == '=' and inner[i + 2] == '=' and inner[i + 3] == ' ')
            {
                const a = std.mem.trim(u8, inner[0..i], " \t");
                const b = std.mem.trim(u8, inner[i + 4 ..], " \t");
                if (a.len > 0 and b.len > 0) return .{ .a = a, .b = b };
            }
        }
        return null;
    }

    fn evalAssertionNative(self: *Heaven, input: []const u8) HeavenError![]u8 {
        // ─── test "name": body ───
        if (std.mem.startsWith(u8, input, "test \"")) {
            const after_test = input["test \"".len..];
            const quote_end = std.mem.indexOfScalar(u8, after_test, '"') orelse
                return self.allocator.dupe(u8, "✗ test: quote manquante");
            const name = after_test[0..quote_end];
            const after_name = std.mem.trimLeft(u8, after_test[quote_end + 1 ..], " \t");
            if (after_name.len == 0 or after_name[0] != ':')
                return self.allocator.dupe(u8, "✗ test: ':' manquant après le nom");
            const body = std.mem.trim(u8, after_name[1..], " \t");

            // Sous-cas : test "name": assert_err expr
            if (std.mem.startsWith(u8, body, "assert_err ")) {
                const res = try self.evalAssertionNative(body);
                defer self.allocator.free(res);
                return std.fmt.allocPrint(self.allocator, "test {s}: {s}", .{ name, res });
            }

            // Cas principal : test "name": lhs == rhs
            const sp = splitTopLevelEq(body) orelse
                return std.fmt.allocPrint(self.allocator, "✗ test {s}: opérateur '==' manquant", .{name});

            const lhs = try self.parseOrDispatch(sp.a);
            const rhs = try self.parseOrDispatch(sp.b);
            const ls = try self.interpForAssert(lhs);
            const rs = try self.interpForAssert(rhs);
            const ls_simp = try self.math.simplifyBasic(ls);
            const rs_simp = try self.math.simplifyBasic(rs);
            if (self.math.structuralEq(ls_simp, rs_simp))
                return std.fmt.allocPrint(self.allocator, "test {s}: ✓ passed", .{name});
            if (self.egraphSemanticEq(ls_simp, rs_simp))
                return std.fmt.allocPrint(self.allocator, "test {s}: ✓ passed (e-graph)", .{name});
            const l_str = try expr.toStringInfix(self.store, ls, self.allocator);
            defer self.allocator.free(l_str);
            const r_str = try expr.toStringInfix(self.store, rs, self.allocator);
            defer self.allocator.free(r_str);
            return std.fmt.allocPrint(self.allocator, "✗ test {s}: {s} != {s}", .{ name, l_str, r_str });
        }

        // ─── assert_eq lhs == rhs ───
        if (std.mem.startsWith(u8, input, "assert_eq ")) {
            const body = std.mem.trim(u8, input["assert_eq ".len..], " \t");
            const sp = splitTopLevelEq(body) orelse
                return self.allocator.dupe(u8, "✗ assert_eq: '==' manquant");

            const lhs = try self.parseOrDispatch(sp.a);
            const rhs = try self.parseOrDispatch(sp.b);
            const ls = try self.interpForAssert(lhs);
            const rs = try self.interpForAssert(rhs);
            const ls_simp = try self.math.simplifyBasic(ls);
            const rs_simp = try self.math.simplifyBasic(rs);
            if (self.math.structuralEq(ls_simp, rs_simp))
                return self.allocator.dupe(u8, "✓ assert_eq passed");
            if (self.egraphSemanticEq(ls_simp, rs_simp))
                return self.allocator.dupe(u8, "✓ assert_eq passed (e-graph)");
            const l_str = try expr.toStringInfix(self.store, ls, self.allocator);
            defer self.allocator.free(l_str);
            const r_str = try expr.toStringInfix(self.store, rs, self.allocator);
            defer self.allocator.free(r_str);
            return std.fmt.allocPrint(self.allocator, "✗ assert_eq failed: {s} != {s}", .{ l_str, r_str });
        }

        // ─── assert_err expr ───
        if (std.mem.startsWith(u8, input, "assert_err ")) {
            const inner = std.mem.trim(u8, input["assert_err ".len..], " \t");
            if (self.parseExpression(inner)) |id| {
                _ = self.evaluateExpr(id) catch {
                    return self.allocator.dupe(u8, "✓ assert_err passed");
                };
                return self.allocator.dupe(u8, "✗ assert_err failed: expression evaluated successfully");
            } else |_| {
                return self.allocator.dupe(u8, "✓ assert_err passed");
            }
        }

        return self.allocator.dupe(u8, input);
    }

    /// Parse une sous-expression d'assertion. Si elle commence par une
    /// commande native (derive/simplify/expand/integrate/solve), l'exécute
    /// puis re-parse le résultat en Id.
    fn parseOrDispatch(self: *Heaven, s: []const u8) HeavenError!Id {
        // ─── type <expr> : retourne le type comme littéral string ───
        if (std.mem.startsWith(u8, s, "type ")) {
            const inner = std.mem.trim(u8, s["type ".len..], " \t");
            const ty_str = try self.evalTypeExpr(inner);
            defer self.allocator.free(ty_str);
            const sym = try self.store.interner.intern(ty_str);
            return try self.store.lit(.{ .str = sym });
        }

        const prefixes = [_]struct { p: []const u8, f: enum { derive, simplify, expand, integrate } }{
            .{ .p = "derive ", .f = .derive },
            .{ .p = "simplify ", .f = .simplify },
            .{ .p = "expand ", .f = .expand },
            .{ .p = "integrate ", .f = .integrate },
        };
        for (prefixes) |pfx| {
            if (std.mem.startsWith(u8, s, pfx.p)) {
                const inner = std.mem.trim(u8, s[pfx.p.len..], " \t");
                const result_str: []u8 = switch (pfx.f) {
                    .derive => try self.derive(inner, "x"),
                    .simplify => try self.simplify(inner),
                    .expand => try self.expand(inner),
                    .integrate => try self.integrate(inner, "x"),
                };
                defer self.allocator.free(result_str);
                return self.parseExpression(result_str);
            }
        }

        // Forme composée sans parenthèses : "handle (perform ...) logHandler"
        // On ne wrappe PAS si c'est déjà un littéral string (commence par ")
        // — sinon les strings avec espaces sont découpées.
        if (s.len > 0 and s[0] != '(' and s[0] != '"' and std.mem.indexOfScalar(u8, s, ' ') != null) {
            const wrapped = try std.fmt.allocPrint(self.allocator, "({s})", .{s});
            defer self.allocator.free(wrapped);
            return self.parseExpression(wrapped);
        }

        return self.parseExpression(s);
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
        const handle_op = try self.store.sym("handle");
        const handler_sym = try self.store.sym("greenHandler");
        var args_buf = [_]expr.Id{ expr_id, handler_sym };
        const handle_node = try self.store.apply(handle_op, &args_buf);

        // 5. Évaluer avec interception des effets
        self.engine.fuel = 1_000_000;
        const result = self.evaluateExpr(handle_node) catch |err| {
            _ = prof.stop(); // ne pas fuiter les métriques
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
        // Guard : arbre invalide = corruption en amont → échec propre + log
        if (a >= self.store.len() or b >= self.store.len()) {
            platform.dbg("[egraphSemanticEq] SKIP: id racine invalide a={d} b={d} (len={d})\n", .{ a, b, self.store.len() });
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

    // ─── Holes (wrappers vers hole_runtime) ───

    pub fn freshHole(self: *Heaven) !Id {
        return self.hole_runtime.fresh();
    }

    pub fn refineHole(self: *Heaven, hole_id: u32, expr_src: []const u8) !void {
        const expression = try self.parseExpression(expr_src);
        try self.hole_runtime.refine(hole_id, expression);
    }

    pub fn hasUnresolvedHoles(self: *Heaven, id: Id) bool {
        return self.hole_runtime.hasUnresolved(id);
    }

    pub fn describeHole(self: *Heaven, hole_id: u32) ![]u8 {
        return self.hole_runtime.describeHole(hole_id);
    }

    pub fn describeAllHoles(self: *Heaven) ![]u8 {
        return self.hole_runtime.describeAllHoles();
    }
};


fn substSymByName(
    store: *Store,
    allocator: std.mem.Allocator,
    e: expr.Id,
    name: []const u8,
    repl: expr.Id,
) !expr.Id {
    if (e >= store.len()) return e;
    const node = store.get(e);
    switch (node.tag) {
        .sym => {
            const s = store.interner.resolve(node.payload);
            if (std.mem.eql(u8, s, name)) return repl;
            return e;
        },
        .apply => {
            const new_func = try substSymByName(store, allocator, node.payload, name, repl);
            const all = store.spanSliceConst(node.span_a);
            if (all.len < 1) return e;
            const args_copy = try allocator.dupe(expr.Id, all[1..]);
            defer allocator.free(args_copy);
            var new_args: std.ArrayListUnmanaged(expr.Id) = .{};
            defer new_args.deinit(allocator);
            var changed = (new_func != node.payload);
            for (args_copy) |a| {
                const na = try substSymByName(store, allocator, a, name, repl);
                try new_args.append(allocator, na);
                if (na != a) changed = true;
            }
            if (!changed) return e;
            return store.apply(new_func, new_args.items);
        },
        else => return e,
    }
}


fn extractBinderType(s: []const u8) []const u8 {
    const t = std.mem.trim(u8, s, " \t");
    if (t.len == 0 or t[0] != '(') return t;
    var depth: usize = 1;
    var i: usize = 1;
    while (i < t.len and depth > 0) : (i += 1) {
        if (t[i] == '(') depth += 1
        else if (t[i] == ')') depth -= 1;
    }
    if (i < 2) return t;
    const inner = t[1 .. i - 1];
    if (std.mem.indexOfScalar(u8, inner, ':')) |colon| {
        return std.mem.trim(u8, inner[colon + 1 ..], " \t");
    }
    return t;
}

fn extractHeadName(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
    if (i < s.len and s[i] == '(') {
        // Soit un binder `(x : T)` (return T), soit un type appliqué
        // `(T args)` (récursion sur l'intérieur).
        const open = i;
        var depth: usize = 1;
        i += 1;
        while (i < s.len and depth > 0) : (i += 1) {
            if (s[i] == '(') depth += 1
            else if (s[i] == ')') depth -= 1;
        }
        if (i > open + 1 and i - 1 <= s.len) {
            const inner = s[open + 1 .. i - 1];
            if (std.mem.indexOfScalar(u8, inner, ':')) |colon| {
                return extractHeadName(inner[colon + 1 ..]);
            }
            return extractHeadName(inner);
        }
        return s;
    }
    const start = i;
    while (i < s.len and (std.ascii.isAlphanumeric(s[i]) or s[i] == '_')) : (i += 1) {}
    return s[start..i];
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

test "parseExpression — lambda courte λx.x" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("(λx.x)");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.lambda, node.tag);
    try std.testing.expectEqualStrings("x", heaven.store.interner.resolve(node.payload));
}

test "parseExpression — application sur lambda courte" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("((λx.x) 42)");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.apply, node.tag);
}

test "tactics v1.5 — rewrite a=b dans la cible" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(
        allocator,
        &arena,
        heaven.store,
        "rewrite_test",
    );
    defer state.deinit();

    // H : a = b
    const a = try heaven.store.sym("a");
    const b = try heaven.store.sym("b");
    const eq_sym = try heaven.store.sym("=");
    const h_ty = try heaven.store.apply(eq_sym, &.{ a, b });

    // Cible : Eq(f a, f b)
    const f = try heaven.store.sym("f");
    const fa = try heaven.store.apply(f, &.{a});
    const fb = try heaven.store.apply(f, &.{b});
    const target = try heaven.store.apply(eq_sym, &.{ fa, fb });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .rewrite = h_name }, &ctx);
    try tactics_mod.applyTactic(&state, .reflexivity, &ctx);

    try std.testing.expect(state.solved());
}

test "tactics v1.5 — apply P->Q crée un sous-but P" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(
        allocator,
        &arena,
        heaven.store,
        "apply_test",
    );
    defer state.deinit();

    // H : P -> Q
    const P = try heaven.store.sym("P");
    const Q = try heaven.store.sym("Q");
    const arrow = try heaven.store.sym("->");
    const h_ty = try heaven.store.apply(arrow, &.{ P, Q });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = Q,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .apply = h_name }, &ctx);

    try std.testing.expectEqual(@as(usize, 1), state.goals.items.len);
    try std.testing.expect(state.goals.items[0].target == P);
}

test "ProofSession — interactif pas à pas" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    // Déclare un théorème
    const stmt_res = try heaven.eval("theorem t_repl_test : x + 0 = x");
    defer allocator.free(stmt_res);

    // Démarre la session
    var session = try heaven.startProof("t_repl_test");
    defer session.deinit();

    // Une ligne de tactique
    const report1 = try session.applyLine("simplify");
    defer allocator.free(report1);
    try std.testing.expect(std.mem.indexOf(u8, report1, "solved") != null or
        std.mem.indexOf(u8, report1, "✓") != null);

    // Fin
    try std.testing.expect(try session.finish());
}

test "tactics v3 — assumption matche une hypothèse" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "assum_test");
    defer state.deinit();

    // H : P ; cible : P
    const P = try heaven.store.sym("P");
    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = P };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = P,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, .assumption, &ctx);
    try std.testing.expect(state.solved());
}

test "tactics v3.5 — apply H : x = x match f(a) = f(a)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "unify_test");
    defer state.deinit();

    // H : x = x
    const x = try heaven.store.sym("x");
    const eq_sym = try heaven.store.sym("=");
    const h_ty = try heaven.store.apply(eq_sym, &.{ x, x });

    // cible : f a = f a
    const f = try heaven.store.sym("f");
    const a = try heaven.store.sym("a");
    const fa = try heaven.store.apply(f, &.{a});
    const target = try heaven.store.apply(eq_sym, &.{ fa, fa });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    try state.appendGoal(.{
        .hyps = hyps,
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    // x abstrait en evar, unifié avec f(a) → pas de sous-buts
    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .apply = h_name }, &ctx);
    try std.testing.expect(state.solved());
}

test "tactics v3.5 — reflexivity unifie via evar explicite" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "refl_unify");
    defer state.deinit();

    // cible : Eq(f(?e0), f(a))
    const f = try heaven.store.sym("f");
    const a = try heaven.store.sym("a");
    const e0 = try heaven.store.mkEvar();
    const fa_ev = try heaven.store.apply(f, &.{e0});
    const fa = try heaven.store.apply(f, &.{a});
    const eq_sym = try heaven.store.sym("=");
    const target = try heaven.store.apply(eq_sym, &.{ fa_ev, fa });

    try state.appendGoal(.{
        .hyps = try state.dupHyps(&.{}),
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    // strict échoue (evar ≠ a), unify lie ?e0 := a → pop.
    try tactics_mod.applyTactic(&state, .reflexivity, &ctx);
    try std.testing.expect(state.solved());
}

test "tactics v3.5 — reflexivity échoue sur a = b" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "refl_fail");
    defer state.deinit();

    // cible : Eq(a, b), deux syms libres distincts.
    const a = try heaven.store.sym("a");
    const b = try heaven.store.sym("b");
    const eq_sym = try heaven.store.sym("=");
    const target = try heaven.store.apply(eq_sym, &.{ a, b });

    try state.appendGoal(.{
        .hyps = try state.dupHyps(&.{}),
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    // reflexivity doit ÉCHOUER, pas paniquer ni prouver.
    const result = tactics_mod.applyTactic(&state, .reflexivity, &ctx);
    try std.testing.expectError(tactics_mod.TacticError.TacticFailed, result);
    try std.testing.expect(!state.solved());
}

test "tactics v3.5 — apply H : P -> Q -> P" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "apply_prems");
    defer state.deinit();

    // H : P -> Q -> P
    const P = try heaven.store.sym("P");
    const Q = try heaven.store.sym("Q");
    const arrow = try heaven.store.sym("->");
    const q_to_p = try heaven.store.apply(arrow, &.{ Q, P });
    const h_ty = try heaven.store.apply(arrow, &.{ P, q_to_p });

    const h_name = try arena.allocator().dupe(u8, "H");
    const hyps = try arena.allocator().alloc(proof_state_mod.Hypothesis, 1);
    hyps[0] = .{ .name = h_name, .ty = h_ty };

    // cible : P
    try state.appendGoal(.{
        .hyps = hyps,
        .target = P,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    // apply H → 2 sous-buts : P, Q (dans cet ordre, P en tête).
    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .apply = h_name }, &ctx);
    try std.testing.expectEqual(@as(usize, 2), state.goals.items.len);
    // Le premier but empilé est P (prems[0]).
    try std.testing.expect(state.goals.items[0].target == P);
    try std.testing.expect(state.goals.items[1].target == Q);
}

test "tactics v4 — cases sur Nat génère base + step" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "cases_test");
    defer state.deinit();

    // cible : x + 0 = x
    const x = try heaven.store.sym("x");
    const zero = try heaven.store.int(0);
    const plus = try heaven.store.sym("+");
    const xp0 = try heaven.store.apply(plus, &.{ x, zero });
    const eq_sym = try heaven.store.sym("=");
    const target = try heaven.store.apply(eq_sym, &.{ xp0, x });

    try state.appendGoal(.{
        .hyps = try state.dupHyps(&.{}),
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, tactics_mod.Tactic{ .cases = "x" }, &ctx);
    try std.testing.expectEqual(@as(usize, 2), state.goals.items.len);
    // Les labels doivent être "base" puis "step".
    try std.testing.expectEqualStrings("base", state.goals.items[0].label);
    try std.testing.expectEqualStrings("step", state.goals.items[1].label);
}

test "tactics v4 — auto résout x * 1 = x par simplify" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var state = proof_state_mod.ProofState.init(allocator, &arena, heaven.store, "auto_test");
    defer state.deinit();

    // cible : x * 1 = x
    const x = try heaven.store.sym("x");
    const one = try heaven.store.int(1);
    const mul = try heaven.store.sym("*");
    const xm1 = try heaven.store.apply(mul, &.{ x, one });
    const eq_sym = try heaven.store.sym("=");
    const target = try heaven.store.apply(eq_sym, &.{ xm1, x });

    try state.appendGoal(.{
        .hyps = try state.dupHyps(&.{}),
        .target = target,
        .label = try state.dupLabel("main"),
    });

    var ctx = tactics_mod.TacticCtx{
        .allocator = allocator,
        .store = heaven.store,
        .heaven = @ptrCast(heaven),
        .simplifyFn = Heaven.tacticsSimplifyCb,
        .eqFn = Heaven.tacticsEqCb,
        .peanoFn = Heaven.tacticsPeanoCb,
        .substFn = Heaven.tacticsSubstCb,
    };

    try tactics_mod.applyTactic(&state, .auto, &ctx);
    try std.testing.expect(state.solved());
}

test "module v0 — theorem aliasé sous M.name" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const m = try heaven.eval("module M");
    defer allocator.free(m);
    try std.testing.expect(std.mem.indexOf(u8, m, "M") != null);

    const thm = try heaven.eval("theorem t_mod : x + 0 = x");
    defer allocator.free(thm);

    try std.testing.expect(heaven.proof_core_inst != null);
    const pc = heaven.proof_core_inst.?;
    try std.testing.expect(pc.theorems.get("M.t_mod") != null);
    try std.testing.expect(pc.theorems.get("t_mod") != null);

    const proof_res = try heaven.eval("prove M.t_mod by { simplify }");
    defer allocator.free(proof_res);
    try std.testing.expect(std.mem.indexOf(u8, proof_res, "proved") != null);
}

test "module v0 — sans module, pas d'alias" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const thm = try heaven.eval("theorem t_no_mod : x + 0 = x");
    defer allocator.free(thm);

    const pc = heaven.proof_core_inst.?;
    try std.testing.expect(pc.theorems.get("t_no_mod") != null);
    try std.testing.expect(pc.theorems.get("M.t_no_mod") == null);
}

test "type-dep v0 — data Vec (n : Nat) s'enregistre" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const res = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(res);
    try std.testing.expect(std.mem.indexOf(u8, res, "data Vec") != null);
    try std.testing.expect(std.mem.indexOf(u8, res, "1 param") != null);
    try std.testing.expect(std.mem.indexOf(u8, res, "2 constructor") != null);

    const info = heaven.type_registry.get("Vec") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Vec", info.name);
    try std.testing.expectEqual(@as(usize, 1), info.params.len);
    try std.testing.expectEqualStrings("n", info.params[0].name);
    try std.testing.expect(info.params[0].ty != null);
    try std.testing.expectEqual(@as(usize, 2), info.ctors.len);
    try std.testing.expectEqualStrings("Nil", info.ctors[0].name);
    try std.testing.expectEqual(@as(u8, 0), info.ctors[0].arity);
    try std.testing.expectEqualStrings("Cons", info.ctors[1].name);
    try std.testing.expectEqual(@as(u8, 2), info.ctors[1].arity);
}

test "type-dep v0 — data simple sans params" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const res = try heaven.eval("data Color = Red | Green | Blue");
    defer allocator.free(res);
    try std.testing.expect(std.mem.indexOf(u8, res, "0 param") != null);
    try std.testing.expect(std.mem.indexOf(u8, res, "3 constructor") != null);

    const info = heaven.type_registry.get("Color").?;
    try std.testing.expectEqual(@as(usize, 0), info.params.len);
    try std.testing.expectEqual(@as(usize, 3), info.ctors.len);
}

test "type-dep v0 — le registre reste compatible avec l'existant" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    // Déclare Vec puis vérifie que les constructeurs sont utilisables
    // (via engine.fns, comme avant).
    const res = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(res);
    try std.testing.expect(heaven.engine.fns.get("Nil") != null);
    try std.testing.expect(heaven.engine.fns.get("Cons") != null);
}

test "import v0.5 — fn aliasé sous M.name + appel M.inc" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/import_test.hvn\" as M");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "import") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "as M") != null);

    // L'alias M.inc doit exister dans engine.fns.
    try std.testing.expect(heaven.engine.fns.get("M.inc") != null);
    try std.testing.expect(heaven.engine.fns.get("M.double") != null);
    // L'original inc reste accessible top-level (comportement Q2-C : tout exporté).
    try std.testing.expect(heaven.engine.fns.get("inc") != null);

    // Appel `M.inc 5` → 6
    const r2 = try heaven.eval("M.inc 5");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "6") != null);
}

test "import v0.5 — nom déduit sans 'as'" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/import_test.hvn\"");
    defer allocator.free(r);
    // Basename sans extension : "import_test"
    try std.testing.expect(std.mem.indexOf(u8, r, "import_test") != null);
    try std.testing.expect(heaven.engine.fns.get("import_test.inc") != null);
}

test "module v1 — import transitif (parent → child)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/trans_parent.hvn\" as P");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "import") != null);

    // p_val aliasé sous P.p_val
    try std.testing.expect(heaven.engine.fns.get("P.p_val") != null);
    // c_val aliasé sous Child.c_val (pas P.Child.c_val — flat namespace v1)
    try std.testing.expect(heaven.engine.fns.get("Child.c_val") != null);
    // Les originaux restent accessibles (comportement Q2-C)
    try std.testing.expect(heaven.engine.fns.get("p_val") != null);
    try std.testing.expect(heaven.engine.fns.get("c_val") != null);

    // Appels
    const r2 = try heaven.eval("P.p_val 5");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "15") != null);

    const r3 = try heaven.eval("Child.c_val 7");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "21") != null);
}

test "module v1 — détection de cycle" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/experimental/cyc_a.hvn\" as A");
    defer allocator.free(r);
    // Cycle détecté : la string d'erreur doit le mentionner
    try std.testing.expect(std.mem.indexOf(u8, r, "cycle") != null or
        std.mem.indexOf(u8, r, "Cycle") != null);

    // La pile doit être propre après l'erreur
    try std.testing.expectEqual(@as(usize, 0), heaven.loading_modules.items.len);
    // current_module doit être restauré (null)
    try std.testing.expect(heaven.current_module == null);
}

test "module v1 — fichier introuvable donne un message clair" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/nonexistent_xyz.hvn\" as X");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "introuvable") != null);
    try std.testing.expect(heaven.current_module == null);
    try std.testing.expectEqual(@as(usize, 0), heaven.loading_modules.items.len);
}

test "type-dep v0 — ctor_arity propagée dans engine.fns" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const res = try heaven.eval("data Stream a = Cons a (Stream a) | End");
    defer allocator.free(res);

    // Le registre interne
    const info = heaven.type_registry.get("Stream").?;
    try std.testing.expectEqual(@as(u8, 2), info.ctors[0].arity);
    try std.testing.expectEqual(@as(u8, 0), info.ctors[1].arity);

    // La table engine.fns (utilisée par le pattern matcher)
    const cons_def = heaven.engine.fns.get("Cons") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 2), cons_def.ctor_arity);

    const end_def = heaven.engine.fns.get("End") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0), end_def.ctor_arity);
}

test "module v2a — export filtre les alias" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/exp_util.hvn\" as U");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "import") != null);

    // U.public existe (exporté), U.secret n'existe PAS.
    try std.testing.expect(heaven.engine.fns.get("U.public") != null);
    try std.testing.expect(heaven.engine.fns.get("U.secret") == null);

    // Enforcement faible : les noms non-exportés restent accessibles
    // sans qualification (cohérent REPL en namespace plat).
    try std.testing.expect(heaven.engine.fns.get("public") != null);
    try std.testing.expect(heaven.engine.fns.get("secret") != null);

    // Appels
    const r1 = try heaven.eval("U.public 5");
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "10") != null);
}

test "module v2a — sans export, tout est aliasé (compat v0.5)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("import \"tests/exp_noexport.hvn\" as N");
    defer allocator.free(r);

    try std.testing.expect(heaven.engine.fns.get("N.inc2") != null);
    try std.testing.expect(heaven.engine.fns.get("N.dbl2") != null);
}

test "module v2b — import idempotent" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("import \"tests/exp_noexport.hvn\" as N");
    defer allocator.free(r1);
    try std.testing.expect(std.mem.indexOf(u8, r1, "✓ import") != null);

    const r2 = try heaven.eval("import \"tests/exp_noexport.hvn\" as N");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "déjà importé") != null);
}

test "type-dep v1a — data Pair a b = Pair a b" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("data Pair a b = Pair a b");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 param") != null);

    const info = heaven.type_registry.get("Pair").?;
    try std.testing.expectEqual(@as(usize, 2), info.params.len);
    try std.testing.expectEqualStrings("a", info.params[0].name);
    try std.testing.expect(info.params[0].ty == null);
    try std.testing.expectEqualStrings("b", info.params[1].name);
    try std.testing.expect(info.params[1].ty == null);
    try std.testing.expectEqual(@as(usize, 1), info.ctors.len);
    try std.testing.expectEqual(@as(u8, 2), info.ctors[0].arity);
}

test "type-dep v1a — data Foo (n : Nat) (m : Nat)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("data Foo (n : Nat) (m : Nat) = MkFoo n m");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 param") != null);

    const info = heaven.type_registry.get("Foo").?;
    try std.testing.expectEqual(@as(usize, 2), info.params.len);
    try std.testing.expectEqualStrings("n", info.params[0].name);
    try std.testing.expect(info.params[0].ty != null);
    try std.testing.expectEqualStrings("m", info.params[1].name);
    try std.testing.expect(info.params[1].ty != null);
}

test "type-dep v1a — mix param typé + non typé" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("data Vec2 a (n : Nat) = VNil | VCons a (Vec2 a n)");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 param") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "2 constructor") != null);

    const info = heaven.type_registry.get("Vec2").?;
    try std.testing.expectEqual(@as(usize, 2), info.params.len);
    try std.testing.expectEqualStrings("a", info.params[0].name);
    try std.testing.expect(info.params[0].ty == null);
    try std.testing.expectEqualStrings("n", info.params[1].name);
    try std.testing.expect(info.params[1].ty != null);
}

test "type-dep v1a — param imbriqué (n : Vec a)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    // Le type du param contient des parenthèses imbriquées.
    const r = try heaven.eval("data Wrap (v : Vector a) = WrapIt v");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "1 param") != null);

    const info = heaven.type_registry.get("Wrap").?;
    try std.testing.expectEqual(@as(usize, 1), info.params.len);
    try std.testing.expectEqualStrings("v", info.params[0].name);
    try std.testing.expect(info.params[0].ty != null);
}

test "type-dep v2e -- subst_v2d non vide sur type parametre" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig v2e_subst : (n : Nat) -> Vec (succ n) -> a");
    defer allocator.free(r2);
    const r = try heaven.eval("v2e_subst _ (Cons x _) = x");
    defer allocator.free(r);

    // Le mecanisme v2d/v2e doit avoir lie evar (ex-_ du ctor_result)
    // avec le sym `n` du domaine : subst count >= 1, expose dans le
    // message. Sans le fix holesToEvars, ce test echoue (subst: 0).
    try std.testing.expect(std.mem.indexOf(u8, r, "subst:") != null);
}

test "type-dep v2e -- pas de subst sur type non parametre" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Color = Red | Green | Blue");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig v2e_color : Color -> Color");
    defer allocator.free(r2);
    const r = try heaven.eval("v2e_color Red = Red");
    defer allocator.free(r);

    // Aucun ctor de Color n'est dans ctor_results : pas de subst.
    try std.testing.expect(std.mem.indexOf(u8, r, "subst:") == null);
    try std.testing.expect(std.mem.startsWith(u8, r, "✓"));
}

test "logic v1 -- fact puis query trouve les faits" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("fact human socrate");
    defer allocator.free(r1);
    try std.testing.expect(std.mem.startsWith(u8, r1, "✓"));

    const r2 = try heaven.eval("fact human platon");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.startsWith(u8, r2, "✓"));

    const r3 = try heaven.eval("query human _");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "2 solution") != null);
}

test "logic v1 -- query sans solution" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("fact human socrate");
    defer allocator.free(r1);

    const r2 = try heaven.eval("query dog _");
    defer allocator.free(r2);
    try std.testing.expect(std.mem.indexOf(u8, r2, "aucune solution") != null);
}

test "eval — (* 3 6) == 18" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer { heaven.deinit(); allocator.destroy(heaven); }
    const r = try heaven.eval("(* 3 6)");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "18") != null);
}

test "eval — (* (+ 1 2) 6) == 18" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer { heaven.deinit(); allocator.destroy(heaven); }
    const r = try heaven.eval("(* (+ 1 2) 6)");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "18") != null);
}

test "eval — beta reduce : ((\\x.x) 42) == 42" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer { heaven.deinit(); allocator.destroy(heaven); }
    const r = try heaven.eval("((\\x.x) 42)");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, r, "\\x") == null);
}

test "eval — beta reduce : (\\x.x) 42 == 42" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer { heaven.deinit(); allocator.destroy(heaven); }
    const r = try heaven.eval("(\\x.x) 42");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "42") != null);
}

test "eval — beta reduce : (\\x. x + 1) 5 == 6" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer { heaven.deinit(); allocator.destroy(heaven); }
    const r = try heaven.eval("(\\x. x + 1) 5");
    defer allocator.free(r);
    try std.testing.expect(std.mem.indexOf(u8, r, "6") != null);
}

test "type-dep v2d — ctor_results peuplé (Nil→zero, Cons→succ)" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r);

    // Convention v2d : arity 0 → "<TypeName> zero", arity > 0 → "<TypeName> (succ _)".
    const cons = heaven.ctor_results.get("Cons") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Vec (succ _)", cons);

    const nil = heaven.ctor_results.get("Nil") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Vec zero", nil);
}

test "type-dep v2d — end-to-end : head (Cons 42 _) évalue 42" {
    // Note : ce test vérifie la non-régression du pipeline complet
    // (data → sig → clause → appel). La substitution v2d elle-même
    // (`n := k`) n'affecte pas le body `x` ici — c'est le pattern
    // matching standard de l'engine qui lie `x := 42`. v2d prépare
    // l'instanciation pour les cas où l'index apparaît dans le body
    // (cf. v2e : `Vec (n + m)`).
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig v2d_e2e : (n : Nat) -> Vec (succ n) -> a");
    defer allocator.free(r2);
    const r3 = try heaven.eval("v2d_e2e _ (Cons x _) = x");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.startsWith(u8, r3, "✓"));

    const r4 = try heaven.eval("v2d_e2e 0 (Cons 42 Nil)");
    // Note : on utilise `0` (Nat concret) au site d'appel, pas `_`,
    // car `_` en position évaluée est parsé comme Tag.hole et
    // déclenche evalMagic. Le pattern `_` (wildcard) matchera `0`.
    defer allocator.free(r4);
    try std.testing.expect(std.mem.indexOf(u8, r4, "42") != null);
}

test "type-dep v2d — head _ (Cons x _) = x accepté, v2d actif" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig v2d_head_uniq : (n : Nat) -> Vec (succ n) -> a");
    defer allocator.free(r2);

    const r3 = try heaven.eval("v2d_head_uniq _ (Cons x _) = x");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.startsWith(u8, r3, "✓"));

    // Le mécanisme v2d a bien vu le ctor `Cons` et accumulé un binding
    // (via unify) : on ne peut pas observer subst_v2d directement (locale),
    // mais on vérifie que ctor_results contient bien ce qu'il faut.
    const cons = heaven.ctor_results.get("Cons") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Vec (succ _)", cons);

    // Et que la clause a été enregistrée dans engine.fns.
    try std.testing.expect(heaven.engine.fns.get("v2d_head_uniq") != null);
}

test "type-dep v2d — non-régression v2c : head _ Nil rejeté" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig v2d_head_uniq : (n : Nat) -> Vec (succ n) -> a");
    defer allocator.free(r2);

    // v2c rejette avant que v2d n'ait la main : `Nil` (base) vs `Vec (succ n)` (step).
    const r3 = try heaven.eval("v2d_head_uniq _ Nil = 42");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "incompatible") != null);
    // La clause n'a PAS été enregistrée.
    try std.testing.expect(heaven.engine.fns.get("v2d_head_uniq") == null);
}

test "type-dep v2d — type non paramétré : absent de ctor_results" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r = try heaven.eval("data Color = Red | Green | Blue");
    defer allocator.free(r);

    // Pas de convention v2d pour un type sans paramètre : les ctors
    // ne sont pas inscrits dans ctor_results.
    try std.testing.expect(!heaven.ctor_results.contains("Red"));
    try std.testing.expect(!heaven.ctor_results.contains("Green"));
    try std.testing.expect(!heaven.ctor_results.contains("Blue"));
}

test "type-dep v2c — base/step incompatible (Nil vs Vec (succ n))" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const r1 = try heaven.eval("data Vec (n : Nat) = Nil | Cons a (Vec n)");
    defer allocator.free(r1);
    const r2 = try heaven.eval("sig head : (n : Nat) -> Vec (succ n) -> a");
    defer allocator.free(r2);

    // Le domaine 2 est `Vec (succ n)` (step), le pattern `Nil` est base → rejet.
    const r3 = try heaven.eval("head _ Nil = 42");
    defer allocator.free(r3);
    try std.testing.expect(std.mem.indexOf(u8, r3, "incompatible") != null);

    // Le pattern `Cons` est step → compatible avec step.
    const r4 = try heaven.eval("head _ (Cons x _) = x");
    defer allocator.free(r4);
    try std.testing.expect(std.mem.startsWith(u8, r4, "✓"));

    // Pattern ctor face à un domaine non-ctor (v2b).
    const r5 = try heaven.eval("head (Cons x _) _ = x");
    defer allocator.free(r5);
    try std.testing.expect(std.mem.indexOf(u8, r5, "appartient à") != null);
}

test "hole — fresh hole has unique id" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    // Capture l'état initial : Heaven.init() charge les std, dont les
    // patterns `_` créent des holes internes.
    const n0 = heaven.hole_state.next_id;
    const h0 = try heaven.freshHole();
    const h1 = try heaven.freshHole();

    try std.testing.expect(h0 != h1);
    try std.testing.expectEqual(n0 + 2, heaven.hole_state.next_id);
}

test "hole — _ parses to a hole node" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const id = try heaven.parseExpression("_");
    const node = heaven.store.get(id);
    try std.testing.expectEqual(expr.Tag.hole, node.tag);
}

test "hole — refine and describe" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const hole_node_id = try heaven.freshHole();
    const hole_id = heaven.store.get(hole_node_id).payload;

    try heaven.refineHole(hole_id, "42");

    const desc = try heaven.describeHole(hole_id);
    defer allocator.free(desc);

    try std.testing.expect(std.mem.indexOf(u8, desc, "refined to: 42") != null);
}

test "hole — hasUnresolvedHoles" {
    const allocator = std.testing.allocator;
    var heaven = try Heaven.init(allocator);
    defer {
        heaven.deinit();
        allocator.destroy(heaven);
    }

    const h = try heaven.freshHole();
    const h_id = heaven.store.get(h).payload;
    const one = try heaven.store.int(1);

    // (+ _ 1) contient un trou non raffiné
    const op = try heaven.store.sym("+");
    const expr_with_hole = try heaven.store.apply(op, &.{ h, one });
    try std.testing.expect(heaven.hasUnresolvedHoles(expr_with_hole));

    // Après raffinement, plus de trou non raffiné
    try heaven.refineHole(h_id, "42");
    try std.testing.expect(!heaven.hasUnresolvedHoles(expr_with_hole));
}
