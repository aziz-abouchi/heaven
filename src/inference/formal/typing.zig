const std = @import("std");
const matrix_lib = @import("../core/matrix.zig");

pub fn typerSumRule(matrix: *matrix_lib.Matrix, node_id: matrix_lib.BobId) !void {
    // Logique agnostique : on regarde les enfants porteurs de types
    // Si enfant A a le tag "type:int" et enfant B aussi
    // Alors on pose le tag "type:int" sur node_id
    _ = matrix;
    // (Simulation de logique pour l'exemple)
    platform.debug.print("[TYPING] Résolution de la règle de somme pour le nœud {d}\n", .{node_id});
}
