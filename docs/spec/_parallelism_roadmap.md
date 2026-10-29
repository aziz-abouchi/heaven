# Parallélisme Heaven — roadmap

## Distinction fondamentale

| Concept | Définition | Statut Heaven |
|---|---|---|
| **Concurrence** | Plusieurs tâches progressent entrelacées | ✅ scheduler préemptif |
| **Parallélisme** | Plusieurs tâches s'exécutent simultanément (cœurs) | ❌ 0 % |

Concurrence ≠ parallélisme. On a l'un, il manque l'autre. Le modèle
acteur est le bon support pour les deux.

## Niveaux (inspirés d'Erlang/BEAM)

### Niveau 0 — actuel : 1 thread + scheduler préemptif
### Niveau 1 — pool de threads + work-stealing (~2-3 sessions)
- N threads (1 par cœur)
- 1 file de tâches par thread
- Vol de travail quand file vide
- `spawn` distribue round-robin
- Isolation acteurs préservée (état local)
- Risque : `Store` partagé → à partitionner ou protéger

### Niveau 2 — parallélisme de données (1 session)
- `pmap`, `preduce` sur listes
- Découpage en chunks, exécution parallèle
- Utilisable sans changer le scheduler

### Niveau 3 — pipeline (`Producer | Transformer | Consumer`)
- Cas particulier de Niveau 1
- Chaque étage = 1 thread dédié
- Utile pour streams

### Niveau 4 — distribué (2+ sessions)
- Acteurs sur N machines
- Modèle BEAM : `node@host`
- Dépend de MPST (protocoles réseau typés)

## Ordre recommandé

1. **Niveau 1** en premier — gain immédiat sur tests/load
2. Niveau 2 ensuite — gain scientifique
3. Niveau 4 en dernier — chantier long

## Ce qui existe déjà pour aider

- `scheduler.zig` : file de tâches + préemption (base Niveau 1)
- `scheduler/task.zig` : TaskId + états (base vol de travail)
- `xargs -P 8` a montré 4,8× sur `heaven test` — preuve que le
  parallélisme process fonctionne
- `BATCH=8` dans `runTestDir` — même pattern, à généraliser
