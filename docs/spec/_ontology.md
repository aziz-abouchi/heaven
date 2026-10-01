# Ontologie Heaven - perimetre, frontiere, decisions

> Statut : **decide**. Les cinq questions sont tranchees (2026-10-01).
> `src/core/ontology.zig` existe desormais comme squelette (Phase 2).
> Les Phases 3 (SMT-LIB) et 4 (MPST labels) sont planifiees mais pas
> commencees.

## Contexte

Deux fichiers distincts, deux roles :

| Fichier | Role | Representation |
|---|---|---|
| `src/core/algo_catalog.zig` | Catalogue d'algorithmes, complexite, choix contextuel | strings |
| `src/core/ontology.zig` | Concepts sur le Core IR, trust, provenance | `Id` (a terme) |

`algo_catalog.zig` est l'ancien `ontology.zig` renomme
(commit `c651fa9`). Il reste un composant a cote du Core, sans
pretention semantique.

## Decisions actees

### 1. Nom

`algo_catalog.zig` pour le catalogue d'algorithmes.
`ontology.zig` reserve pour le niveau **High-Level Semantic IR**
decrit dans `docs/core/core-ir.md` section 18.

### 2. Frontiere avec le Core

L'ontologie **manipule des `Id`** (pas des strings). Elle vit
au-dessus du Core, dans le niveau `High-Level Semantic IR`. Les
noms (`[]const u8`) restent presents pour l'affichage, mais
l'identite semantique passe par `Id`.

Consequence : a terme, `Concept.expr_id` pointera vers un noeud
reel du Store, et `isA` sera verifiable par `structuralEql`.

### 3. Sources externes - SMT-LIB en premier

Ordre d'integration :

1. **SMT-LIB** (Phase 3) - format standard, parseur facile,
   oracle disponible (Z3, cvc5). Emission : `Heaven -> .smt2`.
   Import : axiomes `(assert ...)` comme concepts `asserted`.
2. OWL / RDF / SPARQL - plus tard, quand un cas d'usage le
   demandera.
3. Lean / Rocq - oracles seulement (LSP), pas d'import semantique.
4. MLCPD - tooling, pas runtime.

### 4. Trust et provenance - maintenant

Trois niveaux :

- **`asserted`** - vient d'une source externe non verifiee
  (DBpedia, fichier SMT-LIB, saisie utilisateur)
- **`derived`** - derive par une regle interne valide
  (subsomption, reecriture)
- **`certified`** - prouve par `proof_core.zig`

Chaque concept et chaque relation porte une `Provenance` :
- `source` : `user | smt_lib | owl | lean | rocq | mpst | internal`
- `source_id` : identifiant optionnel (URI, nom de fichier,
  numero de ligne SMT-LIB)
- `timestamp` : secondes Unix

Une relation `equivalent-to` **asserted** reste un candidat, pas
un theoreme. La preuve se fait ailleurs (`proof_core`).

### 5. Relation avec MPST

L'ontologie **alimente les labels de session**. Concretement :

- Un concept peut etre utilise comme role dans un type global.
- Une relation `produces`/`consumes` decrit un flux de messages.
- Les `TrustLevel` s'appliquent aux labels : un role `asserted`
  peut etre verifie plus strictement qu'un role `certified`.

Phase 4 : integration dans `elab.zig` et `mpst.zig`. Pas
commencee.

## Ce que le squelette actuel ne fait pas

`src/core/ontology.zig` (Phase 2) contient :
- `TrustLevel`, `SourceKind`, `Provenance`
- `Concept`, `Relation`, `RelationKind`
- `Ontology` avec `addConcept`, `addRelation`, `isA`, `filterByTrust`
- 3 tests

Il ne contient **pas** :
- de projection vers/depuis `expr.Store` (Phase 3)
- d'emission SMT-LIB (Phase 3)
- de lien avec `mpst.zig` (Phase 4)
- de commandes REPL

Le fichier n'est **pas branche** dans `build.zig` ni importe par
`main.zig`. Il est testable isolement via `zig test
src/core/ontology.zig`. C'est volontaire : on construit la
fondation avant de la cabler.

## Feuille de route

| Phase | Contenu | Statut |
|---|---|---|
| 1 | Renommer `ontology.zig` en `algo_catalog.zig` | fait (`c651fa9`) |
| 2 | Creer `src/core/ontology.zig` (squelette) | ce commit |
| 3 | Emission SMT-LIB + oracle Z3/cvc5 | planifie |
| 4 | Alimenter les labels MPST depuis l'ontologie | planifie |
