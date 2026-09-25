// ═══════════════════════════════════════════════════════════
// Heaven Kernel — point d'entrée canonique
//
// Deux représentations cohabitent :
//   • peano.zig  : pool d'indices u32, Nat/Eq natifs — moteur
//                  historique de `prove by induction`, iso-morphique
//                  avec expr.zig (Store) → pont Expr ↔ Term trivial.
//   • ast.zig & co : CIC à pointeurs, quotients complets, Eq/refl
//                  typés — cible d'unification à long terme.
//
// API de façade : importer `kernel` et ne rien voir d'autre.
// ═══════════════════════════════════════════════════════════
pub const peano = @import("peano.zig");
pub const ast = @import("ast.zig");
pub const typechecker = @import("typechecker.zig");
pub const conversion = @import("conversion.zig");
pub const transform = @import("transform.zig");
// DÉSACTIVÉ — strategy.zig référence tta.zig/kb.zig inexistants (code
// généré incomplet, jamais compilé avant la façade). À réactiver quand
// le système de stratégies sera réellement conçu.
// pub const strategy = @import("strategy.zig");

// ─── Ré-export du kernel Peano (API historique, consommée par proof_core) ───
pub const TermPool = peano.TermPool;
pub const Term = peano.Term;
pub const TermTag = peano.TermTag;
pub const Context = peano.Context;
pub const KernelError = peano.KernelError;

pub const eval = peano.eval;
pub const infer = peano.infer;
pub const check = peano.check;
pub const convertible = peano.convertible;
pub const verify = peano.verify;
pub const verifyStructural = peano.verifyStructural;
pub const initNatAxioms = peano.initNatAxioms;

// ─── API CIC (nouvelle génération) ───
pub const CIC = struct {
    pub const TypeChecker = typechecker.TypeChecker;
    pub const Conversion = conversion.Conversion;
    pub const termsStructurallyEqual = ast.termsStructurallyEqual;
};
