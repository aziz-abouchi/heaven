const std = @import("std");
const Allocator = std.mem.Allocator;
const expr = @import("expr");
const canon = @import("canon");
const egraph_mod = @import("egraph");
const pattern = @import("pattern");
const platform = @import("platform");

const Store = expr.Store;
const Id = expr.Id;
const EGraph = egraph_mod.EGraph;

pub const Provenance = union(enum) {
    Axiom: []const u8,
    Rule: []const u8,
    Sensor: []const u8,
    Agent: []const u8,
    User: []const u8,
};

pub const Engine = enum {
    EGraph,
    CAS,
    Proof,
    Induction,
    Ontology,
    Prolog,
    miniKanren,
};

pub const TraceStep = struct {
    source: Provenance,
    engine: Engine,
    operation: []const u8,
    timestamp: u64,
};

pub const Step = struct {
    engine: Engine,
    operation: []const u8,
    args: []const Id,
};

pub const Plan = struct {
    steps: []const Step,
};

pub const TransformError = error{
    NoDispatch,
    StepFailed,
    OutOfMemory,
    EngineError,
};

pub const TransformResult = union(enum) {
    Success: struct { result: Id, certificate: []const TraceStep },
    Failure: struct { err: TransformError, certificate: []const TraceStep },
};

pub fn format(self: TransformResult, store: *const Store, allocator: Allocator) ![]u8 {
    return switch (self) {
        .Success => |s| {
            const proof_str = try expr.toStringInfix(store, s.result, allocator);
            defer allocator.free(proof_str);
            return std.fmt.allocPrint(allocator, "Success:\n  Result: {s}\n  Certificate: {d} steps", .{ proof_str, s.certificate.len });
        },
        .Failure => |f| {
            return std.fmt.allocPrint(allocator, "Failure: {s}", .{@errorName(f.err)});
        },
    };
}

