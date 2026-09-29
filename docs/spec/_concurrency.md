# Concurrence Heaven — conception

**Date** : 2026-09-29
**Statut** : analyse + questions ouvertes. Aucune implémentation.
**But** : figer la cible, poser les décisions, définir les prototypes.

## Constat

Heaven doit couvrir plusieurs modèles de programmation concurrente :

- Data parallelism (CPU/GPU)
- Streams (pipelines, I/O, événements)
- Actors (état isolé, messages)
- Relations (recherche parallèle, backtracking)
- Tasks/futures (concurrence structurée)
- Reactive (propagation de changements)
- Distributed (essaim)
- Supervision (résilience)

**Ces modèles ne doivent pas devenir 8 systèmes indépendants.**

## Hiérarchie

PROGRAMMATION    actors / reactive / async
    ↓
COMMUNICATION    channels / mailboxes / streams
    ↓
CONCURRENCY      fibers / coroutines / tasks / continuations
    ↓
SCHEDULING       workers / work-stealing / priorities
    ↓
EXECUTION        OS threads / WASM / CPU / GPU / peer

## Distinctions fondamentales

**Fiber** ≠ **Coroutine** ≠ **Generator** ≠ **Stream**

| Concept      | Définition                                 |
|--------------|--------------------------------------------|
| Fiber        | Unité d'exécution légère avec sa pile      |
| Coroutine    | Calcul suspendable (`resume`/`yield`)      |
| Generator    | Producteur de valeurs (`yield T`)          |
| Stream       | Abstraction de séquence (0..n valeurs)     |

## Noyau proposé — 5 primitives

Tout le reste (actor, channel, task, stream, future) doit émerger de :

| Primitive | Type                                | Rôle                    |
|-----------|-------------------------------------|-------------------------|
| `spawn`   | `(computation) → ProcessId`         | Créer un process        |
| `send`    | `(ProcessId, Message) → Unit`       | Envoyer à une mailbox   |
| `recv`    | `(ProcessId) → Message`             | Lire sa mailbox         |
| `yield`   | `() → Unit`                         | Suspendre le process    |
| `self`    | `→ ProcessId`                       | Identité                |

Dérivés :
- `Actor` = process + send/recv + état isolé + comportement
- `Channel` = send/recv + file + backpressure
- `Task` = spawn + send + await (recv résultat)
- `Stream<T>` = handler de l'effet `Yield<T>`
- `Future<T>` = process + send résultat
- `Supervisor` = process qui reçoit les crash events

**Zéro nouvelle primitive dans le noyau CIC** — ce sont des effets
algébriques, cohérents avec `perform`/`handle` existants.

## Le process Heaven

Heaven Process
 ├── état d'exécution (continuation/stack)
 ├── mailbox
 ├── process id (PID)
 ├── capabilities
 └── scheduling metadata

**Pas** : Heaven process = OS thread.

Des milliers/millions de processes multiplexés sur quelques workers OS.

## PID et distribution

PID = <NodeId, ProcessId, Generation>

`send(pid, msg)` est agnostique de la localité :
- même worker
- autre CPU
- autre nœud
- autre continent

Le runtime résout.

## Préemption

**Trois options** :

1. Safepoints instrumentés par le compilateur (5-15 % de surcoût)
2. Signaux + timer (fragile, spécifique plateforme)
3. Coopératif (yield, recv, allocations)

**État actuel** : `engine_expr.zig` a un `engine.fuel` (réduction
budget). En interprété, la préemption est déjà possible. En natif,
elle n'existe pas.

## Décisions à trancher (C1-C5)

### C1 — Stackful vs stackless

| Option             | Mémoire/process | Préemption  | WASM    |
|--------------------|-----------------|-------------|---------|
| Stackful (BEAM, Go)| 2-8 KB          | Triviale    | ❌      |
| Stackless (Rust, JS)| ~100 B         | Impossible  | ✅      |
| Hybride            | Variable        | Double code | Partiel |

**Recommandation** : stackless partout. Accepte la complexité async
coloring, gagne la portabilité WASM et le million de processes.

### C2 — Migration : gestion des Id

`Id` dans `expr.zig` est un `u32` index local dans `Store.nodes`.
Migration d'un process entre nœuds ⇒ les `Id` deviennent invalides.

| Option                       | Coût                    |
|------------------------------|-------------------------|
| Re-sérialiser tout le Store  | ×1000 mémoire           |
| IDs content-addressed        | Refonte `Store`         |
| Store distribué lazy         | Complexité énorme       |

**Aucune option triviale.** À trancher **avant** toute migration.

### C3 — Préemption native

- Reduction budget (en interprété : ✅ déjà là)
- Safepoints (en natif : coûteux mais faisable)
- Coopératif seulement (simple, bloque sur CPU-bound)

**Recommandation** : reduction budget en interprété (existant),
safepoints en natif (session dédiée), ne pas tenter signaux.

### C4 — Modèle de faute

