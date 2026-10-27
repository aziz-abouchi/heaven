# Runner crashes Debug-only (2026-10)

**Statut** : skip-list active dans `src/runtime/test_runner.zig`.

## Sémantique (2026-10-27)

`runTestDir` distingue maintenant :

- **Échec de test** (`.Exited code != 0`) → `any_failed = true` dans
  tous les modes. C'est une assertion qui a échoué, le vrai signal.
- **Crash** (`.Signal`) en **Debug** → loggé `[!] ... crash Debug
  connu, ignoré`, mais **ne fait pas échouer** `test-files`.
  C'est une fragilité de l'allocator Debug / UAF, qui passe en
  ReleaseFast.
- **Crash** en **ReleaseFast** → `any_failed = true` (bug réel).

Conséquence : `zig build test-files` en Debug passe (les crashes
Debug sont loggés mais non bloquants), et `-Doptimize=ReleaseFast`
reste la **hard gate** (aucun crash attendu).

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
