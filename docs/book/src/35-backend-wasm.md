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

## Ce qui échoue (par conception, 2026-11-12)

**Rejet à la compilation** (`error.UnsupportedCall`, cf.
`MIR_CONTRACT.md` §6 et §8, restauré par `31b5ba1`) :

- Appel à une `fn` utilisateur non précompilée : multi-clause,
  garde, ou pattern non-symbole (cf. `precompileUserFns`, `b2e6564`).
- Appel à un symbole inconnu (ni builtin natif, ni `fn` utilisateur,
  ni `@xxx` externe) à 2 arguments → `error.UnsupportedOp`
  (cf. `compileExpr.apply`, `mir.zig`).

**Ne se rejettent pas, mais échouent en aval** :

- `@xxx` (externe) → `extern_call` émis. QBE tente le link
  (libc) ; WAT émet `unreachable` → trap à l'exécution, pas
  rejet à la compilation.
- `(choose 1)` → `UnsupportedExpr` (pipeline WAT incomplet, à
  vérifier sur le commit courant).
- Entry `_start` WASI absente (freestanding).

## Travaux restants (v0.2)

1. `fn` utilisateur multi-clause / patterns / gardes : exclues de
   `fn_defs` par `precompileUserFns` (`b2e6564`). Support complet =
   arbre de décision sur constructeurs / littéraux / gardes
   (cf. A2, estimation 3-6 sessions).
2. `@xxx` en WASM : brancher WASI (`fd_write` pour `@printf`/`@puts`,
   table d'imports pour le reste). Aujourd'hui `unreachable`
   (trap runtime).
3. Primitives présentes dans `Engine.eval` mais absentes de
   `compileExpr.apply` : `%`, `and`/`or`, `band`/`bor`/`shl`/`shr`/
   `>>>`, `!`/`neq`, `seq`/`block`/`let`/`tuple`, `string_*`. Aucun
   arm natif à ajouter sans vérifier la précédence avec les
   `FunctionDef` du même nom dans `core/bootstrap.hvn`
   (cf. `add`, `mul`).
4. Entry `_start` WASI + heap WASM (memory.grow, load/store) +
   strings/bytes.

Prérequis commun à (1)–(4) : split `mir.zig` (45 min) — le fichier
mélange IR, précompilation, fusion SCC, migration str_pool.

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
