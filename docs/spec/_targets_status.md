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
