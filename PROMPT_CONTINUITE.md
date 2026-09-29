# Prompt de continuité — Heaven session suivante

## HEAD
d62e110 (main) — feat(kernel): delta-regles mul + mul_zero_right derivable
Tout poussé sur origin/main.

## Tests
177/177 Zig + WIP externe (voir note), 116/145 HVN + WIP externe.
[KERNEL] structural=true type_check=true pool_size=1083.

## Session écoulée — 16 commits
Kernel : e943eb2, df278cb, 156daa2, c6445af, b33183e, 3cf37b9,
         99380af, 52263b8, ebc4731, 6d0f388, d62e110
Docs  : 22b2466, 886dc19, 5842f7c
Proto : 87c6545 (Prototype 3a-1 PromptStack)

Externe (pas de nous) : 2be075d (TCO trampoline).

## WIP non commitée (autre session, NE PAS TOUCHER)
core/std/list.hvn, core/std/option.hvn, core/std/result.hvn,
core/test_suite.hvn, src/vessel/public/test_suite.hvn
(rajout ~262 lignes, dont +29 tests HVN).

## Jalons kernel atteints
1. [KERNEL] type_check=true sur add_comm via verifyByInduction.
2. add_zero_right retiré (dérivable).
3. add_succ_right retiré (helper mkAddSuccRightProof).
4. delta-regles mul ajoutées (peano_mul).
5. mul_zero_right dérivé par nat_ind.

## Découvertes importantes (ne pas réapprendre)
1. Context.push stocke le type_idx brut. infer(.var_) doit shifter
   de (db_idx + 1). Sans ce fix, variable sous contexte empilé =
   type faux (capture). BUG FONDAMENTAL (b33183e).
2. eval doit short-circuit PARTOUT (nat_succ/eq/pi/app) : sinon
   runaway d'allocations → crash DebugAllocator. Deux fixes :
   3cf37b9 (.nat_succ/.eq/.pi) + 6d0f388 (.app stuck).
3. Indices DB dans nat_ind_type : binders base et step sur la pile.
4. `zig test src/kernel/peano.zig` plus rapide pour itérer kernel.
5. Heredoc > 50 lignes = tronqué par navigateur. Préférer
   cat > /tmp/script.py puis python3 /tmp/script.py en 2-3 blocs.

## Prochaine action — mul_succ_right (chantier dédié)
mul_succ_right : Pi n m. Eq(mul n (succ m), add(mul n m) n)
Beaucoup plus dur que add_succ_right : necessite add_comm ET
associativite de add a l'interieur du proof term.
~2h, a attaquer a froid.

Alternatives :
- Prototype 3a-2 (captureCont/throwCont) — 1 session dense
- Migration 181 sites span_a.slice
- Serialisation v2 (reachable subset)

## Fichiers de reference
- src/kernel/peano.zig — infer/check/convertible/subst/eval/shift
  + mkAddSuccRightProof + 7 tests + delta mul
- src/core/proof_core.zig — verifyByInduction (preuve CIC reelle)
- src/core/continuation.zig — PromptStack (3a-1)
- docs/DECISIONS.md — D1-D8
- docs/spec/_continuations.md — Option B, Prototype 3a

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry.
+ WIP non commit ci-dessus (autre session).

## Methode
Petits pas verifies > gros refactor. Un commit = un theme.
Tests verts avant commit.
rm -rf .zig-cache/* zig-out avant chaque validation.
zig build test --summary all, puis zig build && zig build test-regression.
