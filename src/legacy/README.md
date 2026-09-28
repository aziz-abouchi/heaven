# src/legacy/ — Ancien écosystème Astra

Ce dossier contient le code dormant d'un langage parallèle
(`matrix.Matrix`, `SRG`, `eQSATPlanner`, `AutoFab`, `Vessel/*`,
`Scut/*`, `inference/forge/*`, `inference/neural/*`) qui n'a
jamais convergé vers le noyau 6 primitives de Heaven.

**Règle** : aucun fichier vivant (`main.zig`, `core/expr.zig`,
`engine_expr.zig`, `heaven_expr.zig`, `kernel/peano.zig`,
`platform/*`, `runtime/swarm/runtime.zig`, `runtime/actor/*`)
ne doit importer d'ici.

Si vous avez besoin de piocher dans un de ces modules, c'est
probablement que vous voulez réécrire la fonctionnalité dans
`core/` ou `runtime/` — pas ressusciter l'ancien monde.

## Distinction importante

- `runtime/swarm/runtime.zig` : **VIVANT** (importé par main.zig,
  shell/init.zig, scut/network.zig, vessel/bridge.zig).
- `core/network/swarm.zig` (déplacé ici) : **dormant**, à ne pas
  confondre avec le runtime swarm.

## Contenu

59 fichiers, ~3200 lignes. Voir `docs/DECISIONS.md` section D1.
