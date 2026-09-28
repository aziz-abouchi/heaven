# Décisions d'architecture Heaven

Document de référence pour les choix structurants.
Chaque décision est ancrée sur un constat de code (chiffres,
chemins, lignes). Une décision non appliquée reste **proposée**.

Dernière mise à jour : 2026-09-28.

## Contexte chiffré

- **54 258 lignes de Zig** dans `src/` (~180 fichiers)
- **~16 000 lignes vivantes** : `core/expr.zig`, `engine_expr.zig`,
  `heaven_expr.zig`, `expr_parser.zig`, `kernel/peano.zig`,
  `elab.zig`, `proof_core.zig`, `tactics.zig`, `eqsat/egraph.zig`,
  `logic/kanren.zig`, `platform/*`
- **~20 000 lignes dormantes/orphelines** : ancien écosystème
  Astra (`matrix.zig`, `matrix_bridge.zig`, `vessel/*`,
  `runtime/heaven.zig`, `runtime/eQSATPlanner.zig`,
  `scut/*`, `inference/forge/*`, `inference/neural/*`)
- **21 TODO/FIXME**, **19 `@panic`/`unreachable`**

## D1 — Faire le deuil d'Astra

**Constat** : ~20k lignes de code d'un langage parallèle
(`matrix.Matrix`, `SRG`, `eQSATPlanner`, `AutoFab`) qui n'a
jamais convergé vers le noyau 6 primitives. Le vrai Heaven
utilise `expr.Store` + `engine_expr`, pas `matrix`.

**Action** : déplacer vers `src/legacy/`. Vérifier qu'aucun
fichier vivant n'en dépend (audit préalable).

**Effort** : 1 session.

**Critère** : `zig build test` et `zig build test-regression`
restent verts. `main.zig` n'importe plus `matrix_lib`,
`vessel_lib`, `heaven_lib`, `transpiler_lib`, `universal_lib`,
`autofab_lib`, `react_lib`, `dispatch`, `SRG`, `EQSATPlanner`.

## D2 — Un seul miniKanren

**Constat** : 3 implémentations coexistent :
- `core/kanren_expr.zig` (188 l., Store-based, utilisé par
  `fact`/`query`)
- `logic/kanren.zig` (969 l., Term-based, utilisé par le shell)
- `runtime/prolog.zig` (308 l.)

**Recommandation** : garder `core/kanren_expr.zig` (Univers A),
migrer `logic/kanren.zig` vers Store-based, supprimer
`prolog.zig`. Clarifier les rôles dans `_tooling.md`.

**Effort** : 2-3 sessions.

## D3 — Un seul CIC

**Constat** : après le merge `core/kernel.zig` → `kernel/peano.zig`,
il reste `elab.zig` (1678 l.), `proof.zig`, `proof_core.zig` (598 l.),
`proof_helpers.zig`, `proof_state.zig`. Responsabilités qui se
chevauchent.

**Action** : clarifier qui fait quoi. Documenter dans
`docs/spec/_kernel.md`. Fusion ou façade claire.

**Effort** : 1 session d'audit + 1 session de refactor.

## D4 — Découper le shell

**Constat** : `core/commands.zig` (2338 l.) + `runtime/shell/commands.zig`
(1604 l.) = **3942 lignes** pour un shell.

**Action** : séparer par domaine dans `core/commands/` :
- `commands/logic.zig` (fact, query, rule)
- `commands/proofs.zig` (theorem, prove, skill)
- `commands/cas.zig` (simplify, derive, integrate, solve)
- `commands/modules.zig` (module, import, export)
- `commands/actors.zig` (spawn, send, state)
- `commands/meta.zig` (rules, help, stats)

**Effort** : 2 sessions.

## D5 — Un seul `NodeKind`

**Constat** : `NodeKind` est défini 5 fois :
`platform/shell_parser_types.zig`, `inference/forge/ts_normalize.zig`,
`parsing/shell_parser.zig`, `core/bridge.zig`, `translator/mlcpd.zig`.
Aucun n'est `Tag`. Vestiges de l'univers tree-sitter.

**Action** : si tree-sitter est gardé pour `fmt`/`lsp`/`doc`,
un seul `NodeKind` partagé. Sinon, supprimer avec D1.

**Effort** : 1 session (après D1).

## D6 — Nettoyer `main.zig`

**Constat** : lignes 22-36 de `main.zig` importent 15 modules,
dont la moitié ne devrait plus être là après D1.

**Action** : après D1, ne garder que les imports du noyau vivant.
Le shell devient un module unique `shell_mod`.

**Effort** : 1 session après D1.

## D7 — Sérialisation canonique du Core

**Constat** : ~6 TODO de `core/network/swarm.zig`,
`core/network/handlers.zig`, `codegen_wrapper.zig` demandent un
format d'échange binaire pour le Core. Absent.

**Action** : `core/serialize.zig` :
- `encode(store: *Store, id: Id, writer: anytype) !void`
- `decode(reader: anytype, allocator) !Id`
- Format versionné : `magic = "HVNv1"`, refus des versions inconnues.
- Test d'inverse : `decode(encode(e)) == e` (α-équivalence).

**Effort** : 2-3 sessions.

**Débloque** : cache disque, communication entre process,
tests reproductibles, IPFS (si un jour).

## Roadmap courte (7 sessions)

| # | Session | Débloque |
|---|---|---|
| 1 | Fix `parseExpression` (infix parenthésé) | P0 stabilité |
| 2 | D1 — déplacer Astra vers `src/legacy/` | 20k lignes clarifiées |
| 3 | D7 — sérialisation Core | prérequis réseau/cache |
| 4 | D4 — découper `commands.zig` | shell maintenable |
| 5 | D2 — unifier miniKanren | logique clarifiée |
| 6 | D3 — clarifier CIC/elab/proof_core | noyau clarifié |
| 7 | Scoped syntax `bracket`/`local`/`catch` | effets scopés réels |

## Ce qu'on ne fera pas (vision, hors scope)

- IPFS / IPLD : présuppose sérialisation + réseau + swarm
- Swarm distribué (Fed-LBAP, MinCost, stragglers thermiques) : rien dans le code
- QTT avec budgets temps/énergie : la QTT actuelle est multiplicité
- Couplage thermique runtime : lecture température = 30 min Linux, mais
  corréler avec scheduler = projet
- Brain cognitif complet : `inference/neural/synthesis.zig` expérimental
- Auto-hébergement total : jalon, pas tâche

Ces sujets vivent dans `docs/VISION.md` (à créer), pas dans la roadmap.

## Règle de méthode

Avant toute décision structurante :
1. **Lire le code concerné** (pas de patch à l'aveugle)
2. **Vérifier les chiffres** (grep, wc, tests)
3. **Documenter le constat** (citations, chemins, lignes)
4. **Proposer l'action** avec effort et critère

Les rapports LLM (IPFS, λ_sc, ontologies) sont utiles pour la
direction mais doivent être **vérifiés ligne par ligne** avant
d'être planifiés. Plusieurs prêtaient au code des propriétés
qu'il n'a pas (sérialisable, distribué, typé).
