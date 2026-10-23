# Emancipation Heaven -- roadmap (2026-10-24)

## Objectif
Supprimer Zig du toolchain. Zig = bootloader (~500 lignes loader).
Tout le reste en .hvn ou transpile vers backends.

## Phases (ordre acte)
E3 : bootstrap heaven.zig -> loader minimal (PARITIEL, depend E1)
E2 : backend C en .hvn (lib/backend/c.hvn)
E1 : lib/meta/eval.hvn COMPLET (100%% du langage)
E4 : WASM / WASI / WASM-web
E5 : JS
E6 : Zig auto-heberge
E7 : BEAM (Erlang/OTP)
E8 : JVM (bytecode)
E9 : Multi-plateforme (aarch64, macOS, Windows, BSD)
E10 : Lustre-like (REPL / VISION / IDE)

## Risques identifies

E3 avant E1 = bootstrap partiel : features .hvn non supportees par
eval.hvn actuel -> erreur gracieuse, pas crash. Documente.
E2 avant E1 = backend C partiel : meme limite.
Apres E1, E2/E3 deviennent complets.

## Dependances techniques
E2 depend de : E1 (eval.hvn pour AST), grammar .hvn stable
E3 depend de : E1 (eval.hvn complet), loader arg parsing
E1 depend de : types.zig non-stub (DependentChecker), fix poke/peek

## Backends (multi-cibles)
| Backend | Etat | Effort |
| C | src/codegen/c.zig (partiel) | 2-3 sessions |
| WASM | src/backend/wasm.zig (partiel) | 2-3 sessions |
| WASI | rien | 1-2 sessions (sur WASM) |
| JS | expr_js.zig (partiel) | 2-3 sessions |
| Zig auto | rien | 2-3 sessions |
| BEAM | rien | 5-8 sessions |
| JVM | rien | 6-10 sessions |


## Non-objectifs V0
- Pas de backend BEAM/JVM avant E1 complet
- Pas de Lustre avant E9 (multi-plateforme)
- Pas de Zig auto-heberge avant E2 (C backend) valide


## Decision E1 (2026-10-24)

**Regle** : surface utilisateur = infixe uniquement.
S-Expr = representation interne (desucrage, AST, eval).

**Pipeline** :
  .hvn (infixe) -> [lib/parse/infix.hvn] -> AST S-Expr -> [lib/heaven_eval.hvn] -> Valeur

**Ordre revise** : E1 (parse_infix) -> E3 (meta) -> E2 (C) -> E4..E10
E3 avant E1 = S-expr only = violate la regle.


## E1.2 -- if/then/else (BLOQUE, 2026-10-24)

Tentative ajout if/then/else a infix.hvn : rollback.
Symptome : import infix.hvn crash silencieusement (aucun print,
exit 0). Meme "start" n apparait pas.

Cause probable : is_kw (HP.TSymTok tk) s = (= tk s) -- pattern match
sur TSymTok avec deux args au lieu d un. Ou parse_if boucle.

A reprendre session fraiche : tester is_kw seul, puis parse_if
incrementalement (parse_if sur "if 1 then 2 else 3" sans l import
global, un cas a la fois).

