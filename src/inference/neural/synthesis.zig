const std = @import("std");
const matrix_lib = @import("matrix_lib");
const platform = @import("platform");

pub const SynthesisError = error{
    OutOfMemory,
    NodeNotFound,
    InconsistentState,
};

pub const ProofSynthesizer = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    max_depth: u8 = 5,

    pub fn fillHole(self: *ProofSynthesizer, hole_id: matrix_lib.BobId) SynthesisError!bool {
        return self.fillHoleRecursive(hole_id, 0);
    }

    fn fillHoleRecursive(self: *ProofSynthesizer, hole_id: matrix_lib.BobId, depth: u8) SynthesisError!bool {
        if (depth > self.max_depth) return false;

        const node = self.matrix.nodes.get(hole_id) orelse return false;

        // On extrait le type et on s'assure qu'il existe
        const target_type = switch (node) {
            .Hole => |h| h.expected_type orelse return false, // Si null, on ne peut pas synthétiser
            else => return false,
        };

        var it = self.matrix.nodes.iterator();
        while (it.next()) |entry| {
            const term_id = entry.key_ptr.*;
            if (term_id == hole_id) continue;
            const node_data = entry.value_ptr.*;

            // 1. Axiome / Symbole direct
            const is_match = self.matrix.typesEqual(term_id, target_type);

            const name_match = blk: {
                if (node_data == .Symbol) {
                    const target_node = self.matrix.nodes.get(target_type) orelse break :blk false;
                    if (target_node == .Symbol) {
                        break :blk std.mem.eql(u8, node_data.Symbol, target_node.Symbol);
                    }
                }
                break :blk false;
            };

            if (is_match or name_match) {
                // platform.dbg("[SYNTH] Preuve directe: {d} -> {d}\n", .{ term_id, hole_id });
                self.matrix.fuseNodes(hole_id, term_id); // remplacé unify par fuseNodes
                _ = self.matrix.addEdge(term_id, hole_id, "PROVES") catch {};
                return true;
            }
        }

        return self.attemptApplicationSynthesis(hole_id, target_type, depth);
    }

    fn attemptApplicationSynthesis(self: *ProofSynthesizer, hole_id: matrix_lib.BobId, target_type: matrix_lib.BobId, depth: u8) SynthesisError!bool {
        var it = self.matrix.nodes.iterator();
        while (it.next()) |entry| {
            const func_id = entry.key_ptr.*;
            const node_data = entry.value_ptr.*;

            switch (node_data) {
                .Pi => |pi_data| {
                    if (self.matrix.typesEqual(pi_data.codomain, target_type)) {
                        const arg_hole = self.matrix.addHole("arg", pi_data.domain) catch return SynthesisError.OutOfMemory;

                        if (try self.fillHoleRecursive(arg_hole, depth + 1)) {
                            const args = self.allocator.alloc(matrix_lib.BobId, 1) catch return SynthesisError.OutOfMemory;
                            args[0] = arg_hole;

                            const app_id = self.matrix.addNode(.{
                                .Apply = .{ .function = func_id, .args = args },
                            }) catch return SynthesisError.OutOfMemory;

                            self.matrix.fuseNodes(hole_id, app_id);
                            _ = self.matrix.addEdge(func_id, app_id, "CALL") catch {};
                            _ = self.matrix.addEdge(arg_hole, app_id, "ARG") catch {};
                            _ = self.matrix.addEdge(app_id, hole_id, "RESOLVE") catch {};

                            // platform.dbg("[SYNTH] Déduction réussie via Application {d}\n", .{app_id});
                            return true;
                        }
                    }
                },
                else => continue,
            }
        }
        return false;
    }
};
