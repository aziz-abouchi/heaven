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

## WIP externe (NE PAS TOUCHER)
- src/core/heaven_expr.zig + engine_expr.zig + parse.zig : feature
  "guards" (autre session). ~88 l. de diff non commitees.
  BUGBLOQUANT chez eux : heaven_expr.zig:516 a
  `self.engine.fns.functions.getPtr` au lieu de
  `self.engine.fns.getPtr` (fns est deja la map). Corrige
  localement, pas commit.
- tests/guards.hvn : leur test (untracked).
- src/core/parse.zig, src/runtime/shell/commands_test.zig :
  modifies non commites.
- core/std/*.hvn, core/test_suite.hvn, src/vessel/public/*.hvn :
  WIP, ne pas toucher.

## Pistes pour la prochaine session

### Fait cette session (2026-10-01)
- TCO WASM/QBE : les self-tail-calls sont transformes en boucle dans
  `mir_qbe.zig` et `mir_wat.zig`. `count_down 10000000` compile et
  tourne. Le flag `-W max-wasm-stack=67108864` n'est plus requis.
- bench-wasm fib verifie : median 6.75 ms sur 5 runs, pas de timeout.
  Le timeout initial venait de la pile native non bornee.
- _bench.md complete avec les chiffres fib (interp / QBE / WASM).
- Fix RAPL : `scripts/setup-rapl.sh` adaptatif (Guix / NixOS /
  generique). Rend la lecture d'energy_uj permanente sans sudo.

### Restant
1. TCO etendue QBE/WASM : **fait** (`e6a31ff`).
   - WASM : `return_call` natif. isEven 100000000 = 1.
   - QBE : fusion SCC MIR pour les paires mutuellement recursives.
     isEven 100000000 = 1.
   - Non couvert : cycles de 3+ fonctions, trampolines generaux.
   - Spec : docs/spec/_tco_mutual.md.
2. wasm32-wasi (A : compilateur en WASI ; B : programmes compiles
   en WASI). Priorite basse. Voir docs/spec/_wasm_targets.md.
3. Cross-compilation vers d'autres arches / OS (QBE deja multi-cible
   x86-64/ARM64/RISC-V, a brancher dans build.zig et tester).
4. Auto-hebergement (long terme) : BigInt (libtommath), I/O,
   structures de donnees, puis self-parse/self-compile.

## Bug connexe observe (2026-10-01)

Au shutdown du REPL apres avoir charge deux fonctions mutuellement
recursives (ex. `isEven`/`isOdd`), un `Invalid free` se declenche
dans `src/core/matrix.zig:237` (`free(func.params)`). C'est un bug
**independant** de la TCO, probablement lie a D1 (deplacer
l'ecosysteme Astra vers `src/legacy/`). A traiter separement.

Voir `docs/spec/_tco_mutual.md` (section "Probleme connexe").

## Leaks residuels identifies (2026-10-01)

Deux leaks preexistants, non urgents, visibles dans le rapport debug.

### L1 - proofs.zig:222 (evalTheorem)

`cmds.allocator.dupe(u8, msg)` cree une string retournee a
l'appelant (`commands.zig:580` -> `heaven_expr.zig:2353`), qui ne la
libere jamais. Se declenche a chaque `theorem t : ...`.

### L2 - interactive.zig:146 (readLine dans runProofInteractive)

La `tactic_line` n'est pas liberee sur les chemins `abort` ou `EOF`.
Fix trivial mais a verifier que `applyLine` ne retient pas `trimmed`.

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
