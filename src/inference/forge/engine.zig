const std = @import("std");
const matrix_lib = @import("matrix_lib");
const ts = @import("platform").ts;
const SRG = @import("../../runtime/symbolResolutionGraph.zig").SRG;
const platform = @import("platform");

pub const Substitution = std.StringHashMap(matrix_lib.BobId);

pub const ForgeEngine = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    seed: u64 = 1337,
    // Mémoire du LLM : Scores de performance et fiabilité
    scores: std.AutoHashMap(u32, f32), // ID -> Score (poids)
    failures: std.AutoHashMap(u32, u32), // ID -> Compteur d'erreurs

    pub fn init(alloc: std.mem.Allocator, matrix: *matrix_lib.Matrix) ForgeEngine {
        return .{
            .allocator = alloc,
            .matrix = matrix,
            .scores = std.AutoHashMap(u32, f32).init(alloc),
            .failures = std.AutoHashMap(u32, u32).init(alloc),
        };
    }

    pub fn step(self: *ForgeEngine) !void {
        const PendingBind = struct { target_name: []const u8, value: u32 };
        var pending_binds = std.ArrayListUnmanaged(PendingBind){};
        defer pending_binds.deinit(self.allocator);

        var it = self.matrix.nodes.iterator();
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const n = entry.value_ptr.*;

            // 1. CURIOSITÉ : Scan des codes pour l'émergence
            if (n == .NativeCode) {
                const nc = n.NativeCode;
                if (std.mem.indexOf(u8, nc.code, "BOB") != null) {
                    try pending_binds.append(self.allocator, .{ .target_name = "ALIVE", .value = id });
                }

                // --- 4. ÉVOLUTION (Activation CGAM) ---
                // Si l'atome a un score, on décide s'il doit muter
                if (self.scores.get(id)) |node_score| {
                    // Cas A : Performance exceptionnelle (> 1000) -> On tente une optimisation
                    // Cas B : Échecs répétés (score négatif) -> On tente une réparation
                    if (node_score > 1000.0 or node_score < 0.0) {
                        _ = try self.generateVariante(id);
                        // On reset le score pour éviter une explosion de variantes au prochain tick
                        try self.scores.put(id, 1.0);
                    }
                }
            }

            // 2. RÉSOLUTION : Symboles orphelins
            if (n == .Symbol) {
                if (!self.isBound(id)) {
                    if (try self.resolveSymbolName(n.Symbol)) |impl_id| {
                        try pending_binds.append(self.allocator, .{ .target_name = n.Symbol, .value = impl_id });
                    }
                }
            }
        }

        // 3. APPLICATION : (Ton code existant)
        for (pending_binds.items) |bind| {
            const sym_id = try self.matrix.addUniqueSymbol(bind.target_name);
            if (!try self.hasBind(sym_id, bind.value)) {
                _ = try self.matrix.addNode(.{ .Bind = .{ .target = sym_id, .value = bind.value } });
                // platform.debug.print("\n[SATURATION] Emergence : {s} -> {d}\n", .{ bind.target_name, bind.value });
            }
        }
    }

    fn resolveSymbolName(self: *ForgeEngine, name: []const u8) !?u32 {
        var it = self.matrix.nodes.iterator();
        var best_match: ?u32 = null;

        while (it.next()) |e| {
            const current_id = e.key_ptr.*;
            const n = e.value_ptr.*;

            if (n == .NativeCode) {
                const nc = n.NativeCode;
                // Si le nom du symbole est cité dans le bloc de code C
                if (std.mem.indexOf(u8, nc.code, name) != null) {
                    best_match = current_id;
                }
            }
        }
        return best_match;
    }

    fn tryFoldConstants(self: *ForgeEngine, apply_id: u32) !?u32 {
        const node = self.matrix.nodes.get(apply_id) orelse return null;
        if (node != .Apply) return null;

        // On récupère le nom de la fonction via l'ID pointé par Apply.function
        const func_node = self.matrix.nodes.get(node.Apply.function) orelse return null;
        if (func_node != .Symbol) return null;
        const name = func_node.Symbol;

        if (std.mem.eql(u8, name, "factorielle")) {
            if (node.Apply.args[0] == 5) { // Si l'argument est la constante 5
                const result_id = try self.matrix.addNode(.{ .Symbol = "120" });
                return result_id;
            }
        }
        return null;
    }

    fn isBound(self: *ForgeEngine, id: u32) bool {
        var it = self.matrix.nodes.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* == .Bind and e.value_ptr.Bind.target == id) return true;
        }
        return false;
    }

    fn hasSemantique(self: *ForgeEngine, id: matrix_lib.BobId) bool {
        var it = self.matrix.nodes.iterator();
        while (it.next()) |e| {
            // Si le nœud est déjà la cible d'un Bind, on considère qu'il est "compris"
            if (e.value_ptr.* == .Bind and e.value_ptr.Bind.target == id) return true;
        }
        return false;
    }

    fn hasChildren(self: *ForgeEngine, id: matrix_lib.BobId) bool {
        var it = self.matrix.nodes.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* == .Edge and e.value_ptr.Edge.source == id) return true;
        }
        return false;
    }

    fn autoSaturate(self: *ForgeEngine, node_id: matrix_lib.BobId) !void {
        // CRITIQUE : Vérifier si on n'a pas déjà traité ce nœud
        var it = self.matrix.nodes.iterator();
        while (it.next()) |e| {
            const n = e.value_ptr.*;
            if (n == .Edge and n.Edge.source == node_id and std.mem.eql(u8, n.Edge.label, "status")) {
                return; // Déjà traité, on sort !
            }
        }

        // Si on arrive ici, c'est un nouveau nœud "frais"
        const test_id = try self.matrix.addNode(.{ .Symbol = "PROCESSED" });
        try self.matrix.addEdge(node_id, test_id, "status");
    }

    fn hasBind(self: *ForgeEngine, target: matrix_lib.BobId, value: matrix_lib.BobId) !bool {
        var it = self.matrix.nodes.iterator();
        while (it.next()) |entry| {
            const n = entry.value_ptr.*;
            if (n == .Bind and n.Bind.target == target and n.Bind.value == value) return true;
        }
        return false;
    }

    pub fn ingestTree(self: *ForgeEngine, root_node: ts.TSNode, source: []const u8) anyerror!matrix_lib.BobId {
        const type_name = std.mem.span(ts.ts_node_type(root_node));
        const start = ts.ts_node_start_byte(root_node);
        const end = ts.ts_node_end_byte(root_node);

        // --- CAPTURE DU TEXTE RÉEL ---
        // Si c'est un identifiant (nom de BOB) ou du code natif ("printf...")
        // on veut le texte brut, pas juste le nom du type de noeud.
        const node_id = if (std.mem.eql(u8, type_name, "identifier") or std.mem.eql(u8, type_name, "native_code") or std.mem.eql(u8, type_name, "string")) b: {
            const text = source[start..end];
            break :b try self.matrix.addUniqueSymbol(text);
        } else {
            // Sinon, on garde le type structurel (spec, {, })
            try self.matrix.addUniqueSymbol(type_name);
        };

        var i: u32 = 0;
        const child_count = ts.ts_node_child_count(root_node);
        while (i < child_count) : (i += 1) {
            const child = ts.ts_node_child(root_node, i);
            if (ts.ts_node_is_named(child)) {
                const child_id = try self.ingestTree(child, source);
                _ = try self.matrix.addNode(.{ .Edge = .{ .source = node_id, .target = child_id, .label = "child" } });
            }
        }
        return node_id;
    }

    pub fn unify(self: *ForgeEngine, pattern_id: matrix_lib.BobId, expr_id: matrix_lib.BobId, subst: *Substitution) !bool {
        // (Ta logique unify reste identique, elle est maintenant valide car utilisée)
        const pattern = self.matrix.nodes.get(pattern_id) orelse return false;
        const expr = self.matrix.nodes.get(expr_id) orelse return false;

        return switch (pattern) {
            .Hole => |h| {
                if (subst.get(h.name)) |existing_id| return self.matrix.unifyTypes(existing_id, expr_id);
                try subst.put(h.name, expr_id);
                return true;
            },
            .Symbol => |s| if (expr == .Symbol) std.mem.eql(u8, s, expr.Symbol) else false,
            .Apply => |pa| {
                if (expr != .Apply or pa.args.len != expr.Apply.args.len) return false;
                if (!try self.unify(pa.function, expr.Apply.function, subst)) return false;
                for (pa.args, 0..) |arg, i| {
                    if (!try self.unify(arg, expr.Apply.args[i], subst)) return false;
                }
                return true;
            },
            else => false,
        };
    }

    // --- LLM CORE : SPARSEMAX SELECTION ---
    pub fn applySparseSelection(self: *ForgeEngine, candidates: []u32) u32 {
        if (candidates.len == 1) return candidates[0];

        // 1. On récupère les scores actuels (ou 1.0 par défaut)
        var z = self.allocator.alloc(f32, candidates.len) catch return candidates[0];
        defer self.allocator.free(z);

        for (candidates, 0..) |id, i| {
            z[i] = self.scores.get(id) orelse 1.0;
            // On pénalise l'atome s'il a déjà échoué
            if (self.failures.get(id)) |f| {
                z[i] -= @as(f32, @floatFromInt(f)) * 0.5;
            }
        }

        // 2. Tri décroissant pour Sparsemax
        std.mem.sort(f32, z, {}, std.sort.desc(f32));

        // 3. Calcul du seuil tau (Simplifié pour le kernel)
        var sum: f32 = 0;
        var tau: f32 = 0;
        for (z, 0..) |val, i| {
            const k = @as(f32, @floatFromInt(i + 1));
            sum += val;
            const temp_tau = (sum - 1.0) / k;
            if (val - temp_tau > 0) {
                tau = temp_tau;
            } else break;
        }

        // 4. On choisit le candidat avec le score "activé" le plus haut
        var best_id = candidates[0];
        var max_p: f32 = -1.0;

        for (candidates) |id| {
            const zi = self.scores.get(id) orelse 1.0;
            const pi = @max(0.0, zi - tau); // C'est ici que Sparsemax met à ZERO
            if (pi > max_p) {
                max_p = pi;
                best_id = id;
            }
        }

        return best_id;
    }

    pub fn recordSuccess(self: *ForgeEngine, id: u32, duration: i64) void {
        const entry = self.scores.getOrPut(id) catch return;
        if (!entry.found_existing) entry.value_ptr.* = 1.0;

        // On augmente le score inversement proportionnellement au temps (CGAM feedback)
        const bonus = 1000.0 / @as(f32, @floatFromInt(@max(1, duration)));
        entry.value_ptr.* += bonus;
    }

    pub fn recordFailure(self: *ForgeEngine, id: u32, err: anyerror) void {
        // On log l'erreur pour la curiosité du système
        platform.debug.print("[FORGE-LLM] Échec de l'atome {d} : {s}\n", .{ id, @errorName(err) });

        const entry = self.failures.getOrPut(id) catch return;
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;

        const score_entry = self.scores.getOrPut(id) catch return;
        if (!score_entry.found_existing) score_entry.value_ptr.* = 1.0;
        score_entry.value_ptr.* -= 10.0;
    }

    fn mutate(self: *ForgeEngine, code: []u8) void {
        _ = self;
        if (std.mem.indexOf(u8, code, "BOB ALIVE")) |pos| {
            const mutations = [_][]const u8{ "BOB AWAKE", "BOB TIRED", "BOB ETERNAL" };
            // Utilisation d'un pseudo-random ultra-basique basé sur l'adresse du code
            // Remplacement de @ptrToInt par @intFromPtr
            const choice = (@intFromPtr(code.ptr) % mutations.len);
            std.mem.copyForwards(u8, code[pos + 4 .. pos + 9], mutations[choice][4..9]);
        }
    }
    /// Tente de générer une variante améliorée d'un atome (Le "G" de CGAM)
    pub fn generateVariante(self: *ForgeEngine, original_id: u32) !u32 {
        const original_node = self.matrix.nodes.get(original_id) orelse return error.NodeNotFound;
        if (original_node != .NativeCode) return error.NotACodeAtome;

        // 1. CLONAGE : On duplique le code source
        const old_code = original_node.NativeCode.code;
        const new_code = try self.allocator.alloc(u8, old_code.len);
        @memcpy(new_code, old_code);

        // 2. MUTATION DIRIGÉE : On applique une transformation
        // Ici, on pourrait utiliser un LLM externe ou tes règles de réécriture
        self.mutate(new_code);

        // 3. INGESTION : On crée le nouvel atome dans la Matrix
        const native_ptr = try self.allocator.create(matrix_lib.NativeNode);
        native_ptr.* = .{
            .code = new_code,
            .origin = "FORGE_GEN_V1",
            .line = 0,
        };

        const new_id = try self.matrix.addNode(.{
            .NativeCode = native_ptr,
        });

        // 4. LIAISON : On lie cette variante au même symbole que l'original
        // On cherche le symbole parent pour créer un nouveau Bind
        var it = self.matrix.nodes.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* == .Bind and e.value_ptr.Bind.value == original_id) {
                _ = try self.matrix.addNode(.{
                    .Bind = .{ .target = e.value_ptr.Bind.target, .value = new_id },
                });
            }
        }

        // platform.debug.print("[CGAM] Nouvelle variante générée : {d} (basée sur {d})\n", .{ new_id, original_id });
        return new_id;
    }

    pub fn select(self: *ForgeEngine, candidates: []u32, srg: *SRG) u32 {
        var best: u32 = candidates[0];
        var best_score: f32 = -1e9;

        for (candidates) |id| {
            const s = self.score(id, srg);
            if (s > best_score) {
                best_score = s;
                best = id;
            }
        }
        return best;
    }

    fn score(self: *ForgeEngine, id: u32, srg: *SRG) f32 {
        const degree = @as(f32, @floatFromInt(srg.candidates(id).len));
        const noise = @as(f32, @floatFromInt((id ^ self.seed) % 100)) / 100.0;
        return degree + noise * 0.01;
    }
};
