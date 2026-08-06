const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub const Solver = struct {
    pub fn solve(self: Solver, matrix: *matrix_lib.Matrix, goal: matrix_lib.BobId) bool {
        _ = self;

        var it = matrix.nodes.iterator();

        while (it.next()) |entry| {
            const node = entry.value_ptr.*;

            if (node == .Rule) {
                if (matrix.findCanonical(node.Rule.head) == matrix.findCanonical(goal)) {
                    var ok = true;

                    for (node.Rule.body) |subgoal| {
                        if (!self.solve(matrix, subgoal)) {
                            ok = false;
                            break;
                        }
                    }

                    if (ok) return true;
                }
            }
        }

        return false;
    }
};
