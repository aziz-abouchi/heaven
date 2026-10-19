<!-- HEAVEN:http-fullstack-plan -->
# HTTP fullstack Heaven — remplace D9 (plan 2026-10-19)

## Décision

Remplacer D9 (découpler Vessel de Matrix) par : **stack HTTP
entièrement Heaven**, sans bridge.zig sur le chemin HTTP.

## Constat réel (vérifié 2026-10-19)

`_vessel_decouple.md` (inventaire D9) sous-estimé :
- 14/16 routes Vessel : aucune dépendance Astra.
- 2 routes couplées : /telemetry (Matrix + net2.known_peers) et
  LSP didSave (syncMatrixWithFile).
- `core/http_server.hvn` existe déjà : handle_request/handle_api
  (via @egraph_snapshot, magic Store, déjà Heaven).
- `bridge.zig` (474 l.) = couplage Matrix + net2 pour les 2 routes.

## 5 étapes

### E1 — telemetry_store (1-2h)
`src/vessel/telemetry_store.zig` : génère JSON depuis `expr.Store`
au lieu de `matrix`. Champs : node_count, symbol_count, nodes
(tag/payload/aux). Peers via `net2.known_peers` conservés.
Testable isolément.

### E2 — handleLsp didSave (1h)
`heavenIngestSource(path, source)` = `heaven.eval(source)` +
stats. Remplace `syncMatrixWithFile`. Le Store est peuplé par
l'éval, le dashboard lit le Store.

### E3 — Bascule bridge.zig (30 min)
`serveTelemetry` -> `telemetry_store`. `handleLsp` -> `heavenIngestSource`.
Supprimer `import matrix_lib`, `import autofab_lib` du bridge.

### E4 — Bascule main.zig (30 min)
`src/main.zig` appelle `http_serve` (core/http_server.hvn) au lieu
du bridge pour les 14 routes statiques + /api/egraph.

### E5 — Move Astra vers legacy (15 min)
`matrix.zig`, `matrix_bridge.zig`, `autofab.zig` -> `src/legacy/`.
D1 complète (Astra hors du chemin runtime).

## Effort total : 4-5h, 1 session longue.

## Ce qui ne change pas
- 14 routes statiques (IDE, REPL web, frames, assets).
- `@egraph_snapshot` (déjà Heaven).
- `bridge.zig` peut rester pour TCC/IDE hors HTTP.

## Dettes résiduelles
- LSP `didSave` : hors-scope (IDE couplé, à traiter séparément).
- `net2.known_peers` : conservé, couplage réseau Vessel/Scut.
