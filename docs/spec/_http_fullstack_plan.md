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

---

## Etat 2026-10-19

- **E1** : DONE. `src/vessel/telemetry_store.zig` livre, cable au CI
  (`test_telemetry_store`). Commit `e65dc66`.
- **E2** : DONE (implicite). Le helper `heavenIngestSource` n'a pas
  ete extrait en fonction nommee : le pattern est repris inline
  dans E3b (read + splitStatements + heaven.eval loop). Refactor
  eventuel si E4 le reutilise.
- **E3a** : DONE. `serveTelemetry -> telemetry_store.render`, store
  plombe `WebBridge.store: *expr.Store`. Commit `0bdc6e9`.
- **E3b** : DONE. `didSave -> Heaven.eval` (read + split + eval
  loop). `WebBridge.heaven: *Heaven` remplace `.store`. Accesseur
  `Heaven.getStore()`, `splitStatements` passe pub.
  `syncMatrixWithFile` (stub) n'est plus appele par bridge.
  Commit `00e1475`.
- **E3c** : DONE. Dedup `heaven_expr`/`heaven_expr_mod`, retire
  `main_mod` orphelin de bridge. Commit `584e5e2`.
- **E4** : TODO. Reestimation : **1-2 sessions de conception**, pas
  "30 min". Blocages identifies :
  1. `stdlib/net/http.hvn` n'a pas de serveur (0 match `serve|
     listen|accept|recv`). Il faut un `http_serve` en `.hvn`.
  2. JSON-RPC en `.hvn` : objets maintenant OK (H1/H2 clos), mais
     ni `encode_jsonrpc` ni `decode_jsonrpc` n'existent.
  3. `@embedFile` n'existe pas en `.hvn`. Decision a poser : soit
     statiques en Zig (seul `/api/*` porte en `.hvn`), soit
     `fs.read_file` + manifest.
  Voir `_vessel_decouple.md` pour le decoupage E4a/E4b.
- **E5** : TODO. matrix/autofab/matrix_bridge -> `src/legacy/`.
  6 usages residuels de `self.matrix` dans `bridge.zig` (`/graph`,
  `/rules`, `/bob`...). Apres E4.