| Modèle              | Exemple       | Discipline             |
|---------------------|---------------|------------------------|
| BEAM (supervisors)  | Erlang        | Let-it-crash           |
| Structured          | Trio, Kotlin  | Scopes, pas de dangling|

**Recommandation** : structured concurrency. Cohérent avec QTT et
le zéro GC.

### C5 — Relation/search vs tasks

Le miniKanren fait déjà de l'`interleave` — c'est un scheduler.

| Option                    | Conséquence                    |
|---------------------------|--------------------------------|
| Unifier avec scheduler    | Problème de recherche (dur)    |
| Sous-scheduler dédié      | Exception au principe "1 seul" |
| Paralléliser branches top | Limité mais faisable           |

**Recommandation** : sous-scheduler dédié pour la logique. C'est
l'exception assumée au principe.

## Scheduler

Heaven Scheduler
 ├── Run Queue par worker
 ├── Work stealing
 └── Politiques : affinité, priorité, QTT, effets, énergie, thermique

**Contrainte architecturale** : aucun modèle de haut niveau ne doit
avoir son propre scheduler. Actor/coroutine/task/stream/relation sont
des modes d'usage du **même** scheduler.

## QTT et concurrence

QTT est **statique** (0/1/ω). Utile pour :
- Ownership (qui possède une tâche)
- Duplication (stream `1` vs `ω`)

**Pas** pour :
- Budget énergétique
- Migration
- Priorité

Ces derniers relèvent du **cost model runtime**, pas du type system.
À nommer séparément.

## Plan prototype

### Prototype 1 (1 session) — Modèle local minimal

- `spawn`, `send`, `recv` comme effets sur `perform`/`handle`
- Pas de préemption native
- Pas de migration
- Pas de distribution
- Objectif : valider que le modèle composable fonctionne

### Prototype 2 (2-3 sessions) — Scheduler + Yield

- Ajouter `yield` + scheduler à réduction budget
- 3-4 processes concurrents interprétés
- Comparer avec `runtime/actor/` existant
- Objectif : mesurer la surcharge du scheduler

### Prototype 3 (session dédiée) — Trancher C1

- Choisir stackful vs stackless
- Implémenter le scheduler qui va avec
- Objectif : premier benchmark million-process

## Découvertes — Prototype 1 (2026-09-29)

### Découverte 1 — QTT `linear` trop strict pour un handle concurrent

Un `ProcessId` est utilisé **deux fois** dans un cycle typique :
une fois pour `tell`, une fois pour `recv`. `let linear p = ...`
refuse (violation). Contournement actuel : `let many p = ...` dans
les tests.

**Conséquence pour Prototype 2+** : il faudra trancher une
multiplicité adaptée :
- `many` par défaut pour les ProcessId (simple, mais perd la
  discipline)
- nouvelle multiplicité (`linear-write`, `shared-read`...) — cohérent
  avec Rust (`self` vs `&mut self`)
- `tell` consomme, `recv` renvoie un nouveau handle (`linear` strict)

**À trancher avant le scheduler.**

### Découverte 2 — `spawn` ignore ses arguments

Signature actuelle : `spawn(handler, init_state)`. Les deux arguments
sont évalués puis **jetés**. Le process créé est une mailbox nue.

**Trois options pour Prototype 2** :
- **A** : `spawn(fn, init)` réveille le handler à chaque message
  (sémantique BEAM)
- **B** : `spawn()` 0 args, mailbox pure (état actuel)
- **C** : les deux, avec `spawn` vs `spawn_actor`

**Recommandation** : garder B pour Prototype 2 (le scheduler n'a pas
besoin de sémantique acteur), puis A pour Prototype 3.

## Prototype 2 — Scheduler + Yield (plan)

**Objectif** : valider que plusieurs processes peuvent se coordonner
sans bloquer le thread principal.

**Cible** :
- `yield()` : suspend le process courant, cède la main
- Scheduler à réduction budget : quand `engine.fuel` atteint 0,
  le process est suspendu et un autre prend la main
- Test : 3 processes qui s'envoient des messages en boucle

**Hors-scope** :
- Pas de préemption native
- Pas de threads OS
- Pas de distribution

## Ce qui existe déjà dans le code

- `runtime/actor/` — acteurs locaux (mailbox, lifecycle, registry)
- `engine_expr.zig::fuel` — réduction budget
- `logic/kanren.zig::Stream::interleave` — scheduler miniKanren
- `runtime/swarm/runtime.zig` — squelettes distribués
- `runtime/scheduling` — ébauches

**À réutiliser**, pas réinventer.

## Ne pas faire

- Migration distribuée avant Prototype 3
- Préemption native avant C3 tranché
- WebRTC/peer avant Prototype 2 vert
- Un scheduler par paradigme
- Confondre QTT (statique) et budget (runtime)

## Le vrai danger

Vouloir tout implémenter. Finir avec 30 000 lignes de Zig, aucun cas
d'usage validé. La discipline D1-D7 s'applique ici : 5 primitives,
prototype local, tests, puis élargir.
