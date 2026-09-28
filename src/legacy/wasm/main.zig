const std = @import("std");
const heaven_expr = @import("heaven_expr");
const types = @import("../core/types.zig");
const prolog = @import("../runtime/prolog.zig");

// On réutilise tes buffers de communication globaux existants
extern fn getInputPtr() [*]u8;
extern fn getOutputPtr() [*]u8;

/// Exporte l'inférence de type avancée (HM + QTT + Dépendants) vers le Web REPL
export fn heavenCheckType(len: usize) usize {
    const input = getInputPtr()[0..len];
    const allocator = std.heap.page_allocator; // Ou ton pool dédié si partagé

    // Parse, infère via le DependentChecker / HM, et écrit le résultat
    const res_str = types.inferAndFormat(allocator, input) catch "Type Error";

    @memcpy(getOutputPtr()[0..res_str.len], res_str);
    return res_str.len;
}

/// Exporte le moteur de preuve (by eval, by simplify, by induction)
export fn heavenVerifyTheorem(len: usize) usize {
    const input = getInputPtr()[0..len];
    const allocator = std.heap.page_allocator;

    // Format attendu du JS : "add_comm : a + b = b + a by commutativity"
    const report = heaven_expr.parseAndVerifyInline(allocator, input) catch "Proof Failed";

    @memcpy(getOutputPtr()[0..report.len], report);
    return report.len;
}

/// Exporte les requêtes Prolog / miniKanren au Web REPL
export fn heavenLogicQuery(len: usize) usize {
    const input = getInputPtr()[0..len];
    const allocator = std.heap.page_allocator;

    // Exécute la requête (:ask ou :run) sur le store WASM isolé
    const results = prolog.queryFromWasm(allocator, input) catch "No Solution";

    @memcpy(getOutputPtr()[0..results.len], results);
    return results.len;
}
