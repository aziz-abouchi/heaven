# Prompt de continuité — Heaven session suivante

## HEAD
(a completer apres le push ci-dessus)

## Tests
28/28 tests peano verts. [KERNEL] type_check=true pool_size~1116.

## Session écoulée — kernel arithmetique complet
Teoremes derives par induction (tous valides sur arguments concrets 2,3,4) :
- add_comm, add_assoc, add_succ_right
- mul_zero_right, mul_succ_right, mul_comm
- distrib

Helpers exportes dans peano.zig :
mkAddCommProof, mkAddAssocProof, mkAddSuccRightProof,
mkMulZeroRightProof, mkMulSuccRightProof, mkMulCommProof,
mkDistribProof, mkCongSuccProof, mkCongAddLProof, mkCongAddRProof

Axiome primitif ajoute : eq_rect_nat (J-eliminator restreint Nat).
cong_succ et cong_add_l sont maintenant DERIVES via eq_rect_nat.

## Bugs / limites connus
1. mkCongAddLProof : cas NON-CLOS echoue (TypeMismatch sous [Nat]).
   Suspect : eq_rect_nat ou shift de P_body avec vars libres.
   TODO note dans le test "cong_add_l derivable via eq_rect_nat".
2. mkCongAddRProof n'existe pas encore - a deriver pareil.

## Pattern de bugs (3 occurrences historiques)
1. ih_type doit etre ecrit sous le contexte PRECEDENT (var(0) pour
   [k] seul), pas var(2).
2. Ordre des arguments de retour doit matcher l'ordre des Pi dans P.
   mkDistribProof : P = Pi b. Pi a. Pi c. donc retour (b_arg, a_arg, c_arg).
3. cong_add_l vs cong_add_r : l (2e arg) vs r (1er arg).

Ces bugs sont invisibles sur (zero,zero,...). Le test e2e sur (2,3,4)
est INDISPENSABLE.

## Architecture a terme (kernel)
delta-regles minimales (2 par operateur, 1er argument) :
  add(zero,n)->n ; add(succ k,n)->succ(add k n)
  mul(zero,n)->zero ; mul(succ k,n)->add(n,mul k n)
Equality : eq_rect_nat primitif, tout le reste derive.
Actuellement 4 axiomes de congruence encore declares (a terme
derives via eq_rect_nat) : sym, trans, cong_add_r, cong_succ.

## Prochaines actions
A. Deriver cong_add_r via eq_rect_nat (symetrique de cong_add_l).
B. Deriver sym et trans via eq_rect_nat.
C. Investiguer le bug non-clos de mkCongAddLProof.
D. Prototype 3a-2 (captureCont/throwCont).
E. Migration span_a.slice / serialisation v2.

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry.
WIP externe (core/std/*.hvn, parse.zig, test_suite.hvn).

## Methode
Petits pas verifies > gros refactor. Un commit = un theme.
Heredoc > 50 l. = tronque par navigateur -> scripts /tmp en 2-3 blocs.
zig test src/kernel/peano.zig (rapide) pour iterer kernel.
