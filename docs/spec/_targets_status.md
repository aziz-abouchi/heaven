# Cibles de compilation : etat reel

**Date** : 2026-10-15
**Statut** : audit. Cross-compilation non garantie.

## Cibles fonctionnelles

| Cible | Commande | Test |
|---|---|---|
| x86_64-linux | `zig build` | ✅ tout |
| wasm32-freestanding | `zig build -Dtarget=wasm32-freestanding` | ✅ build + REPL |

## Cibles en cours

| Cible | Erreur principale | Fix requis |
|---|---|---|
| wasm32-wasi | 22 err (stub pauvre) | Session dediee |
| aarch64-linux | aarch64_linux.zig absent | 1h : stub |
| x86-linux | x86_linux.zig absent | 1h : stub |
| aarch64-macos | platform.debug_enabled absent | 30 min |
| x86_64-windows | platform.debug_enabled absent | 30 min |
| aarch64-windows | aarch64_windows.zig absent | 1h |
| x86_64-macos | TCC config.h | Session dediee (TCC) |
| aarch64-ios | Guix libc + tree-sitter | Hors scope V0 |
| aarch64-android | zig 0.15.2 ne supporte pas | Hors scope |

## Pattern

`build.zig` ligne 35 : auto-derive `<arch>_<os>.zig`.
Realite : la plupart de ces fichiers n'existent pas. Pas de fallback.

## Plan

1. Spec (ce document).
2. Fix `platform.debug_enabled` pour tous les stubs (aarch64_macos, x86_64_windows).
3. Creer des stubs pour les cibles Linux/Windows secondaires.
4. wasm32-wasi : session dediee (voir _wasi_gap.md).
5. macOS/Windows x86_64 : tests reels impossibles sans machine.

## Decision

Cross-compilation = confort, pas priorite V0.
x86_64-linux + wasm32-freestanding couvrent le besoin reel.
Les autres cibles sont documentees mais pas supportees.

## Selfhost natif (mise à jour 2026-10-30 soir)

`heaven compile-qbe bin/heaven.hvn -o bin/heaven-natif` produit un
ELF x86_64 fonctionnel. Validé :

    ./bin/heaven-natif version   # exit 1
    ./bin/heaven-natif help      # exit 2
    ./bin/heaven-natif foo       # exit 0

ABI SysV : `argc` en `%edi`, `argv` en `%rsi`, retour dans `%eax`
(glibc lit `eax & 0xFFFFFFFF`).

| Cible | État selfhost |
|---|---|
| x86_64-linux (QBE) | OK (ELF, strings, puts, argv, dispatch) |
| wasm32-wasi (build) | OK (armPreemptTimer stub), runtime à valider |
| wasm32-freestanding | OK (REPL navigateur) |
| Windows / kernel32 | stubs incomplets |
| macOS / libc | TCC config partielle |

Voir `docs/book/src/39-selfhosting.md`.

## WASM selfhost (mise à jour 2026-10-30 nuit)

`heaven compile-wasm` compile désormais `main = 42` et `main = (+ 1 2)`
en `.wat` exécutable :

    ./zig-out/bin/heaven compile-wasm /tmp/t.hvn -o /tmp/t.wat
    wat2wasm --enable-tail-call /tmp/t.wat -o /tmp/t.wasm
    node -e "...WebAssembly.instantiate... main() ..."

| Cible | État selfhost |
|---|---|
| x86_64-linux (QBE) | OK (ELF, strings, puts, argv, dispatch) |
| wasm32-freestanding (WAT) | OK (main=42, (+ 1 2)) |
| wasm32-wasi (build) | OK (armPreemptTimer), runtime à valider |
| Windows / kernel32 | stubs incomplets |
| macOS / libc | TCC config partielle |

**Limitations WASM** : `@puts` → `unreachable` (extern_call non
implémenté), pas de data segments (const_str), pas de WASI imports
(`fd_write`, `args_get`). Parité QBE = 1-2 sessions (WASI).

Note env : `wasmtime` cassé (`libgcc_s.so.1` not found) sur ce
système ; utiliser `wat2wasm` + `node` comme fallback.

Voir `docs/book/src/40-heaven-eval.md` et ch. 35 backend-wasm.