pub const Transform = struct {
    allocator: Allocator,
    store: *Store,
    kb: *KnowledgeBase,
    tracer: TraceTracer,
    // État mutable pendant l'exécution du plan
    state: struct {
        current: Id,
        target: Id,
        current_normalized: ?Id,
        target_normalized: ?Id,
        egraph: ?*EGraph,
    },

    pub fn init(allocator: Allocator, store: *Store, kb: *KnowledgeBase) Transform {
        return .{
            .allocator = allocator,
            .store = store,
            .kb = kb,
            .tracer = TraceTracer.init(allocator),
            .state = .{
                .current = 0,
                .target = 0,
                .current_normalized = null,
                .target_normalized = null,
                .egraph = null,
            },
        };
    }

    pub fn transform(self: *Transform, source: Id, target: Id, engine: anytype) TransformResult {
        self.state.current = source;
        self.state.target = target;

        // On mémorise l'état initial de la KB pour pouvoir faire machine arrière si ça échoue
        const initial_rules_len = self.kb.rules.items.len;

        // Phase 1 : construction du plan
        const plan = self.buildPlan(source, target) catch |err| {
            return TransformResult{
                .Failure = .{
                    .err = err,
                    .certificate = self.tracer.toOwnedSlice() catch &[_]TraceStep{},
                },
            };
        };

        // Phase 2 : exécution du plan
        for (plan.steps) |step| {
            _ = self.executeStep(step, engine) catch |err| {
                // NETTOYAGE : on retire les règles ajoutées par .Induction avant de quitter
                self.kb.rules.items.len = initial_rules_len;

                self.tracer.append(
                    .{ .Rule = step.operation },
                    step.engine,
                    step.operation,
                    err,
                );
                return TransformResult{
                    .Failure = .{
                        .err = err,
                        .certificate = self.tracer.toOwnedSlice() catch &[_]TraceStep{},
                    },
                };
            };
            self.tracer.append(
                .{ .Rule = step.operation },
                step.engine,
                step.operation,
                null,
            );
        }

        // Phase 3 : extraction de la preuve (simplifiée)
        const proof = self.extractProof() catch |err| {
            return TransformResult{
                .Failure = .{
                    .err = err,
                    .certificate = self.tracer.toOwnedSlice() catch &[_]TraceStep{},
                },
            };
        };

        return TransformResult{
            .Success = .{
                .result = proof,
                .certificate = self.tracer.toOwnedSlice() catch &[_]TraceStep{},
            },
        };
    }

    fn buildPlan(self: *Transform, source: Id, target: Id) !Plan {
        // Stratégie 1 : but arithmétique
        if (self.isArithmeticGoal(source, target)) {
            return Plan{
                .steps = &[_]Step{
                    .{ .engine = .Induction, .operation = "structural", .args = &.{} },
                    .{ .engine = .EGraph, .operation = "saturate", .args = &.{} },
                    .{ .engine = .CAS, .operation = "normalize", .args = &.{} },
                    .{ .engine = .Proof, .operation = "refl", .args = &.{} },
                },
            };
        }

        // Stratégie 2 : but ontologique
        if (self.isOntologyGoal(source, target)) {
            return Plan{
                .steps = &[_]Step{
                    .{ .engine = .Ontology, .operation = "lookup", .args = &.{} },
                    .{ .engine = .Ontology, .operation = "subsume", .args = &.{} },
                    .{ .engine = .Proof, .operation = "iso", .args = &.{} },
                },
            };
        }

        // Stratégie 3 : but relationnel
        if (self.isRelationalGoal(source, target)) {
            return Plan{
                .steps = &[_]Step{
                    .{ .engine = .Prolog, .operation = "query", .args = &.{} },
                    .{ .engine = .miniKanren, .operation = "unify", .args = &.{} },
                    .{ .engine = .Proof, .operation = "relational", .args = &.{} },
                },
            };
        }

        return error.NoDispatch;
    }

    fn isArithmeticGoal(self: *Transform, source: Id, target: Id) bool {
        // Détecter si source/target contiennent des opérateurs arithmétiques
        return isArithmeticNode(self.store, source) and isArithmeticNode(self.store, target);
    }

    fn isOntologyGoal(self: *Transform, source: Id, target: Id) bool {
        // Détecter si source/target sont des concepts ontologiques
        // Pour l'instant : toujours false (à implémenter)
        _ = self;
        _ = source;
        _ = target;
        return false;
    }

    fn isRelationalGoal(self: *Transform, source: Id, target: Id) bool {
        // Détecter si source/target sont des relations logiques
        // Pour l'instant : toujours false (à implémenter)
        _ = self;
        _ = source;
        _ = target;
        return false;
    }

    fn isArithmeticNode(store: *const Store, id: Id) bool {
        const node = store.get(id);
        switch (node.tag) {
            .lit => return true, // Les littéraux sont arithmétiques
            .sym => {
                // Les symboles simples (x, y, n) sont considérés arithmétiques
                return true;
            },
            .apply => {
                const func_node = store.get(node.payload);
                if (func_node.tag != .sym) return false;
                const op = store.interner.resolve(func_node.payload);
                // Vérifier si c'est un opérateur arithmétique
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or
                    std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or
                    std.mem.eql(u8, op, "^"))
                {
                    return true;
                }
                // Sinon, vérifier récursivement les arguments (avec limite de profondeur)
                const args = node.span_a.slice(store.pool.items);
                for (args) |arg| {
                    if (isArithmeticNode(store, arg)) return true;
                }
                return false;
            },
            else => return false,
        }
    }

    fn executeStep(self: *Transform, step: Step, engine: anytype) !void {
        _ = engine;
        const is_wasm = @import("builtin").target.cpu.arch == .wasm32;

        switch (step.engine) {
            .EGraph => {
                if (std.mem.eql(u8, step.operation, "saturate")) {
                    // EGraph saturate : désactivé en WASM (bug potentiel), exécuté en natif
                    if (!is_wasm) {
                        try self.saturateEGraph();
                    }
                }
            },
            .CAS => {
                if (std.mem.eql(u8, step.operation, "normalize")) {
                    try self.normalize();
                }
            },
            .Proof => {
                if (std.mem.eql(u8, step.operation, "refl")) {
                    const cur = self.state.current_normalized orelse return error.StepFailed;
                    const tgt = self.state.target_normalized orelse return error.StepFailed;
                    // On compare le résultat FINAL (après l'E-Graph) avec la cible
                    if (!exprEqual(self.store, cur, tgt)) {
                        return error.StepFailed;
                    }
                }
            },
            .Induction => {
                const var_sym = Transform.findFirstSymbol(self.store, self.state.current) orelse return error.StepFailed;

                // Générer l'Hypothèse de Récurrence P(k) et l'injecter dans la KB
                const k_id = try self.store.sym("k");
                var bindings_k = std.AutoHashMapUnmanaged(u32, Id){};
                defer bindings_k.deinit(self.allocator);
                try bindings_k.put(self.allocator, var_sym, k_id);

                const ih_lhs = try pattern.substitutePattern(self.store, self.state.current, &bindings_k, self.allocator);
                const ih_rhs = try pattern.substitutePattern(self.store, self.state.target, &bindings_k, self.allocator);
                const ih_rule = try self.store.relation("IH", &.{ih_lhs}, &.{ih_rhs});
                try self.kb.rules.append(self.allocator, ih_rule);

                // Transformer le but courant en P(succ(k))
                const sk_id = try self.store.apply(try self.store.sym("succ"), &.{k_id});
                var bindings_sk = std.AutoHashMapUnmanaged(u32, Id){};
                defer bindings_sk.deinit(self.allocator);
                try bindings_sk.put(self.allocator, var_sym, sk_id);

                self.state.current = try pattern.substitutePattern(self.store, self.state.current, &bindings_sk, self.allocator);
                self.state.target = try pattern.substitutePattern(self.store, self.state.target, &bindings_sk, self.allocator);
            },
            else => return error.EngineError,
        }
    }

    fn saturateEGraph(self: *Transform) !void {
        var egraph = egraph_mod.EGraph.init(self.store, self.allocator);
        defer egraph.deinit();

        // 1. Ajouter les DEUX expressions (source et target) dans l'E-graph
        const root_source = try egraph.addExpr(self.state.current);
        const root_target = try egraph.addExpr(self.state.target);

        // 2. Saturation avec budget strict
        const budget_ns: u64 = 1_000_000; // 1 ms
        const start = platform.time.nanoTimestamp();
        var changed = true;
        var iterations: u32 = 0;

        while (changed and iterations < 5) : (iterations += 1) {
            if (platform.time.nanoTimestamp() - start > budget_ns) break;
            changed = false;

            for (self.kb.rules.items) |rule_id| {
                const rule_node = self.store.get(rule_id);
                if (rule_node.tag != .relation) continue;
                const pair = rule_node.span_a.slice(self.store.pool.items);
                if (pair.len < 2) continue;
                const lhs = pair[0];
                const rhs = pair[1];

                var class_idx: u32 = 0;
                while (class_idx < egraph.classes.items.len) : (class_idx += 1) {
                    if (platform.time.nanoTimestamp() - start > budget_ns) break;
                    const eclass = &egraph.classes.items[class_idx];

                    for (eclass.nodes.items) |node_id| {
                        var bindings = std.AutoHashMapUnmanaged(u32, Id){};
                        defer bindings.deinit(self.allocator);

                        if (pattern.exprPatternMatch(self.store, lhs, node_id, &bindings, self.allocator)) {
                            const new_id = pattern.substitutePattern(self.store, rhs, &bindings, self.allocator) catch continue;
                            const new_class = try egraph.addExpr(new_id);
                            const merged = try egraph.merge(class_idx, new_class);
                            if (merged != class_idx) {
                                changed = true;
                            }
                        }
                    }
                }
            }
        }

        // 3. Vérifier si l'E-graph a prouvé l'équivalence
        const final_source_class = egraph.find(root_source) orelse return error.StepFailed;
        const final_target_class = egraph.find(root_target) orelse return error.StepFailed;

        if (final_source_class == final_target_class) {
            // Victoire ! Les deux expressions ont fusionné.
            // On dit au moteur qu'on a atteint la cible pour que .Proof réussisse.
            self.state.current = self.state.target;
        } else {
            // Défaite de l'E-graph.
            const best = egraph.extract(final_source_class, null) orelse self.state.current;
            self.state.current = best;
        }
    }

    fn normalize(self: *Transform) !void {
        // Réécriture Bottom-Up à point fixe
        var cur = try self.rewriteBottomUp(self.state.current);
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            const new_cur = try self.rewriteBottomUp(cur);
            if (new_cur == cur) break;
            cur = new_cur;
        }
        self.state.current_normalized = cur;
        self.state.target_normalized = self.state.target;
    }

    fn rewriteBottomUp(self: *Transform, id: Id) !Id {
        if (id >= self.store.len()) return id;
        const node = self.store.get(id);
        const pool = self.store.pool.items;
        const children = node.span_a.slice(pool);

        // 1. Réécrire les enfants d'abord (Bottom-Up)
        var new_children = std.ArrayListUnmanaged(Id){};
        defer new_children.deinit(self.allocator);
        var changed_child = false;
        for (children) |child| {
            const new_child = try self.rewriteBottomUp(child);
            try new_children.append(self.allocator, new_child);
            if (new_child != child) changed_child = true;
        }

        var current = id;
        if (changed_child) {
            // Reconstruire le nœud avec les nouveaux enfants
            current = try self.store.apply(node.payload, new_children.items);
        }

        // 2. Essayer de matcher les règles sur le nœud courant
        for (self.kb.rules.items) |rule_id| {
            const rule_node = self.store.get(rule_id);
            if (rule_node.tag != .relation) continue;
            const pair = rule_node.span_a.slice(self.store.pool.items);
            if (pair.len < 2) continue;
            const lhs = pair[0];
            const rhs = pair[1];

            var bindings = std.AutoHashMapUnmanaged(u32, Id){};
            defer bindings.deinit(self.allocator);

            if (pattern.exprPatternMatch(self.store, lhs, current, &bindings, self.allocator)) {
                // On ne met à jour `current` QUE si la substitution a vraiment réussi
                if (pattern.substitutePattern(self.store, rhs, &bindings, self.allocator)) |new_current| {
                    current = new_current;
                    break;
                } else |_| {
                    // gérer l'échec de substitution : souvent juste `continue` ou `return err`
                    continue; // substitution échouée pour cette règle : on continue avec la règle suivante
                }
            }
        }

        return current;
    }

    fn checkRefl(self: *Transform) !void {
        const cur = self.state.current_normalized orelse return error.StepFailed;
        const tgt = self.state.target_normalized orelse return error.StepFailed;
        if (!expr.exprStructuralEq(self.store, cur, tgt)) {
            return error.StepFailed;
        }
    }

    fn extractProof(self: *Transform) !Id {
        const sym = try self.store.interner.intern("Refl");
        return self.store.sym("Refl") catch self.store.push(.{ .tag = .sym, .payload = sym });
    }

    fn exprEqual(store: *const Store, a: Id, b: Id) bool {
        if (a == b) return true;
        if (a >= store.len() or b >= store.len()) return false;

        const na = store.get(a);
        const nb = store.get(b);

        if (na.tag != nb.tag) return false;
        if (na.payload != nb.payload) return false;

        const pool = store.pool.items;
        const sa = na.span_a.slice(pool);
        const sb = nb.span_a.slice(pool);

        if (sa.len != sb.len) return false;
        for (sa, sb) |ca, cb| {
            if (!exprEqual(store, ca, cb)) return false;
        }

        return true;
    }

    fn findFirstSymbol(store: *const Store, id: Id) ?u32 {
        if (id >= store.len()) return null;
        const node = store.get(id);
        if (node.tag == .sym) return node.payload;
        const pool = store.pool.items;
        for (node.span_a.slice(pool)) |child| {
            if (findFirstSymbol(store, child)) |sym| return sym;
        }
        return null;
    }
};

