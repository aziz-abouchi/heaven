const std = @import("std");
const effects = @import("effects.zig");
const matrix_lib = @import("../core/matrix.zig");

pub const Censor = struct {
    /// Analyse un effet et décide s'il peut passer la barrière de conscience
    pub fn validate(matrix: *matrix_lib.Matrix, effect: effects.EffectType) bool {
        // Règle de Conscience 1 : Silence Réseau
        if (effect == .NetworkSend) {
            if (matrix.hasSymbol("NETWORK_SILENCE")) return false;
        }

        // Règle de Conscience 2 : Préservation Thermique (Green)
        if (effect == .CoreKill) {
            if (matrix.hasSymbol("CRITICAL_OVERHEAT")) return true; // Autorisé si surchauffe
        }

        return true; // Par défaut, la Légion fait confiance à ses membres
    }
};
