const std = @import("std");

const matrix_lib = @import("matrix_lib");
const SRG = @import("symbolResolutionGraph.zig").SRG;
const EQSATPlanner = @import("eQSATPlanner.zig").EQSATPlanner;
const Forge = @import("../inference/forge/engine.zig").ForgeEngine;
const AutoFab = @import("autofab.zig").AutoFab;

const network = @import("../scut/network.zig");
const TaskQueue = @import("task").TaskQueue;
const platform = @import("platform");
const egraph_mod = @import("egraph");

const log = platform.debug.print;

pub const ResonanceState = enum { Dormant, Vibrating, Resolved };

pub const HeavenAtom = struct {
    id: u32,
    state: ResonanceState,
    last_pulse: i64,
    is_hole: bool,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    egraph: *egraph_mod.EGraph,

    // CORE DATA
    atoms: std.AutoHashMap(u32, HeavenAtom),
    matrix: *matrix_lib.Matrix,

    // LAYERS (clean separation)
    srg: *SRG,
    eqsat: *EQSATPlanner,
    forge: Forge,
    autofab: ?*AutoFab,
    task_queue: TaskQueue,

    pub fn init(alloc: std.mem.Allocator, matrix: *matrix_lib.Matrix, srg: *SRG, eqsat: *EQSATPlanner, egraph: *egraph_mod.EGraph) Engine {
        return .{
            .allocator = alloc,
            .egraph = egraph,
            .matrix = matrix,
            .srg = srg,
            .eqsat = eqsat,
            .autofab = null,
            .atoms = std.AutoHashMap(u32, HeavenAtom).init(alloc),
            .forge = Forge.init(alloc, matrix),
            .task_queue = TaskQueue.init(alloc),
        };
    }

    pub fn deinit(_: *Engine) void {
        // Libère ici les listes/maps internes de Engine si tu veux
    }

    pub fn bindAutoFab(self: *Engine, fab: *AutoFab) void {
        self.autofab = fab;
    }

    pub fn run(self: *Engine, root: u32) !void {
        const plan = try self.eqsat.plan(root, self.srg);

        for (plan.steps) |step| {
            const impl = self.srg.resolve(step.symbol);

            if (self.autofab) |fab| {
                try fab.executeDeterministic(impl, step.code);
            }
        }
    }

    pub fn evaluate(self: *Engine, matrix: *matrix_lib.Matrix, id: u32) ?i64 {
        if (matrix.nodes.get(id)) |node| {
            switch (node) {
                .NativeCode => |n| {
                    // tentative simple : parser int
                    return std.fmt.parseInt(i64, n.code, 10) catch null;
                },
                .Bind => |b| {
                    return self.evaluate(matrix, b.value);
                },
                else => return null,
            }
        }
        return null;
    }

    fn collectCandidates(self: *Engine, matrix: *matrix_lib.Matrix, symbol_id: u32) []u32 {
        var list = std.ArrayListUnmanaged(u32){};

        var it = matrix.nodes.iterator();
        while (it.next()) |entry| {
            const n = entry.value_ptr.*;
            if (n == .Bind and n.Bind.target == symbol_id) {
                list.append(self.allocator, n.Bind.value) catch continue;
            }
        }

        if (list.items.len == 0) {
            // On alloue un slice de 1 élément pour rester cohérent avec le free() futur
            const fallback = self.allocator.alloc(u32, 1) catch return &[_]u32{};
            // Note: le return &[_]u32{} vide est safe ici car candidates.len sera 0
            fallback[0] = symbol_id;
            return fallback;
        }

        return list.toOwnedSlice(self.allocator) catch b: {
            const fallback = self.allocator.alloc(u32, 1) catch break :b &[_]u32{};
            fallback[0] = symbol_id;
            break :b fallback;
        };
    }

    fn execute(self: *Engine, matrix: *matrix_lib.Matrix, id: u32) !void {
        const node = matrix.nodes.get(id) orelse return error.NodeNotFound;

        switch (node) {
            .NativeCode => |n| {
                if (self.autofab) |fab| {
                    try fab.executeDeterministic(id, n.code);
                }
            },

            .Bind => |b| {
                try self.pulse(matrix, b.value);
            },

            .Symbol => {
                const resolved = self.srg.resolve(id);
                try self.pulse(matrix, resolved);
            },

            else => {},
        }
    }

    pub fn pulse(self: *Engine, matrix: *matrix_lib.Matrix, atom_id: u32, origin: u64) !void {
        // Ne court-circuite que si c'est VRAIMENT un entier pur
        if (matrix.nodes.get(atom_id)) |n| {
            if (n == .NativeCode and std.ascii.isDigit(n.NativeCode.code[0])) {
                if (self.evaluate(matrix, atom_id)) |val| {
                    platform.debug.print("[EVAL] Node {d} => {d}\n", .{ atom_id, val });
                    return;
                }
            }
        }
        const entry = try self.atoms.getOrPut(atom_id);
        if (!entry.found_existing) {
            const node = matrix.nodes.get(atom_id) orelse return error.NodeNotFound;
            entry.value_ptr.* = .{
                .id = atom_id,
                .state = .Dormant,
                .last_pulse = std.time.timestamp(),
                .is_hole = (node == .Hole),
            };
        }

        const atom = entry.value_ptr;

        // --- PHASE 1 : RÉSOLUTION (Ton code actuel) ---
        if (atom.is_hole) {
            atom.state = .Vibrating;
            log("[HEAVEN] Vibration du Hole {d}...\n", .{atom_id});

            var synth = @import("synthesis").ProofSynthesizer{
                .allocator = self.allocator,
                .matrix = matrix,
            };

            if (try synth.fillHole(atom_id)) {
                atom.state = .Resolved;
                log("[HEAVEN] Hole {d} résolu !\n", .{atom_id});
            } else {
                network.broadcast(matrix, atom_id) catch {};
                return; // On attend la prochaine impulsion ou un signal réseau
            }
        }

        // --- PHASE 2 : EXÉCUTION (Le pont vers AutoFab) ---
        const current_node = matrix.nodes.get(atom_id) orelse return;

        // Cas A : On pulse un Bind directement
        if (current_node == .Bind) {
            log("[HEAVEN] Suivi du lien sémantique {d} ≡ {d}\n", .{ atom_id, current_node.Bind.value });
            return self.pulse(matrix, current_node.Bind.value, origin);
        }

        // Cas B : On pulse un Symbole (on cherche ses attaches)
        // --- PHASE 3 : INFERENCE LLM (Sélection de l'atome le plus probable) ---
        if (current_node == .Symbol) {
            const candidates = self.collectCandidates(matrix, atom_id);
            defer self.allocator.free(candidates); // Libération après sélection

            if (candidates.len > 0) {
                const selected_id = self.forge.applySparseSelection(candidates);
                log("[LLM-FORGE] Sparsemax a isolé l'atome {d} parmi {d} variantes.\n", .{ selected_id, candidates.len });

                // Éviter la boucle infinie si le sélectionné est le même que l'actuel
                if (selected_id != atom_id) {
                    return self.pulse(matrix, selected_id, origin);
                }
            }
        }

        // Cas C : On arrive sur du code exécutable
        if (current_node == .NativeCode) {
            if (self.autofab) |fab| {
                const start_time = std.time.microTimestamp();

                // Exécution JIT
                fab.synthesizeAndExecute(current_node.NativeCode.code) catch |err| {
                    // ÉCHEC : La Forge enregistre l'erreur pour ne plus générer ce code
                    self.forge.recordFailure(atom_id, err);
                    return err;
                };

                const duration = std.time.microTimestamp() - start_time;

                // SUCCÈS : La Forge renforce ce chemin
                self.forge.recordSuccess(atom_id, duration);

                atom.state = .Resolved;
                return;
            }
        }

        if (current_node == .ExternLink) {
            if (self.autofab) |fab| {
                const link = current_node.ExternLink;

                // 1. On cherche d'abord si c'est déjà en mémoire
                var ptr = fab.getJITSymbol(link.symbol_name);

                // 2. Si introuvable et que c'est "main", on tente de forger le Node parent
                // (Note: Dans une version future, on cherchera le NativeCode lié sémantiquement)
                if (ptr == null and std.mem.eql(u8, link.symbol_name, "main")) {
                    log("[HEAVEN] Symbole 'main' absent. Tentative de forgeage automatique...\n", .{});
                    // On force le forgeage du node actuel (ID 12)
                    // Autofab doit être capable de retrouver le code source via la Matrix
                    self.autofab.?.forge(atom_id, .{ .platform = .NativeJit }) catch |err| {
                        log("[HEAVEN ERR] Forgeage auto échoué: {any}\n", .{err});
                    };
                    // On réessaie de récupérer le symbole après la forge
                    ptr = fab.getJITSymbol(link.symbol_name);
                }

                if (ptr) |func_ptr| {
                    log("[HEAVEN] Activation JIT : {s} @ {p}\n", .{ link.symbol_name, func_ptr });
                    const func: *const fn () callconv(.c) void = @ptrCast(func_ptr);
                    func();
                    atom.state = .Resolved;
                    return;
                }

                // 2. FALLBACK NATIF : Si TCC ne l'a pas, on cherche dans le système (libc)
                fab.linker.loadLibrary(link.lib_name) catch |err| {
                    log("[HEAVEN ERR] Échec chargement lib {s}: {any}\n", .{ link.lib_name, err });
                    return err;
                };

                const symbol_z = try self.allocator.dupeZ(u8, link.symbol_name);
                defer self.allocator.free(symbol_z);

                if (fab.linker.getSymbol(link.lib_name, symbol_z)) |sys_ptr| {
                    log("[HEAVEN] Appel système (libc) : {s} @ {p}\n", .{ link.symbol_name, sys_ptr });
                    const func: *const fn () callconv(.c) void = @ptrCast(sys_ptr);
                    func();
                    atom.state = .Resolved;
                    return;
                } else {
                    log("[HEAVEN ERR] Symbole {s} introuvable (JIT et Système).\n", .{link.symbol_name});
                    return error.SymbolNotFound;
                }
            }
        }
        if (self.evaluate(matrix, atom_id)) |val| {
            platform.debug.print("[EVAL] Node {d} => {d}\n", .{ atom_id, val });
        }
    }
};
