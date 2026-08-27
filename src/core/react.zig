const std = @import("std");
const matrix_lib = @import("matrix_lib");
const unify_lib = @import("unify.zig");
const BobId = matrix_lib.BobId;
const platform = @import("platform");

pub const ReactionEngine = struct {
    matrix: *matrix_lib.Matrix,
    allocator: std.mem.Allocator,

    pub fn processNewFact(self: *ReactionEngine, fact_id: BobId) !void {
        const Ctx = struct {
            engine: *ReactionEngine,
            fact_id: BobId,
            fn checkNode(node_id: BobId, node: matrix_lib.BobNode, ctx: *@This()) void {
                _ = node_id; // paramètre inutilisé
                if (node == .Rule) {
                    const rule = node.Rule;
                    var subst = unify_lib.Substitution.init(ctx.engine.allocator);
                    defer subst.deinit();
                    for (rule.body) |condition_id| {
                        if (unify_lib.unify(ctx.engine.matrix, &subst, ctx.fact_id, condition_id) catch false) {
                            ctx.engine.triggerRule(rule.head, &subst) catch |err| {
                                platform.dbg("[REACTION] Erreur triggerRule: {s}\n", .{@errorName(err)});
                            };
                        }
                    }
                }
            }
        };
        var ctx = Ctx{ .engine = self, .fact_id = fact_id };
        self.matrix.forEachNode(Ctx.checkNode, .{&ctx});
    }

    fn triggerRule(self: *ReactionEngine, head_id: BobId, subst: *unify_lib.Substitution) !void {
        // On matérialise la tête de la règle avec les variables trouvées
        const new_fact_id = try self.materialize(head_id, subst);

        // On informe le monde
        platform.dbg("[REACTION] Règle activée ! Conclusion matérialisée (ID: {d})\n", .{new_fact_id});
    }

    fn materialize(self: *ReactionEngine, node_id: BobId, subst: *unify_lib.Substitution) !BobId {
        const actual_id = subst.lookup(node_id);
        const node = self.matrix.getNode(actual_id) orelse return actual_id;

        // Si c'est une structure, on doit cloner ses enfants récursivement
        // en appliquant les substitutions au passage.
        switch (node) {
            .Relation => |rel| {
                var new_args = try self.allocator.alloc(BobId, rel.args.len);
                for (rel.args, 0..) |arg, i| {
                    new_args[i] = try self.materialize(arg, subst);
                }
                return try self.matrix.addNode(.{ .Relation = .{ .predicate = rel.predicate, .args = new_args } });
            },
            // ... étendre aux autres types (HCall, Send, etc.)
            else => return actual_id,
        }
    }
};
