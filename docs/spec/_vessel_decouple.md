# Decouplage Vessel du noyau Astra (D9)

> Statut : **inventaire** (2026-10-02). Ce document recense ce qui
> depend vraiment de `matrix` dans le bridge Vessel. L'implementation
> reste a faire.

## Contexte

`DECISIONS.md` D9 annoncait 1-2 sessions. L'inventaire du
2026-10-02 corrige l'estimation : c'est **2-4 heures**, parce que
sur 16 routes HTTP du bridge, seules 2 touchent vraiment `matrix`.

Vessel est l'environnement web de Heaven (IDE, REPL web,
visualisateur eGraph, process monitor). Il porte une grande partie
de l'experience utilisateur. Ne pas casser.

## Inventaire des routes

`src/vessel/bridge.zig` (474 lignes) expose 16 routes GET.

### Routes statiques (14 routes, aucune dependance Astra)

Elles servent des fichiers via `@embedFile` ou en clair :

- `GET /` ou inconnu -> `index.html`
- `GET /repl`, `/dashboard`, `/ide`, `/docs`, `/test` -> HTML
- `GET /common.css`, `/wasm-core.js`, `/test_heaven.js` -> assets
- `GET /editor-frame.html`, `/repl-frame.html`,
  `/debugger-frame.html`, `/process-frame.html` -> frames iframe
- `GET /heaven.wasm` -> binaire WASM du compilateur
- `GET /test_suite.hvn` -> suite de tests

**Ces routes n'ont aucun lien avec Astra.** Elles peuvent rester
telles quelles.

### Route dynamique : /telemetry (1 route, depend de matrix)

`serveTelemetry` (lignes 42-200 de `bridge.zig`) produit du JSON
pour le dashboard. Il lit :

- `matrix.getStats()` -> `node_count`, `symbol_count`
- `matrix.nodes.iterator()` -> parcourt et filtre les Edge,
  Rule, Fact, Bob (acteurs), swarm tasks

Les concepts Astra utilises :
- `Edge` : arete typée entre nœuds
- `Rule` : regle de reecriture
- `Fact` : fait (kb)
- `Bob` (acteur) avec `state` et `handler`


### Route LSP : didSave (1 route, depend de matrix)

`handleLsp` sur `textDocument/didSave` appelle :

    main_mod.syncMatrixWithFile(matrix, fab, allocator, path)

C'est l'unique point d'ingestion continue : quand VSCode/Codium
sauve un fichier `.hvn`, Vessel le lit et le fait ingerer dans la
matrix (via UniversalIngestor). Affiche ensuite `MATRIX UPDATED:
N nodes, M symbols`.

Ce chemin est **important** : c'est ce qui rend le dashboard
"vivant" pendant l'edition.

## Ce qu'il faudrait pour découpler

### Pour /telemetry

Créer un `Telemetry` générateur qui lit `expr.Store` au lieu de
`matrix`. Trois champs :

1. `node_count` : `store.nodes.items.len`
2. `symbol_count` : `store.interner.list.items.len`
3. `nodes` : itération sur `store.nodes` exposant `tag`, `payload`,
   `aux` par nœud

L'information est disponible mais moins riche : la matrix exposait
des **concepts typés** (Edge, Rule, Fact, Bob). Le Store expose des
**nœuds bruts** (6 primitives). Il faudra dériver les concepts par
filtrage de tags :
- `Edge` -> `apply(sym("edge"), ...)` ou similaire
- `Rule` -> `relation(...)`
- `Fact` -> présence dans le KB kanren
- `Bob` -> `spawn` / acteurs dans `engine.actors`

**Effort** : 1-2h.

### Pour handleLsp didSave

Remplacer `syncMatrixWithFile(matrix, fab, ...)` par un appel à
`heaven.eval(source)`, qui peuple `store`, `engine.fns`, etc. Le
dashboard lit alors le Store au lieu de la matrix.

**Effort** : 1h.

## Estimation révisée

| Endpoint | Effort |
|---|---|
| /telemetry (basculer sur Store) | 1-2h |
| handleLsp didSave (basculer sur heaven.eval) | 1h |
| Supprimer l'import matrix_lib/autofab_lib du bridge | 15 min |
| Tester Vessel fonctionne toujours (dashboard, LSP) | 30 min |

**Total : 3-4 heures**, pas 1-2 sessions. Une session courte suffit.

## Ce qui disparaît après

Une fois `/telemetry` et `handleLsp` recablés :

- Le bridge Vessel n'importe plus `matrix_lib` ni `autofab_lib`.
- `universal.zig` (UniversalIngestor) n'est plus appelé que par
  `main.zig` pour le bootstrap.
- `matrix.zig`, `matrix_bridge.zig`, `autofab.zig` deviennent
  **réellement morts** (hors tests) et peuvent être déplacés vers
  `src/legacy/`.

## Ce qui ne change pas

- Les 14 routes statiques : inchangées.
- L'IDE, le REPL web, le visualisateur eGraph : fonctionnent pareil.
- Le test `test_suite.hvn` : inchangé.

## Ordre d'implémentation

1. Créer `src/vessel/telemetry_store.zig` : génère le JSON depuis
   `expr.Store` (testable isolément).
2. Basculer `serveTelemetry` sur ce module.
3. Créer un helper `heavenIngestSource(path, source)` qui appelle
   `heaven.eval` et renvoie les stats.
4. Basculer `handleLsp` sur ce helper.
5. Supprimer les imports matrix/autofab du bridge.
6. Tester : dashboard affiche des données, LSP didSave met à jour.
7. Move Astra vers `src/legacy/` (D1 enfin complete).
