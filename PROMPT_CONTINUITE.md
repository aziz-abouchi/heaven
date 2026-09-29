# Prompt de continuité — Heaven session suivante

## HEAD
7acec12 (main) — feat(kernel): axiomes cong_add_l + cong_add_r
Tout poussé sur origin/main.

## Tests
176/177 Zig (1 skipped), HVN variable (WIP externe, voir note).
[KERNEL] structural=true type_check=true pool_size=1083.
peano.zig : 21/21 tests verts.

## Session écoulée — 19 commits poussés
Kernel : e943eb2, df278cb, 156daa2, c6445af, b33183e, 3cf37b9,
         99380af, 52263b8, ebc4731, 6d0f388, d62e110, 0635d1f,
         7acec12
Docs  : 22b2466, 886dc19, 5842f7c, 2f700e4
Proto : 87c6545 (PromptStack 3a-1)

Externe (pas de nous) : 2be075d (TCO), d9d35ba (TCO bounce).

## WIP externe non commité (AUTRE SESSION, NE PAS TOUCHER)
core/std/list.hvn, option.hvn, result.hvn, core/test_suite.hvn,
src/vessel/public/test_suite.hvn, src/core/heaven_expr.zig,
src/core/parse.zig, patch_parser_infix.py (untracked).

## Jalons kernel atteints
1. [KERNEL] type_check=true sur add_comm via verifyByInduction.
2. add_zero_right, add_succ_right, mul_zero_right : dérivés/retirés.
3. delta-règles mul ajoutées (peano_mul).
4. mkAddAssocProof (add_assoc dérivé).
5. cong_add_l + cong_add_r (axiomes provisoires).

## En cours — mul_succ_right (BLOQUÉ, à reprendre à froid)
Helper mkMulSuccRightProof partiellement écrit mais retire avant
commit (git checkout). Debug laisse : infer(proof) = TypeMismatch
sous contexte [k, ih, m].

Structure identifiée du proof term (5 maillons) :
h1  = cong_add_l(mul k (succ m), add X k, ih(m), m)
h1' = cong_succ(add m (mul k (succ m)), add m (add X k), h1)
assoc = mkAddAssocProof(m, X, k)   [X = mul k m]
h2  = cong_succ(add m (add X k), add (add m X) k, sym(assoc))
step_inner_23 = trans(h1', h2)  (type : Eq(succ(mul...), succ(add (add m X) k)))
h3  = sym(mkAddSuccRightProof(add m X, k))
step_inner = trans(step_inner_23, h3)

Suspects du TypeMismatch (à isoler par prints ciblés) :
- mkAddAssocProof appelé sous [k, ih, m] : vérifier que les
  indices DB de son P_body sont corrects dans ce contexte (ils
  sont var(2), var(1), var(0) sous [a, b, c] du nat_ind, mais
  appliqué ici il doit s'adapter).
- cong_add_l : vérifier arité et indices sur appel concret.

## Découvertes importantes (ne pas réapprendre)
1. Context.push stocke type_idx brut. infer(.var_) doit shifter
   de (db_idx + 1). BUG FONDAMENTAL corrige (b33183e).
2. eval doit short-circuit PARTOUT (nat_succ/eq/pi/app) sinon
   runaway -> crash DebugAllocator (3cf37b9, 6d0f388).
3. Indices DB dans nat_ind_type : binders base et step sur la pile.
4. ih_type d'un binder Pi doit s'ecrire sous le contexte PRECEDENT
   (ex: sous [k] seulement pour mkMulSuccRightProof). Ecrire k=var(2)
   donne UnboundVariable.
5. Heredoc > 50 l. = tronque par navigateur. Preferer
   cat > /tmp/s.py puis python3 /tmp/s.py en 2-3 blocs.

## Architecture à terme (vision kernel)
delta-regles minimales (2 par operateur, sur 1er argument) :
  add(zero, n) -> n ; add(succ k, n) -> succ(add k n)
  mul(zero, n) -> zero ; mul(succ k, n) -> add(n, mul k n)
TOUT le reste = theoremes (add_zero_right, mul_succ_right, comm...).
Congruence : idealement eq_rect unique (J-eliminator) remplacant
cong_succ, cong_add_l/r, sym, trans. Compromis actuel acceptable.

## Prochaines actions
A. Finir mul_succ_right (~1h, debug cible).
B. Prototype 3a-2 (captureCont/throwCont) — 1 session dense.
C. Migration span_a.slice (181 sites).
D. Serialisation v2.

## NE PAS TOUCHER
wasm.zig, kernel.zig, mir.zig, x86_64_windows.zig, aarch64_macos.zig,
commands.zig (racine), transform.zig, kernel_bridge.zig,
branche feat/physical-telemetry + WIP externe ci-dessus.

## Methode
Petits pas verifies > gros refactor. Un commit = un theme.
rm -rf .zig-cache/* zig-out avant chaque validation.
zig test src/kernel/peano.zig (rapide) pour iterer kernel.

# Addendum — session « TCO & bugs moteur » 2026-09-29 (parallèle)

## Commits poussés
- d9d35ba fix(core): TCO — bounce limité à la spine de queue
- c620281 fix(parser): fact/query + f(x) ne corrompent plus les defs
- 35b99d8 fix(eval): ctors minuscules = valeurs (racine stdlib List)
- 629110b docs: BACKENDS.md (MIR contrat commun, Green/Fast, M0-M5)

## Bugs fermés
- #9A/#9B : TCO_BOUNCE (0xFFFFFFFF) fuyait dans l'évaluateur
  (panic get() sur size/fact/verify_book) + résultat jeté au rebond.
  Fix : collectTailSpine — bounce seulement depuis le corps ou une
  branche de if. count_down garde son TCO, fact/size redeviennent
  récursion ordinaire correcte.
- C1 : `fact n = ...` dévoré par la commande kanren (garde " = ").
- C2a : `f(x) = ...` enregistrait une fonction nommée "f(x)".
- C3 : evaluate(.sym) rejetait les ctors minuscules (nil/cons/ok).

## Bugs ouverts (diagnostiqués)
- C2b : corps mono-token true/false → symbole non lié.
  Repro : fn bar x = true ; bar 1 → UnboundVariable.
  (fn foo x = x OK ; multi-tokens OK). parse.zig, côté parser.
- C2c : `fn f x = if (= x 1) 1 9` échoue ; `f(x) = <même corps>`
  marche (chemins de parse distincts).
- Fuite mémoire : runs test_suite WIP sans "Memory clean" en fin.
- Dettes : whitelist {zero,succ,quote} + heuristique majuscule
  redondantes avec le check fns ; shadowing silencieux fn→ctor
  dans evalDataDecl ; tco_deep ~40µs/iter ; t_distrib ~2s ;
  README périmé (39 tests, MIR 40%, zig build wasm inexistant).

## Conventions de session (cumulées aux 8 existantes)
- #9 : git add ciblé — jamais -A en multi-session.
- #10 : git status vide de MODIFICATIONS avant tout reset --hard.
- #11 : heredoc ≤ 40 lignes ; intégrité par comptages structurels.
- #12 : une probe de discrimination isole UNE variable
  (casse≠paramétrage m'a coûté 3 tours — cf C3).

## État fin de session
main = 35b99d8. Suite base 94/94 (tco_deep ✓), verify_book 40/43
(3 échecs pré-existants), section 11 WIP 100/100 sur binaire
avec nos fixes. Deux sessions actives, pile linéaire, zéro conflit.
