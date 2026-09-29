# Prompt de continuité — Heaven session suivante

## HEAD
6d0f388 (main) — perf(kernel): short-circuit eval(.app) stuck
Tout poussé sur origin/main.

## Tests
176/177 Zig (1 skipped), 94/94 test_suite.hvn, 0 fuite.
[KERNEL] structural=true type_check=true (symbolic_step=true) pool_size=1083

## Session écoulée — 13 commits
Kernel : e943eb2, df278cb, 156daa2, c6445af, b33183e, 3cf37b9,
         99380af, 52263b8, ebc4731, 6d0f388
Docs  : 22b2466, 886dc19
Proto : 87c6545 (Prototype 3a-1 PromptStack)

Commits externes (pas de nous, sur main) :
- 2be075d feat: Tail Call Optimization (TCO) via trampoline
  94/94 tests HVN (tco_deep 100k en ~4s), 5 nouveaux tests

## Jalons kernel
1. [KERNEL] type_check=true sur add_comm via verifyByInduction.
2. add_zero_right retiré (dérivable).
3. add_succ_right retiré (dérivable via mkAddSuccRightProof).
4. Plus aucun axiome de réduction sur add (hors δ définitionnelles).

## Découvertes importantes (ne pas réapprendre)
1. Context.push stocke le type_idx brut. infer(.var_) doit shifter
   de (db_idx + 1). Sans ce fix, toute variable sous contexte
   empilé a un type faux (capture). BUG FONDAMENTAL corrigé (b33183e).
2. eval doit short-circuit PARTOUT (nat_succ, eq, pi, app) : sinon
   runaway d'allocations → crash DebugAllocator. Deux fixes :
   3cf37b9 (.nat_succ/.eq/.pi) + 6d0f388 (.app stuck).
3. Indices DB dans nat_ind_type : binders base et step sur la pile.
4. `zig test src/kernel/peano.zig` plus rapide que zig build test.

## Prototype 3a-1 livré
src/core/continuation.zig : PromptStack (push/pop/top/depth).
Intégré à build.zig (test_continuation). 3 tests verts.

## Prochaines actions possibles
A. Prototype 3a-2 : captureCont/throwCont (dense, 1 session).
   Design délicat : segment copié en heap par frame.
B. Autres axiomes à déclassifier : mul_zero_right, mul_succ_right.
C. Migration 181 sites span_a.slice.
D. Sérialisation v2 (reachable subset, prérequis C2).

## Fichiers de référence
- src/kernel/peano.zig — infer/check/convertible/subst/eval/shift
  + mkAddSuccRightProof + 6 tests
- src/core/proof_core.zig — verifyByInduction (preuve CIC réelle)
- src/core/continuation.zig — PromptStack (3a-1)
- docs/DECISIONS.md — D1-D8
- docs/spec/_continuations.md — Option B, Prototype 3a
- docs/spec/_concurrency.md — C1-C5

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry.

## Méthode
Petits pas vérifiés > gros refactor. Un commit = un thème.
Tests verts avant commit.
rm -rf .zig-cache/* zig-out avant chaque validation.
zig build test --summary all, puis zig build && zig build test-regression.
