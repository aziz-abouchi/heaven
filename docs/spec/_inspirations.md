# Inspirations externes -- coffre

> Statut : index de veille. Ce document enregistre les inspirations
> exterieures examinees et la decision prise a leur sujet.
>
> Reference : docs/ARCHITECTURAL_DISCIPLINE.md (regle d'or et
> gouvernance).

## Regle

Une inspiration n'entre dans l'architecture que si elle resout un
probleme identifie, que ses prerequis sont disponibles, que son
cout est acceptable, et qu'une decision explicite l'introduit.

Sinon, elle reste ici, avec un trigger de reouverture verifiable.

## Decisions actees

Ces inspirations ont ete examinees et ecartees dans leur forme
actuelle. Aucune n'est "reportee" : elles sont rejetees.

| Inspiration | Decision | Raison |
|---|---|---|
| Pony -- reference capabilities | Ne pas integrer | QTT couvre la multiplicite |
| Roc -- modele Task | Ne pas copier | Modele historique, Roc a change |
| Flix -- Datalog integre | Ne pas elargir | Pertinent pour Knowledge, non prioritaire |
| Linear logic | Cadre theorique | Fondement possible de QTT + MPST, pas une couche |
| Sessions-as-effects | Cadre de conception | Utilise pour concevoir MPST + effects + QTT, pas un sous-systeme |
| Hare -- philosophie | Rejetee | Trop eloignee, aucun apport architectural |
| V (vlang) | Rejetee | Promesses non tenues, pas de lecon structurelle |

## Adoptions actées

Ces inspirations ont été examinées et **introduites** dans l'architecture,
avec trigger et effort.

| Inspiration | Décision | Raison | Livrable |
|---|---|---|---|
| Radul & Sussman — propagation architecture (cellules + propagateurs) | Adopter | Unifie egraph + kanren + ontologies sous un modèle monotone. Pas de 7e primitive (pair + lambda suffisent). | `_propagators.md` V0 (2026-11-02) |

### Radul & Sussman — A Generic Propagation Architecture

**Décision.** Adopté. V0 (`lib/heaven_propagator.hvn`, 14/14 tests)
livre cellules + merge + propagation. V1.1 (2026-11-03) ajoute
`cell_merge_with` générique + semilattices `min`/`or`.

**Trigger de vérification.** Les 4 lois (commutativité, associativité,
idempotence, monotonie) doivent être testées sur chaque semilattice
avant extension (kanren, prolog, ontologies). V1.2 : union ensembliste
+ `watch` (fold) — reportés faute de lib listes/fold.

**Effort.** V0 fait. V1.1 fait. V1.2 : 1 session. V2 : 1-2 sessions.

**Voir aussi.** `docs/spec/_propagators.md`, `lib/heaven_propagator.hvn`,
`tests/test_propagator.hvn`.

---

## Coffre -- reports avec trigger

Chaque entree porte : pourquoi pas maintenant, trigger verifiable,
effort estime.

### Koka -- Perceus / reuse analysis

**Pourquoi pas maintenant.** Perceus necessite un pipeline compile
fiable sur 100% des cas. QBE/WASM n'a pas atteint ce niveau de
stabilite. Un bug dans l'analyse de reutilisation produit un UAF
silencieux.

**Trigger.** Pipeline QBE/WASM avec zero regression sur 1 mois.

**Effort.** 3-4 sessions.

### BEAM -- reductions + dirty schedulers

**Pourquoi pas maintenant.** Le scheduler preemptif depend de D8
(continuations delimitees). Sans capture/reprise exacte, il n'y a
pas de preemption reelle.

**Trigger.** D8 termine (3a-3 branche + tests end-to-end verts).

**Effort.** 2-3 sessions.

### CRDT -- convergence Knowledge distribue

**Pourquoi pas maintenant.** CRDT necessite un systeme distribue
en production. Heaven n'a aujourd'hui aucun reseau actif (WebRTC
stubbed).

**Trigger.** Premier reseau fonctionnel (deux noeuds qui echangent
du code ContentId).

**Effort.** 2-3 sessions apres la fondation distribuee.

### Unison -- content addressing

