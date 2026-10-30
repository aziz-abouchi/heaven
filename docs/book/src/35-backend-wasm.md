# Backend WASM — État partiel

> `compile-wasm` émet du `.wat`, converti via `wat2wasm`, exécuté
> via `wasmtime`.

## Pipeline

    Source.hvn → parse → Core AST
      → lowerRec → MIR → compileExpr
      → mir_wat.emitWat → .wat
      → wat2wasm → .wasm
      → wasmtime → exécution

## Ce qui marche (v0.1-partial, 2026-10-30)

- `mir_wat.zig` émet le WAT pour arith / if / fns user
- Heap → `unreachable` trap (au lieu d'erreur bloquante)

## Ce qui échoue

- `(+ 1 2)` → `UnsupportedCall` (checkCallUsers sans stubs)
- `(choose 1)` → `UnsupportedExpr` (pipeline WAT incomplet)
- Entry `_start` WASI absente (freestanding)

## 3-4 sessions nécessaires

1. Skip `checkCallUsers` en warn + stubs
2. Entry `_start` WASI + fd_write pour printf
3. Heap WASM (memory.grow, load/store WASI)
4. Strings/bytes + tests

Prérequis : split `mir.zig` (45 min).

## Fichiers WASI existants

`src/vessel/wasi_main.zig` (2.9 KB) et `src/vessel/wasm_entry.zig`
(41 KB), à brancher en session future.

## Mise à jour 2026-10-30 — WASI build débloqué

Tag `wasm-wasi-v1`. Stub `armPreemptTimer` ajouté dans
`src/platform/wasm32_wasi.zig` :

    pub fn armPreemptTimer(_: ?*const fn (i32) callconv(.c) void) void {}

Résultat : `zig build -Dtarget=wasm32-wasi` passe (binaire produit).
Reste à valider côté runtime (wasmtime, WASI preview1).

Voir aussi [ch. 39 selfhosting](39-selfhosting.md) — WASM selfhost
(`mir_wat`) reste à faire (TODO, 1h).
