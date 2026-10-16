<!-- HEAVEN:platform-refactor-plan -->
# Refactor plateforme : x86_64_linux.zig → modules par préoccupation

## Objectif
Découper le fichier monolithique `src/platform/x86_64_linux.zig` (591 lignes,
8 préoccupations mélangées) en modules ciblés par OS/arch.

## Contrat public à NE PAS casser
29 symboles consommés par le reste du repo via `platform.X` :
allocator, ConsoleRawMode, dbg, debug, debug_enabled, disableRawMode,
enableRawMode, fs, getenv, initConsole, io, js_env, md, MultiParser, net,
posix, profiler, readEnergyUJ, readFileAllocCwd, readLine, readStdin, rtc,
setNonBlocking, ShellParser, shell_parser_types, spawnProcess, streamRead,
target, Thread, time.

Chaque commit du refactor doit préserver ces symboles à l'identique.

## Mapping cible → fichier
- Actuel : `src/platform/{arch}_{os}.zig` sans routage (build.zig:36-42).
- Commentaires build.zig:34-37 OBSOLÈTES — à corriger en fin de refactor.

## Étapes (1 commit par étape, build+test verts avant chaque)

| # | Étape | Gain estimé | Risque |
|---|-------|-------------|--------|
| 1 | Extraire `parser_ts.zig` (tree-sitter, ShellParser, MultiParser) | ~250 l. | Faible (isolé) |
| 2 | Extraire `webrtc.zig` (fusion `Network` + `webrtc.zig` existant) | ~90 l. | Moyen |
| 3 | Extraire `io_console.zig` (dbg, ConsoleRawMode, writeStdout, readStdin) | ~80 l. | Faible |
| 4 | Extraire `process.zig` (spawnProcess, ProcessResult) | ~15 l. | Faible |
| 5 | Extraire `time.zig` (time.*) | ~15 l. | Faible |
| 6 | Extraire `net_sockets.zig` (net.*, setNonBlocking) | ~190 l. | Moyen |
| 7 | Purger re-exports std (`platform.posix`, `platform.os`, `platform.Thread`, `platform.fs`, `platform.debug`, `platform.allocator`) → D-SH4 | — | Moyen |
| 8 | Nettoyer `engine_expr.zig` : `@import("builtin")` → `platform.target` | — | Faible |
| 9 | Corriger commentaires build.zig:34-37 + décider mapping explicite | — | Faible |

## Statut : TERMINÉ (2026-10-16, commit 4bb506b)

Bilan : `x86_64_linux.zig` **591 -> 113 lignes (-81%)**. 10 commits verts.

| Module créé | Lignes | Contenu |
|---|---|---|
| parser_ts.zig | 66 | tree-sitter cImport + 4 externs + ShellParser/MultiParser |
| io_console.zig | 87 | dbg, ConsoleRawMode, writeStdout, io.print, readLine |
| process.zig | 15 | spawnProcess + ProcessResult |
| time.zig | 17 | milli/nanoTimestamp + sleep |
| net_sockets.zig | 209 | struct net (16 syscalls Linux directs) + setNonBlocking |

Supprimés : `native.zig` (347 l. orphelin), `network.zig` (39 l. orphelin),
zone WebRTC morte (108 l.), re-exports std morts.

Reste dans `x86_64_linux.zig` : profiler switch, parser_ts re-exports,
net_sockets re-exports, Thread/fs/debug/posix/os/allocator (alias std,
purge = chantier D-SH4 séparé, ~500 sites), readFileAllocCwd/streamRead/
readEnergyUJ (wrappers triviaux, extraire couterait plus que ça ne retire).

## Chantier restant (non couvert par ce refactor)

1. **Remplir les stubs** : `aarch64_macos.zig` (73 l.), `wasm32_wasi.zig` (53 l.),
   `x86_64_windows.zig` (77 l.), `wasm32_freestanding.zig` (657 l., partiel).
   Bloquant pour la philosophie portable (WASI/POSIX/Windows).
2. **Purge alias std** (D-SH4 strict) : `platform.posix` (12 sites),
   `platform.Thread` (16), `platform.fs` (57), `platform.debug` (430),
   `platform.allocator` (11). Chantier multi-fichiers, pas un refactor plateforme.
3. **`engine_expr.zig`** : migré `builtin` -> `platform.target`. Vérifier qu'aucune
   autre fuite `builtin` n'apparaît dans `src/core/`.

## Règle absolue
`zig build -Doptimize=ReleaseFast` ET
`HEAVEN_NO_LEAK_CHECK=1 zig build -Dnetwork=false test-files`
doivent être VERTS avant chaque commit. Aucune exception.

## Chantier séparé (hors refactor)
- `test_bigint.hvn` quarantiné (215f4fc) — enquête isolation runner.
- `aarch64_macos.zig` (73 l.) : stub, à remplir.
- `wasm32_wasi.zig` (53 l.) : stub, à remplir.
- `x86_64_windows.zig` (77 l.) : stub, à remplir.
