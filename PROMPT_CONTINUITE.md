# Prompt de continuité — Heaven session suivante

## HEAD
11ca8f4 (main) — docs sync 2026-09-30 (STATUS/BACKENDS/CHANGELOG)
Session : f31b2eb (fix mir+defs), 22de554 (_bench.md), 097a493 (fib.hvn)
Tout poussé sur origin/main.

## Tests
Zig : 381/382 (1 skip test_mir_wat).
HVN : ~95/95.

## Ce qui a été fait cette session
- QBE v1.2 opérationnel (compile + bench).
- WASM via wasmtime (M2a/M2b).
- bench-interp / bench-qbe / bench-wasm : wall, cpu, energy RAPL,
  temperature, RSS, --loop.
- Compilation des fonctions utilisateur recursives : fib(25) = 75025
  en QBE 1.15 ms (vs 29824 ms interprete, ~26000x).
- bench/run.sh, bench/progs/{count_down,arith,loop,fib}.hvn.
- docs/spec/_bench.md : methodologie et resultats.

## Fix majeur — fonctions utilisateur (f31b2eb)
3 bugs chaines :
1. defs.zig : parseSExpr pour les corps S-expr purs. parseExpression
   -> tree-sitter confond `<` avec une balise et currifie.
2. defs.zig : lowerRec uniforme (le cas "sans patterns" l'oubliait).
3. mir.zig : precompileUserFns en 2 passes (placeholders avant
   compilation des corps). Resout la recursion (fib appelle fib).

## Etat de l'arbre (2026-10-02)

Le conflit de stash sur `src/vessel/public/test_suite.hvn` est
resolu (`tco_deep` reajoute). L'arbre est propre a part les
modifications en cours de cette session.

Un commit local `3469bc3` (session parallele, eval.zig + math.zig)
attend d'etre pousse.

## Pistes actives (2026-10-02)

### Court terme

1. **D1bis** — degager les imports morts de `main.zig` (30 min).
   `heaven_lib`, `react_lib`, `SRG`, `EQSATPlanner`, `transpiler_lib`
   sont importes mais jamais utilises au runtime. Voir
   `DECISIONS.md` D1 revisee.

2. **Leaks residuels** — voir section dediee plus bas. L1
   (`proofs.zig:222`) et L2 (`interactive.zig:146`).

3. **`[fns.deinit] freeing key=...`** — ~90 lignes de debug print
   a chaque shutdown. Conditionner a `HEAVEN_DEBUG=1`.

### Moyen terme

4. **D8 — continuations delimitees**. `src/core/continuation.zig`
   existe (334 l., 9 tests) mais n'est branche nulle part.
   Etape 3a-3 : brancher dans `engine_expr.zig` + tests end-to-end.
   Debloque `handle-rec` et le scheduler preemptif.

5. **D9 — decoupler Vessel d'Astra** (1-2 sessions). Vessel lit
   `matrix.getStats()`, `matrix.nodes.iterator()`. Recabler sur
   `expr.Store`. Debloque la suppression effective de `matrix.zig`
   et elimine le doublon de bootstrap.

6. **Audit des 39 `@panic`/`unreachable`** (1 session). Le nombre
   a double depuis 2026-09-29 (19 -> 39). A trier : defensifs vs
   bugs latents.

### Long terme

7. **wasm32-wasi** (A : compilateur en WASI ; B : programmes
   compiles en WASI). Session parallele a cree
   `src/platform/wasm32_wasi.zig` (542 l.). Priorite basse.

8. **Cross-compilation** vers d'autres arches / OS. QBE est deja
   multi-cible (x86-64/ARM64/RISC-V), a brancher dans `build.zig`.

9. **Cycles SCC 3+ fonctions** (TCO mutuelle etendue). Actuellement
   limite aux paires.

10. **Auto-hebergement** (long terme) : BigInt (libtommath), I/O,
    structures de donnees, puis self-parse/self-compile.

## Bug matrix (RESOLU 2026-10-01)

Le `Invalid free` au shutdown du REPL (`matrix.zig:237`,
`free(func.params)`) est corrige (`c27cc54`). Cause : la Matrix
liberait des slices qui appartenaient a l'arena de
`UniversalIngestor`. Fix : retirer les 7 free Forge de
`matrix.deinit()`.

## Leaks residuels (RESOLUS 2026-10-02)

Les deux leaks L1 (proofs.zig:222) et L2 (interactive.zig:146)
identifies le 2026-10-01 sont **resolus** :

- Verification : `theorem t : x + 0 = x` + `prove t by simplify`
  + `abort` + EOF dans preuve : 0 leak (HEAVEN_DEBUG=1).
- `zig build test` : aucun leak.

Ils ont ete corriges par les refactors des sessions 2026-10-01 et
2026-10-02 (PROMPT restructure, run.zig defer free, etc.). Aucune
action residuelle.

## Debug print bruyant

`[fns.deinit] freeing key=...` : ~90 lignes a chaque shutdown
(`engine_expr.zig:252`). A conditionner a `HEAVEN_DEBUG=1`.

## Fichiers de reference
- src/commands/qbe_cmd.zig, wasm_cmd.zig, bench_interp.zig
- src/backend/mir_qbe.zig, mir_wat.zig
- src/core/mir.zig (precompileUserFns)
- src/core/commands/defs.zig (parseSExpr)
- bench/run.sh, bench/progs/
- docs/spec/_bench.md

## Methodes
- Heredoc > 50 l. = tronque par navigateur (scinder en 2-3 blocs).
- git add cible uniquement (jamais -A, 3 sessions sur l'arbre).
- Avant de retoucher mir.zig/defs.zig, verifier qu'aucune session
  parallèle n'y travaille.
- Utiliser src/platform/* pour toute syscall, jamais std.posix direct.

## Addendum -- session guards (2026-10-01)

### Livre
- 867ec43 : guards sur clauses (f p | cond = body). 17/17.
  6 bugs de suture (tokenizer lhs_eff, split =, == non evaluable,
  mem.replace in-place = corruption tas). Credit : fix fns.getPtr
  (session MIR/QBE) inclus.
- d377a73 : STATUS guards ✅. 7be1b81 : tranchages comprehensions
  (ROADMAP, 5 decisions : syntaxe double, sequentiel, linear,
  SubstStream, Set-quotient).

### Conventions #17-#18
- #17 : std.mem.replace exige src != dest (in-place = UB,
  SIGSEGV differe DebugAllocator).
- #18 : ASCII seul (commands, patches, commits).

### File
- t_distrib ~2s (regression vivante, piste nodeHash)
- tco_deep ~40us/iter (trampoline)
- M4 Green/Fast (debloque depuis M3)
- Comprehensions : spec decidee, implementation a ouvrir

## Addendum -- forme alignee (2026-10-01 soir)
- 89ead1f : gardes en forme alignee (continuation '|').
- b26eb9f : fix use-after-free setLastEqLhs (bisection 867/89e).
  Lecon gravee : les tests d'une feature ne voient pas un UAF --
  seule la suite complete le detecte (convention #6).

## Correction interpretation (2026-10-02)
- Le "crash corruption tas" chase hier (bisection 867/89e) etait
  en fait le leak kernel au shutdown : gpa.deinit abort (exit 134)
  quand une preuve CIC passe par shift/mkApp. Stack : peano.zig
  104/123/372-388. Flaky (4/5). Dossier session kernel -- relais
  envoye avec reproducteur. Notre b26eb9f (fix UAF) reste valide
  pour ce qu'il corrigeait (ordre de liberation), mais la cause
  racine du 134 est le leak peano.

## Addendum -- perf t_distrib (2026-10-02)
- 9c90969 : rewriteViaPipeline convergence structurelle.
  t_distrib 1416ms -> 66ms (21x), saturations 20 -> 1.
  Cause : comparaison d'Id pour le point fixe -- or le pipeline
  re-alloue des Ids a chaque passage. LECON GENERALISABLE :
  jamais == sur Id comme critere de convergence dans un pipeline
  qui re-alloue -- toujours structuralEql. (Sweep fait : un seul
  site, celui-ci, corrige.)
- 08-proofs.md : rien a jour -- la perf ne change pas la
  semantique documentee. Si un chapitre perf nait un jour,
  y referencer les 21x.

---
## 📅 Journal : 02 Oct 2026
- **feat** : Parsing lambda `λ` 100% fiable (UTF-8, delim_pos, délégation parseSExpr).
- **feat** : Désucrage des compréhensions `(for ... (when ...))` opérationnel via `desugarFor`. Tests `comprehensions.hvn` validés.
- **fix** : Fuite de mémoire dans `eval.zig` colmatée (`defer free`).
- **fix** : Panic `Invalid free` à la fermeture du REPL dans `matrix.zig` résolu.
- **fix** : Règle de réécriture v2f `(add (succ x) y)` stabilisée.
- **Prochaines étapes candidates** : Spécification formelle EBNF, Support WASM IO, ou Pipeline logique unifié (rule/prolog).

## Addendum -- ordre superieur + comprehension (2026-10-02 PM)
- f8e9535 : 3 bugs racines. (1) symbole-fonction = valeur
  (le "application partielle" du 28/09 MORT -- test_stream 33/37).
  (2) defer env.delete premature x3 : thunk/t valeur differee
  -- filter-λ et le when en dependent. (3) comprehension phase A :
  desucrage TEXTE (for ...) -> map/filter, 10/12.
- OUVERT : parseOrDispatch/interpForAssert (parseur de TEST)
  ne connait pas λ S-expr -- 2 tests comprehension. Matrice
  complete en session : DS parfaits, chemins radiographies,
  reproducteurs /tmp/ds2.hvn /tmp/fl2.hvn.
- LECON #19 : le test-runner et le REPL ont des parseurs
  DIFFERENTS (interpForAssert vs parseExpression) -- une forme
  peut passer dans l'un et pas dans l'autre. Toujours sonder
  les deux.
