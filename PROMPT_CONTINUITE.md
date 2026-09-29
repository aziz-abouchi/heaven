# Prompt de continuité — Heaven session suivante

## HEAD
df278cb (main) — test(kernel): subst shifts replacement under binder
Session : e943eb2 (nat_ind type-check) + df278cb (test subst).
Pushé sur origin/main.

## Tests
173/173 Zig (1 skipped), 91/91 test_suite.hvn, 0 fuite.

## Session écoulée
- nat_ind_type : indices De Bruijn corrigés (p_k var(2), p_succ_k var(3),
  p_n var(3)). Les binders base et step sont sur la pile, pas seulement P.
- infer nat_zero/nat_succ : lookupAxiom("Nat") renvoie Type(0), pas Nat.
  Remplacé par mkRef(Nat) direct.
- Test sanity nat_ind : P=λn.Eq(n,n), base=refl(zero),
  step=λk.λih.refl(succ k) → type_check=true.
- Test non-régression subst (shift replacement sous binder).

## État chantier type_check kernel induction
Kernel type-check nat_ind sur théorème réflexif : OK.
verifyByInduction retourne type_check=false car le proof term réel
(add_comm) est un stub : base et step n'utilisent pas ih.

## Prochaine action
Construire la vraie preuve CIC de add_comm :
1. Ajouter cong_succ (ou eq_rect) dans initNatAxioms.
2. step_proof utilisant ih :
   ih(m) : Eq(add k m, add m k)
   cong_succ(ih(m)) : Eq(succ(add k m), succ(add m k))
   Puis conversion vers Eq(add(succ k, m), add(m, succ k))
   via add_succ_right + symétrie à ajouter.
3. Faire passer type_check=true dans verifyByInduction.

## Fichiers de référence
- src/kernel/peano.zig — infer/check/convertible/subst/eval
  + tests sanity nat_ind et subst shift (fin de fichier)
- src/core/proof_core.zig — verifyByInduction (~ligne 353)
- docs/spec/_proof.md — architecture preuve
- docs/spec/_continuations.md — Option B proposée, à valider

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry.

## Méthode
Petits pas vérifiés > gros refactor.
Un commit = un thème. Tests verts avant commit.
rm -rf .zig-cache/* zig-out avant chaque validation.
zig build test --summary all, puis zig build && zig build test-regression.