// KnowledgeBase minimale : liste de règles (IDs de relations lhs=rhs)
pub const KnowledgeBase = struct {
    rules: std.ArrayListUnmanaged(Id),
    pub fn init(_: Allocator) KnowledgeBase {
        return .{ .rules = .{} };
    }
    pub fn deinit(self: *KnowledgeBase, allocator: Allocator) void {
        self.rules.deinit(allocator);
    }
};

// Tracer
pub const TraceTracer = struct {
    allocator: Allocator,
    steps: std.ArrayListUnmanaged(TraceStep),

    pub fn init(allocator: Allocator) TraceTracer {
        return .{ .allocator = allocator, .steps = .{} };
    }

    pub fn append(self: *TraceTracer, source: Provenance, engine: Engine, op: []const u8, err: ?TransformError) void {
        _ = err;
        const step = TraceStep{
            .source = source,
            .engine = engine,
            .operation = op,
            .timestamp = 0, // Pas de temps en WASM
        };
        self.steps.append(self.allocator, step) catch {};
    }

    pub fn toOwnedSlice(self: *TraceTracer) ![]const TraceStep {
        const slice = try self.allocator.alloc(TraceStep, self.steps.items.len);
        @memcpy(slice, self.steps.items);
        return slice;
    }

    pub fn deinit(self: *TraceTracer) void {
        self.steps.deinit(self.allocator);
    }
};
// ═══════════════════════════════════════ Stratégies avancées ═══════════════════════════════════════
