# Prompt de continuité — Heaven session suivante

## HEAD
99380af (main) — feat(proof): verifyByInduction branche la vraie preuve CIC
Session : 7 commits (e943eb2 → 99380af). Tout poussé sur origin/main.

## Tests
174/174 Zig (1 skipped), 91/91 test_suite.hvn, 0 fuite.
[KERNEL] structural=true type_check=true (symbolic_step=true) pool_size=1151

## Session écoulée — jalon kernel atteint
Le kernel type-check une VRAIE preuve d'induction, pas un stub.

Commits :
- e943eb2 fix(kernel): nat_ind type-check (3 indices DB + nat_zero/succ)
- df278cb test(kernel): subst shifts replacement under binder
- 156daa2 feat(kernel): axiome cong_succ
- c6445af feat(kernel): axiomes sym + trans
- b33183e fix(kernel): shift types dans infer(.var_) + preuve CIC add_comm
- 3cf37b9 perf(kernel): eval short-circuit + cap pool 100k
- 99380af feat(proof): verifyByInduction branche la vraie preuve CIC

## Découvertes importantes (ne pas réapprendre)

1. Context.push stockait le type_idx brut. infer(.var_) doit shifter
   de (db_idx + 1) avant retour. Sans ce fix, toute variable sous un
   contexte empilé a un type faux (capture de variable).
2. eval ne short-circuitait pas : après le branchement de la preuve
   réelle, runaway d'allocations → crash DebugAllocator "double-mapped
   pages" (corruption GPA). Fix : si sous-termes inchangés, retourne
   term_idx au lieu de réallouer. Cap pool 100k en garde-fou.
3. Indices De Bruijn dans nat_ind_type : les binders base et step
   sont sur la pile, pas seulement P. Profondeur réelle à chaque usage.
4. Sym/temp d'un test unitaire : `zig test src/kernel/peano.zig`
   donne un retour bien plus rapide que zig build test.

## Base de confiance (kernel) — état actuel
Prouvé par induction : add_comm (via nat_ind, cong_succ, sym, trans,
add_succ_right, δ sur add).
Assertés (axiomes) : Nat, zero, succ, add, mul, nat_ind,
add_zero_right, add_succ_right, cong_succ, sym, trans.
À déclassifier : add_zero_right, add_succ_right → prouvables par
induction quand on aura automatisé add_comm dans les tactiques.

## Prochaines actions possibles
A. Déclassifier add_zero_right/add_succ_right (les prouver).
B. Option B continuations (validation _continuations.md, Proto 3a-1).
C. Migration 181 sites span_a.slice.
D. Sérialisation v2 (reachable subset, prérequis C2).

## Fichiers de référence
- src/kernel/peano.zig — infer/check/convertible/subst/eval/shift
  + 4 tests en fin de fichier (nat_ind, subst shift, cong_succ,
  sym+trans, add_comm) + cap pool 100k
- src/core/proof_core.zig — verifyByInduction (~ligne 470)
  proof term réel branché
- docs/spec/_proof.md — architecture preuve
- docs/spec/_continuations.md — Option B proposée, à valider

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry.

## Méthode
Petits pas vérifiés > gros refactor. Un commit = un thème.
Tests verts avant commit.
rm -rf .zig-cache/* zig-out avant chaque validation.
zig build test --summary all, puis zig build && zig build test-regression.
