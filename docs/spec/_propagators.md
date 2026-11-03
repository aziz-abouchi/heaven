# Propagateurs et cellules — cadrage

**Date** : 2026-11-02
**Statut** : TODO explicite, aucun code. Session dédiée (~1-2 semaines).

## Objectif

Unifier les systèmes d'information partielle de Heaven (egraph, kanren,
ontologies, agrégats) sous un modèle unique : **cellules** (accumulateurs
de treillis) + **propagateurs** (machines sans état qui ajoutent de
l'information). Le modèle vient de Radul & Sussman (*A Generic
Propagation Architecture*, MIT 2009), vulgarisé par George Wilson
(*An Intuition for Propagators*, 2019).

## Principe

Une **cellule** est une relation unaire dont le contenu est un élément
d'un **join-semilattice** (merge commutatif, associatif, idempotent).
Un **propagateur** observe des cellules et en met à jour d'autres,
toujours en ajoutant de l'information (monotonie). Pas de message,
pas d'identité, pas d'ordre.

Le noyau Heaven (6 primitives : `sym`, `lit`, `bind`, `apply`,
`lambda`, `relation`) **suffit** — pas de 7ᵉ primitive. Le merge est
une relation binaire qui satisfait les lois (théorèmes par tests).
La notification est un propagateur = une `lambda` qui observe.

## Applications dans Heaven

| Système | Cellule | Merge (join-semilattice) | Propagateur |
|---|---|---|---|
| **Egraph** | e-class (ensemble d'e-nodes) | union (ensembliste) | rewrite rules |
| **Kanren** | variable logique (contrainte) | unification partielle | contraintes |
| **Prolog** | terme (substitution partielle) | unification | résolution SLD |
| **Ontologies** | sujet (ensemble de prédicats) | union de triples | règles RDF/OWL |
| **Agrégats** | clé de groupe (valeur) | fold/merge associatif | fold (group-by) |

Tous ces systèmes ont la **même structure** : information partielle +
merge monotone + propagation. Les cellules généralisent l'egraph et
kanren (déjà dans Heaven), et ouvrent la voie à Prolog et aux
ontologies déclaratives.

## Programmation courante

Au-delà des systèmes logiques, les cellules ouvrent un **style de
programmation** pour les développeurs Heaven finaux :

- **FRP/réactif** : une cellule = un signal, un propagateur = un
  consommateur. Merge = dernière valeur (ou ensemble de valeurs).
- **Contraintes** : une cellule = une variable, un propagateur = une
  règle (sudoku, planification, config).
- **Tableaux de bord** : une cellule = une métrique, merge = max
  (ou dernier), propagateur = mise à jour UI. Heaven a déjà
  `@runtime_stats`, c'est un cas particulier.
- **Configs** : une cellule = une clé, merge = override, propagateur
  = rechargement. Alternative aux variables d'environnement mutables.

Dans tous ces cas, **pas de message explicite** — l'information circule
par merge. C'est plus simple que les acteurs (OTP) pour les systèmes
où l'ordre n'importe pas.

## Lois (théorèmes par tests)

Une cellule `C` est valide si son merge `⊕` satisfait :

1. **Commutativité** : `a ⊕ b = b ⊕ a`
2. **Associativité** : `(a ⊕ b) ⊕ c = a ⊕ (b ⊕ c)`
3. **Idempotence** : `a ⊕ a = a`
4. **Monotonie** : si `a ⊑ b` alors `a ⊕ c ⊑ b ⊕ c` (où `⊑` est
   l'ordre induit par `⊕`)

Ces 4 lois sont testables par `quickcheck` (déjà 6 tests dans Heaven).
Un propagateur est valide s'il ne fait qu'**ajouter** de l'information
(pas de retrait, pas de mutation destructive).

## Implémentation prévue

**V0 (fait 2026-11-02)** : `lib/heaven_propagator.hvn` (26 l.)
+ `tests/test_propagator.hvn` (14/14). `cell`, `cell_merge` (max),
`propagate`, `propagate2`, `cell_le`. 4 lois testées. Commit `??`.
- Cellule = `relation` unaire (déjà primitive)
- Merge = `relation` binaire, lois testées par quickcheck
- Propagation = `lambda` qui observe + `apply`
- Test : egraph simple (5-10 nœuds, 3-4 rewrites) vs egraph actuel

**V1 (généralisation, 2-3 sessions)** :
- Kanren avec contraintes comme cellules
- Prolog minimal (unification = merge)
- Ontologies (triples + règles RDF)
- Agrégats (group-by = fold)

**V1.1 (fait 2026-11-03)** : `cell_merge_with` générique +
semilattices `min_int` et `or_bool`. 7 tests supplémentaires
(21/21 total).

**V1.2 (fait 2026-11-03, `e71851b`)** : `union_list` semilattice
(`nub (append a b)`) + `watch` (fold via `foldl`). 6 tests (27/27 total).
Import implicite `core/std/list.hvn` (`module List` non-préfixé).

**V2 (programmation courante, 1-2 sessions)** :
- API utilisateur : `cell`, `propagate`, `watch`
- Doc + exemples (FRP, contraintes, dashboards)
- Tests + bench

## TODO explicite

**Aucun code n'existe** pour les propagateurs généralisés. `_propagators.md`
est un document de cadrage. La feature est **phase 3+** (après selfhost
complet, WASM parité, bigint fix).

Prochaine étape concrète : **prototype V0** (2-3 sessions), quand le
selfhost est stable. Contournement actuel : egraph et kanren existent,
mais séparés (pas unifiés).

## Voir aussi

- `_inspirations.md` — Radul & Sussman, Wilson (à ajouter)
- `_hott_roadmap.md` — HIT (autre chantier phase 3)
- `docs/spec/_metacircularite_chantier.md` — selfhost
- Egraph existant : `src/inference/eqsat/egraph.zig`
- Kanren existant : `src/logic/kanren_expr.zig`