**Pourquoi pas maintenant.** Necessite une forme canonique des
termes, qui n'existe pas encore. Avec CIC et types dependants,
la canonicalisation depend de l'egalite definitionnelle, qui est
indecidable en general.

**Trigger.** Forme canonique du Core Expr decidee (spec + prototype).

**Effort.** 2-3 sessions (canonical form + hash + cache).

Note : Unison est deja partiellement en place via le hash-consing
du Store. Ce qui manque, c'est un ContentId stable et exportable.

### Maty -- MPST + acteurs + effects

**Pourquoi pas maintenant.** Maty combine trois systemes que
Heaven a separement (MPST, actors, effects). L'integration suppose
que chacun soit stabilise. Aujourd'hui : MPST est un fichier
dormant, les acteurs sont caller-driven, les effets sont one-slot.

**Trigger.** Un des trois piliers atteint un etat stable
(probablement les effets apres D8).

**Effort.** 4-6 sessions apres D8.

### Koka / Unison -- yield comme effet

**Pourquoi pas maintenant.** Convergence entre Generator, Stream,
Channel, comprehension, async autour d'un meme mecanisme d'effets.
Necessite D8.

**Trigger.** D8 + un premier cas d'usage concret (stream effectful
qui doit suspendre).

**Effort.** 1-2 sessions apres D8.

### Process mining -- extraction de motifs

**Pourquoi pas maintenant.** Aucune trace d'execution structuree
n'existe. Le profiler mesure, mais n'extrait pas de motifs.

**Trigger.** Infrastructure de traces persistantes.

**Effort.** A definir apres la trace.

## Inspirations sans suite

Ces idees ont ete mentionnees mais ne justifient pas une entree
dans le coffre.

- **Idris, Agda** : deja dans la lignee directe de Heaven (types
  dependants). Pas une inspiration externe, une filiation.
- **Lean 4, Coq/Rocq** : oracles externes, pas une source
  architecturale. Voir `docs/spec/_ontology.md` pour le pont.
- **Erlang/OTP** : inspiration pour les acteurs (deja en place).
  La partie supervision est couverte par le coffre BEAM.
- **Datalog, Prolog, miniKanren** : deja integres sous une forme
  ou une autre. Pas d'ajout.
- **MLIR** : reference de complexite, pas une source d'architecture.

## Gouvernance

Voir `docs/ARCHITECTURAL_DISCIPLINE.md`.

Une entree sort du coffre uniquement si :
1. son trigger est atteint (verifiable),
2. un cas concret dans le code justifie la reouverture,
3. une ADR est ecrite,
4. la decision est prise dans un commit dedie.


## Propagateurs et cellules (Radul & Sussman, Wilson)

**Examiné** 2026-11-02. **Décision : coffre, trigger = selfhost stable.**

- **Alexey Radul & Gerald Sussman**, *A Generic Propagation Architecture*
  (MIT, 2009). Modèle : cellules (join-semilattice) + propagateurs
  (machines sans état, monotones). Merge commutatif, associatif,
  idempotent. Unification comme merge de cellules.
- **George Wilson**, *An Intuition for Propagators* (Compose Melbourne,
  2019). Vulgarisation. Exemple conversion Fahrenheit/Celsius
  bidirectionnelle.
- **Edward Kmett**, `ekmett/propagators` (Haskell). Implémentation
  de référence.

**Pertinence** : généralise egraph (déjà en place) et kanren (déjà en
place) sous un modèle unique. Ouvre Prolog, ontologies déclaratives,
agrégats. Style de programmation pour les développeurs Heaven finaux
(FRP, contraintes, dashboards, configs).

**Pourquoi pas maintenant** : phase 3+, après selfhost complet, WASM
parité, bigint fix. Aucun code existant n'utilise les cellules
généralisées. Prototype V0 (2-3 sessions) planifié dans
`docs/spec/_propagators.md`.

**Trigger de réouverture** : selfhost V1 stable (bin/heaven.hvn
compile `heaven_eval.hvn` + tests verts) ET WASM parité QBE
(`@puts`, `@argv`, `@strcmp` en WASM).
