# Cibles WebAssembly : freestanding vs wasi

**Date** : 2026-10-15
**Statut** : analyse. Implementation en cours.

## Deux cibles, deux modeles

| Cible | Provider | Modele |
|---|---|---|
| wasm32-freestanding | **JS host** (HTML5 + bindings) | POSIX emule via `extern fn js_*` |
| wasm32-wasi | **WASI** runtime | syscalls WASI (preview1/2) |

Le code source est identique. Seul le fichier platform differe :

    src/platform/native.zig            -- natif (Linux, macOS, Windows)
    src/platform/wasm32_freestanding.zig -- navigateur/Node via JS
    src/platform/wasm32_wasi.zig       -- WASI (wasmtime, wasmer, node --experimental-wasi)

## wasm32-freestanding

**Principe** : toutes les operations OS sont des `extern fn` que le
JS host fournit. Le host est un fichier `heaven.js` charge par la
page HTML (ou Node).

    extern fn js_fs_read(path_ptr: [*]const u8, path_len: usize, out: [*]u8, max: usize) i32;
    extern fn js_fs_write(path_ptr: [*]const u8, path_len: usize, data: [*]const u8, len: usize) i32;
    extern fn js_net_listen(port: u16) i32;
    extern fn js_now_ns() i64;
    extern fn js_console_log(ptr: [*]const u8, len: usize) void;

Le host JS utilise :
- `fetch` pour HTTP sortant
- `WebSocket` / `WebRTC` pour la comm
- `localStorage` / `IndexedDB` pour la persistence
- `performance.now()` pour le temps
- `console.log` pour la sortie

## wasm32-wasi

**Principe** : WASI fournit les syscalls standard (fd_read, fd_write,
path_open, clock_time_get, sock_accept, etc.). Le code compile contre
les headers WASI et lie les imports `wasi_snapshot_preview1.*`.

    const wasi = @import("std").os.wasi;
    const fd = try wasi.fd_write(1, &iov, 1);

Cibles : wasmtime, wasmer, wasmedge, node --experimental-wasi.

## Etat actuel (2026-10-15)

- wasm32-freestanding : stub minimal pour compiler. Les `js_*`
  sont declares en stub no-op. Le JS host reel n'existe pas encore.
- wasm32-wasi : stub cree (a completer).
- Le natif fonctionne pleinement.

## Plan

1. Spec (ce document).
2. wasm32-freestanding : remplacer les no-op par de vraies
   declarations extern, creer `src/vessel/public/heaven_host.js`.
3. wasm32-wasi : completer le stub avec les vraies appels WASI.
4. Tests d'integration : REPL web, evaluation d'un `.hvn` simple
   dans le navigateur.

## Hors scope

- wasm64 (memoire > 4 GB) : pas necessaire V0.
- WASI preview 3 : pas encore standardise.
- Threads wasm (SharedArrayBuffer) : chantier separe.

## Ecart stub Zig vs JS host (2026-10-15)

Le stub `wasm32_freestanding.zig` compile (exit=0) mais utilise des
**no-op internes** au lieu de vraies `extern fn`. Le JS host existe
(`heaven_host.js`, `wasm-core.js`).

### Ce que le JS host fournit deja

| Import JS | Stub Zig actuel |
|---|---|
| js_console_log | no-op |
| js_console_error | absent |
| js_performance_now | absent (time.timestampMs retourne 0) |
| js_websocket_connect | absent |
| js_websocket_send | absent |

### Ce qu'il faut aligner

1. Declarer les vraies `extern fn` dans le stub Zig.
2. Wrapper dans `js_env` (meme nom, meme signature).
3. Completer le JS host pour les manquants (fs, net, message queue).
4. Tests : REPL web doit fonctionner (charger wasm, eval simple).

### Dette

- fs : pas d'interface JS (localStorage/IndexedDB a brancher).
- net : WebSocket partiel, manque WebRTC.
- message queue : stub, pas de vrai routage.
- time : js_performance_now non branche.
