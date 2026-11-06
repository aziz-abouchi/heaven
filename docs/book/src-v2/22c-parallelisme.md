# Chapitre 22c — Parallélisme : la route vers le multi-cœur

> **Version 2 (2026-11-04)** — from scratch (roadmap, pas tutoriel).
> Source : `_parallelism_roadmap.md` (5 niveaux), `_concurrency.md` C1-C5.
> **État V0** : niveau 0 (mono-thread). Aucun code parallèle en V0.
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Il y a une différence entre avoir un marteau et avoir une
> usine. »*
> — Proverbe d'atelier

Le chapitre 21a a montré la **concurrence coopérative**. Le 21b a
ajouté la **préemption**. Tu peux maintenant gérer mille tâches qui
s'entrelacent fair-play.

Mais il y a un mot qu'on n'a **pas** encore prononcé : **parallélisme**.
Et c'est un mot différent.

## 1. Concurrence ≠ parallélisme

**Concurrence** : *plusieurs choses à faire en même temps*, sur une
seule ressource. Le scheduler alterne — chaque tâche a l'illusion
d'avancer, mais une seule s'exécute à un instant donné.

**Parallélisme** : *plusieurs choses s'exécutent simultanément*, sur
plusieurs ressources (cœurs, machines). Deux threads qui tournent
vraiment en même temps.

Le tableau :

| | Concurrence | Parallélisme |
|---|---|---|
| Ressources | 1 cœur | N cœurs |
| Bénéfice | réactivité | **vitesse** (N×) |
| Risque | famine, deadlock | race conditions, mémoire partagée |
| Heaven V0 | ✅ (21a/21b) | ❌ (roadmap) |

**Ce que tu as dans Heaven aujourd'hui** : la concurrence complète.
**Ce que tu n'as pas** : le parallélisme. Un programme Heaven V0
utilise **un seul cœur**, même si tu en as 16.

## 2. Les cinq niveaux

Le fichier `_parallelism_roadmap.md` décrit **5 niveaux**, inspirés
de BEAM/Erlang. On les parcourt du plus simple au plus ambitieux.

### Niveau 0 — actuel : 1 thread + scheduler préemptif

C'est où on est. Un thread OS, N tâches Heaven. Le scheduler
coopératif/préemptif (21a/21b) alterne entre elles. **Zéro
parallélisme** — juste l'illusion du concurrent.

### Niveau 1 — pool de threads + work-stealing (~2-3 sessions)

**L'idée** : lancer K threads OS (K = nombre de cœurs). Chaque thread
a sa propre file de tâches. Quand un thread finit sa file, il **vole**
une tâche à un autre (work-stealing).

**Ce que ça débloque** : K× speedup sur les tâches pures.

**Ce que ça coûte** :
- Synchronisation des files (atomiques)
- Migration d'état (`Id` non partagés entre threads → `Option D` lazy copy, `_concurrency.md` C2)
- Debug multi-thread (race conditions possibles dans le runtime)
- WASM interdit (`std.Thread` incompatible avec `wasm32-freestanding`)

### Niveau 2 — parallélisme de données (~1 session)

**L'idée** : opérations « map » et « fold » sur des collections
parallélisables. `(map f xs)` sur 1M éléments → découpé en K chunks,
traités en parallèle.

**Ce que ça débloque** : accélération des traitements de masse (RDF,
egraph, ML).

**Ce que ça coûte** : un contrat utilisateur (« ces opérations sont
parallèles, ces autres non »), et un runtime qui sait découper.

### Niveau 3 — pipeline

**L'idée** : composition `Producer | Transformer | Consumer`. Chaque
étage tourne sur un thread dédié, les données circulent par canal.

**Ce que ça débloque** : streaming haut débit (serveur HTTP, I/O).

**Ce que ça coûte** : gestion des canaux, du backpressure, des
fermetures.

### Niveau 4 — distribué (2+ sessions)

**L'idée** : N **machines**, pas N cœurs. Chaque nœud Heaven parle à
ses voisins par le réseau. Erlang fait ça depuis 1986.

**Ce que ça débloque** : scalabilité horizontale (1000 nœuds).

**Ce que ça coûte** : la migration d'`Id` (`_concurrency.md` C2,
Option D tranchée), la tolérance aux partitions, la supervision
distribuée.

## 3. Où en est Heaven (2026-11)

Heaven est au **niveau 0**. C'est un choix assumé.

Le projet vise d'abord la **correction** (preuves, types dépendants,
HoTT) avant la **performance**. Un langage prouvé qui tourne sur 1
cœur vaut mieux qu'un langage rapide qui plante.

Mais le multi-cœur est **planifié**. L'ordre recommandé
(`_parallelism_roadmap.md`) :

1. **Niveau 1** d'abord (pool de threads + work-stealing) — c'est le
   fondement. Sans ça, les niveaux 2-4 sont instables.
2. **Niveau 2** ensuite (parallélisme de données) — le plus gros gain
   utilisateur pour l'effort.
3. **Niveau 3** (pipeline) — après stabilisation.
4. **Niveau 4** (distribué) — chantier long, à réserver pour après
   l'auto-hébergement.

## Piège — « ça marche » ≠ « ça scale »

Le piège classique, c'est de croire que parce qu'un programme
concurrent **fonctionne** sur 1 cœur, il **fonctionnera** sur 16.

