const std = @import("std");
const matrix_lib = @import("../../core/matrix.zig");

pub const RelationType = enum {
    Identity, // A ≅ B
    Dependency, // A nécessite B
    Exclusion, // A interdit B
    Constraint, // A doit être < B
};

pub const Relation = struct {
    type: RelationType,
    subject_id: usize,
    object_id: usize,

    /// Vérifie si la relation est satisfaite dans la Matrix actuelle
    pub fn isSatisfied(self: @This(), matrix: *matrix_lib.Matrix) bool {
        const sub = matrix.getNode(self.subject_id);
        const obj = matrix.getNode(self.object_id);

        return switch (self.type) {
            .Identity => std.mem.eql(u8, sub.symbol, obj.symbol),
            .Dependency => matrix.hasConnection(self.subject_id, self.object_id),
            .Exclusion => !matrix.hasConnection(self.subject_id, self.object_id),
            .Constraint => parseAndCompare(sub.symbol, obj.symbol),
        };
    }
};
