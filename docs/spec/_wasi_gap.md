# wasm32-wasi : etat et ecarts restants

**Mis a jour** : 2026-11-20
**Statut** : `src/platform/wasm32_wasi.zig` implemente les appels WASI preview1 (`fd_write`, `fd_read`, `path_open`, `clock_time_get`, `random_get`), `mir_wat.zig` emet la memoire lineaire `(memory (export "memory") 1)` avec `$heap_ptr` aligne 8 octets et `memory.grow`, et `heaven-wasi` s'execute sous `wasmtime` (expression directe, `--fuel`, `--eval-file` avec `--dir .`) sans fuite GPA.

## Etat actuel

- `src/platform/wasm32_wasi.zig` : appels WASI preview1 actifs ; `zig build -Dtarget=wasm32-wasi` compile proprement.
- `src/vessel/wasi_main.zig` : supporte l'expression directe, `--fuel <n>` et `--eval-file <path>` avec liberation propre de `Heaven` via `Heaven.deinit()`.
- `src/backend/mir_wat.zig` : tas lineaire + croissance `memory.grow` en place ; `call_user` hors `fn_defs` rejette explicitement (`error.UnsupportedCall`) et `.extern_call` emet `unreachable`.

## Ecarts restants

- Integrer une verification E2E `heaven-wasi` automatisee dans le workflow de build (`zig build test-wasi-e2e`).
- Connecter les appels externes / `fd_write` directement dans l'emission `mir_wat` plutot que d'emettre `unreachable` sur `.extern_call`.
- Maintenir la separation nette entre `wasm32-freestanding` (hote JS) et `wasm32-wasi` (runtime WASI).

## Voir

- `docs/spec/_wasm_targets.md` : distinction freestanding/wasi.
- `docs/spec/_runtime_gaps.md` : journal des ecarts runtime et MIR.
