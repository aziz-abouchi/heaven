# wasm32-wasi : ecart avec la cible reelle

**Date** : 2026-10-15
**Statut** : identifie, non implemente. Session dediee requise.

## Etat actuel

- src/platform/wasm32_wasi.zig : stub 53 lignes.
- Ne fonctionne PAS avec wasmtime/wasmer : les syscalls WASI
  ne sont pas appeles.

## Objectif

Compilation cross-cible wasm32-wasi fonctionnelle :
- Tests via wasmtime/wasmer.
- API WASI preview1 (fd_write, path_open, clock_time_get,
  sock_accept si supporte).

## Plan

1. Auditer le stub wasm32_wasi.zig actuel.
2. Lier les vraies API WASI (std.os.wasi).
3. Tester avec wasmtime.
4. Separer proprement freestanding (JS host) vs wasi (WASI
   runtime) : meme wasm_entry.zig, platform substitue.

## Effort

1 session. Priorite basse : freestanding (JS) couvre le besoin
web actuel.

## Voir

- docs/spec/_wasm_targets.md : distinction freestanding/wasi.