C'est faux. Trois raisons :

1. **Race conditions** : deux tâches accèdent à la même donnée sans
   synchronisation. Sur 1 cœur, l'ordre est déterministe (scheduler).
   Sur 16 cœurs, non. Un bug invisible devient visible 1 fois sur
   10 000.
2. **Faux partage** : deux threads écrivent dans des cases proches de
   la même ligne de cache. Le CPU invalide la ligne en permanence.
   Performance divisée par 10, pas par 1.
3. **Sérialisation** : si toutes les tâches prennent le **même**
   verrou, elles se bloquent mutuellement. Aucun speedup, pire même
   (coût du verrou).

**Ce que ça implique** : passer au niveau 1 n'est **pas** juste
« lancer K threads ». C'est repenser le runtime pour que la mémoire
soit **partitionnée** (chaque thread ses données) ou **partagée
explicitement** (RwLock, atomiques). Sinon on perd le gain.

**Cas vécu (autre langage)** : Python a le GIL (Global Interpreter
Lock) qui empêche deux threads d'exécuter du bytecode simultanément.
Le parallélisme Python est une **illusion** — les threads aident pour
l'I/O, pas pour le CPU. Heaven devra éviter ce piège en partitionnant
dès le départ (c'est l'objet de `Option D`, `_concurrency.md` C2).

## Sous le capot — pourquoi `std.Thread` est interdit en WASM

`src/core/heaven_expr.zig:7` :

    /// std.posix/std.Thread — interdits sur wasm32-freestanding. 2026-10-27 (E4).

En WASM (navigateur, freestanding), il n'y a **pas** de threads OS
natifs. La spec WASM a des **Web Workers** (threads isolés) et des
**SharedArrayBuffer** (mémoire partagée), mais :

- **Pas de threads OS** : pas de `pthread_create`.
- **Pas de `std.Thread`** dans Zig pour `wasm32-freestanding`.
- **SharedArrayBuffer** nécessite des en-têtes COOP/COEP côté serveur
  (isolation cross-origin), compliqué.

**Conséquence** : le niveau 0 (mono-thread) est **obligatoire** en
WASM. Les niveaux 1-4 sont **natifs seulement** (Linux, macOS,
Windows). C'est une contrainte de la plateforme, pas un choix de
Heaven.

**Ce que ça implique pour le design** : le runtime doit être
**portable** — la version WASM fait tout en mono-thread, la version
native peut utiliser les threads. Le code utilisateur ne doit **pas**
savoir sur quelle plateforme il tourne (sauf pour les perfs).

## Exercices

1. **Concurrence vs parallélisme.** Le chapitre 21a montre `yield`
   coopératif. Combien de threads OS sont utilisés ? Combien de cœurs ?
   Si tu as un CPU 8 cœurs, ton programme Heaven V0 en utilise-t-il
   plusieurs ? *Indice* : lis le code du scheduler dans
   `core/continuation.zig`.

2. **Le GIL.** Cherche « GIL Python » et « GIL Ruby » (MRI). Pourquoi
   deux langages populaires ont-ils choisi un GIL malgré le coût en
   performance ? Qu'est-ce que ça simplifie ? Heaven devrait-il en
   avoir un, ou éviter ? *Indice* : la simplicité d'écrire un GC et un
   runtime sans race.

3. **Partition ou partage ?** Pour chacune de ces opérations, dis si
   elle est **partitionnable** (chaque thread ses données, pas de
   communication) ou **partagée** (besoin de synchroniser) :
   - `map f xs` (xs est une liste de 1M)
   - `sum xs` (idem)
   - `counter = counter + 1` sur une variable globale
   - `egraph.add(node)` sur un egraph partagé
   - `http_server.listen(port)` (le serveur accepte des connexions)

4. **WASM et threads.** Lis la spec WASM sur `SharedArrayBuffer`.
   Quels en-têtes HTTP faut-il pour que `SharedArrayBuffer` marche
   dans un navigateur ? Pourquoi ces en-têtes existent-ils (attaque
   Spectre) ? *Indice* : COOP, COEP, `Cross-Origin-Opener-Policy`,
   `Cross-Origin-Embedder-Policy`.

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.

## À toi de jouer

Tu sais maintenant :
- distinguer concurrence (faire semblant) et parallélisme (faire
  vraiment) ;
- les 5 niveaux de la roadmap (`_parallelism_roadmap.md`) ;
- où Heaven en est : **niveau 0**, assumé ;
- pourquoi c'est dur (« ça marche » ≠ « ça scale ») ;
- pourquoi WASM interdit les threads natifs.

Le **niveau 1** (pool de threads) est le prochain chantier parallèle.
Il débloque le niveau 2 (parallélisme de données), qui débloque le
niveau 3 (pipeline), etc.

Mais avant de coder, il faut **décider** : où va l'argent ? Sur
l'auto-hébergement (`39-selfhosting`), sur la formalisation
(`41-semantique-formelle`), ou sur le parallélisme ? Heaven est un
projet expérimental — chaque choix est un pari. Le multi-cœur est un
pari sur la **performance à long terme**. La preuve est un pari sur
la **correction à long terme**. Les deux ne sont pas incompatibles,
mais ils ne se font pas en même temps avec la même énergie.
