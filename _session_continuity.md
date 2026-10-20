# HEAVEN — Prompt de continuité (2026-10-20, après recon R1-R9)

## Rôle
Agent expert Zig/Heaven. Scripts shell/python copier-collables.
L'utilisateur exécute et colle les sorties. Adapte selon ce que tu vois.

## Méthodologie (héritée, toujours valide)
1. Blocs courts : shell < 20L, python < 40L. Heredoc `python3 - <<'PYPATCH'`
   préféré à `cat > file`.
2. Chaque bloc vérifiable : grep, wc -l, `echo "EXIT=${PIPESTATUS[0]}"`
   (jamais `$?` après pipe).
3. Backups `.bak` avant modif. `cp -n` pour idempotence.
4. Cutoff dur : si un fix échoue au 1er build, rollback + doc + pause.
   Pas de 3ᵉ tentative.
5. Baseline avant commit (si .zig touché) :
   - `zig build -Doptimize=ReleaseFast` = 0
   - `zig build test` = 0
   - `HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests` fails=0
   - wasm32-freestanding + wasm32-wasi = 0
6. `--run-test` (singulier) fork par fichier, capture le Total.
   `--run-tests tests` global, timeout 30s possible (baseline via per-file).

## Style Heaven (infixe obligatoire)
- `a + b` (pas `(+ a b)`), `if p then a else b`, `let x = v in body`.
- `f = 42` est une fonction, PAS une valeur. `f _ = 42` puis `f 0 == 42`.
- **Dans `test "nom":`, le parser cherche `==` à profondeur 0.** Tout
  `let ... in` doit être dans un helper HORS test.
- Escape `\xNN`, `\"` non supportés (workaround poke_byte).

## Pièges confirmés
- Regex multi-ligne casse les corps indentés → remove_def par blocs.
- Double import direct+transitif silencieusement KO (fossile #4) —
  workaround `b1adff3` (retire le chemin), vraie correction non-commitée
  (patch `import.zig` re-préfixe sous-imports).
- `engine_expr.zig:1052-1060` : `evalMagic` est fonction libre (`engine`, pas `self`).
- `heaven_expr.zig` = parser (fields `Heaven`), `engine_expr.zig` = magics
  (fields `Engine`). Les deux ont un `fn_arities`.

## État réel (vérifié R1-R9, 2026-10-20)

**Vert / fonctionnel** :
- HKT V1a : 2/2 (`test_hkt_v1a`)
- HKT V1b : 25/25 (step1 4/4, step2 11/11, step3 10/10) — dispatch livré
- Lens/optics : 12/12 (`stdlib/optics.hvn` canon, `core/std/lens.hvn` v0 fossile)
- Effects : commit `e445f5d` (facade .hvn + resume + tests)
- MPST : 10+3 runtime (`stdlib/mpst.hvn`)
- Fantasy Land : 13/13, Free monad : 6/6, MaybeT : 6/6

**Partiel / non branché** :
- QTT : `linear`/`erased`/`many` parsés, check parse `expr_parser.zig:742`
  **ne fire PAS sur `heaven run`**, `LinearChecker` (`types.zig:145`) mort
  sauf `hasErrors` appelé par `src/runtime/shell/commands.zig:917`.
  → Chantier Phase 2 RFC v2 : brancher, 1 session.
- `examples/vision/` : 14-16L/fichier, esquisse multi-OS (`linear`,
  `inline_qbe`, `module`, `arena`, `memory`). Parser accepte `linear`,
  sémantique absente. À rapatrier `stdlib/platform/`.

**Dette** :
- 3 arbres `.hvn` : `core/` (mort, 0 import tests), `site/repl/core/`
  (copie publiée 35/37 identiques, 2 divergents `bigint`, `http_server`),
  `stdlib/`+`lib/` (vrais arbres actifs, 12+7 imports).
- 10 `.bak` récursifs (voir `find . -name '*.bak'`).
- 57 fichiers `tests/scratch/`.
- `stdlib/` : 2 `.bak` (`dns.hvn.local.bak`, `string.hvn.d2.bak`).
- Pas de tests `.hvn` end-to-end QTT.
- Bug runner : `helper _ = ...` dans test → `Total 1/2` silencieux
  (1 passed + 1 failed invisible, sans message).

## Chantiers actifs (par priorité, après patch docs)

1. **QTT Phase 2** (1 session, `.zig`) : brancher `expr_parser.zig:742`
   sur `heaven run`, ajouter 4-6 tests `.hvn` explicites, décider si
   `types.zig` `LinearChecker` est mort ou à rebrancher.
2. **Fix runner `helper` dans test** (0.5 session) : `Total 1/2` sur
   fichier 1-test = bug scope, à tracer dans `test_runner.zig`.
3. **Plateforme `examples/vision/` → `stdlib/platform/`** (1-2 sessions,
   `.hvn` + FFI Zig) : HKT V1b débloque `class Allocator a`.
4. **Stratification `stdlib/`** (1 session, shell) : `data/`, `net/`,
   `core/`, `io/`, `platform/`. Après Phase 2/3 pour ne pas perturber.
5. **Fossile #4 vraie correction** : patch `import.zig` non-commité
   (re-préfixe sous-imports), baseline complet à faire, 4-5 blocs.

## Ordre de lecture au démarrage
1. `_stdlib_v2_plan.md` (97L, plan complet)
2. `docs/STATUS.md` (474L, journal)
3. `docs/STDLIB.md` (308L+, sections à jour)
4. Ce fichier

## Contraintes de communication
- Signaler tunnel > 3 blocs sur un diagnostic. Proposer rollback + doc.
- Ne pas prétendre faisable si session de conception. Dire « 2 sessions ».
- Demander la sortie après CHAQUE bloc, ne pas supposer.
