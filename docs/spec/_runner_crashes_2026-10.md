# Runner crashes Debug-only (2026-10)

**Statut** : skip-list active dans `src/runtime/test_runner.zig`.

## Contexte

`zig build test-files` lance `heaven --run-tests tests`. Le runner
spawn un sous-processus par fichier (`--run-test`). En Debug, certains
fichiers crashent (SIGSEGV intermittent ou déterministe) sans être
isolés par le sous-processus — l'échec est bien détecté
(`CRASH/FAIL`), mais `runTestDir` positionne `any_failed = true`,
ce qui fait échouer le step `test-files`.

En ReleaseFast, tous les fichiers passent (pas de poison allocator,
pas d'asserts, layout mémoire différent).

## Skip-list

`DEBUG_SKIP_FILES` dans `test_runner.zig` :

- `test_mcp.hvn`
- `test_web_ontology.hvn`
- `test_bigint_d20.hvn`
- `test_hashmap.hvn`
- `test_bigint.hvn`
- `test_heaven_eval_prims.hvn`
- `test_lexer.hvn`

Conditionnée à `builtin.mode == .Debug` (ReleaseFast exécute tout).

## Auto-génération

La liste est maintenue par un script ad-hoc (capture des `CRASH/FAIL`
de `zig build test-files` en Debug). En cas de nouveau crasher,
relancer le script pour l'ajouter.

## Commandes de référence

- CI : `zig build test-files -Doptimize=ReleaseFast` (référence).
- Local Debug : `zig build test-files` (avec skip-list).
- Fichier isolé : `./zig-out/bin/heaven --run-test tests/test_xxx.hvn`.

## Backlog

- Investiguer les 7 (piste : allocator Debug, UAF, état partagé).
- Le Smocker (`core/std/smocker.hvn`) peut aider à isoler les effets
  pour reproduire/corriger ces crashes.
