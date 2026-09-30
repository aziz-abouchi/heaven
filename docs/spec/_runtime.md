<!--
Cette spec est une CARTE, pas un territoire. Elle ne prend pas de
nouvelle décision : elle réconcilie _concurrency.md, _effects.md,
_continuations.md, _platform.md en une vue unifiée du runtime, et
comble les trous inter-specs (Streams, Capabilities ↔ Acteurs,
frontière browser). En cas de désaccord avec une spec de domaine,
c'est la spec de domaine qui fait foi.
-->

# Runtime Heaven — conception

**Date** : 2026-09-30
**Statut** : spécification carte. Aucune implémentation.
**But** : articuler les specs de domaine (`_concurrency.md`,
`_effects.md`, `_continuations.md`, `_platform.md`) en une vue
d'exécution unifiée. Fixer les invariants que `_metrics.md` devra
respecter.

## Constat

Quatre specs de domaine existent, chacune couvre un aspect :

| Spec | Couvre |
|---|---|
| `_concurrency.md` | Modèle process (C1-C5), scheduler, prototypes 1-3 |
| `_effects.md` | `perform`/`handle`, `bracket`/`local`/`catch` |
| `_continuations.md` | Prompts délimités (D8), Prototype 3a |
| `_platform.md` | Capabilities, précision, erreurs, ABI |

Aucune ne dit **comment elles s'articulent**. Le risque : que
chacune évolue en isolation et que leur intersection devienne
incohérente (par ex. qu'une continuation capture un état de
capability qu'elle ne devrait pas conserver).

## Invariant fondateur — orthogonal au noyau CIC

Les 5 primitives du runtime (`spawn`, `send`, `recv`, `yield`,
`self`) sont des **effets algébriques**, pas des primitives du
noyau logique. Elles s'expriment sur `perform`/`handle` existants
et n'ajoutent **rien** à `initNatAxioms`.

Conséquence directe : le noyau CIC reste à 7 primitifs
(`Nat`, `zero`, `succ`, `add`, `mul`, `nat_ind`, `eq_rect_nat`).
Le runtime est **orthogonal** au kernel. C'est ce qui permet à
`Profile` (`_metrics.md`) d'être un terme réifiable sans introduire
de dépendance circulaire.

## Cartographie — 5 couches, où vit chaque décision

Reprise de la hiérarchie de `_concurrency.md`, avec pour chaque
couche la spec de référence :

| Couche | Contenu | Spec |
|---|---|---|
| **Programmation** | actors, reactive, async | `_effects.md` |
| **Communication** | channels, mailboxes, streams | `_runtime.md` §Streams |
| **Concurrency** | fibers, tasks, continuations | `_continuations.md` |
| **Scheduling** | workers, work-stealing, priorités | `_concurrency.md` C1-C5 |
| **Exécution** | OS threads, WASM, CPU, peer | `_platform.md` |

Règle : aucune décision d'une couche ne peut contredire une couche
inférieure sans une mise à jour explicite de la spec de référence.

## Streams unifiés

`_concurrency.md` mentionne `Stream<T> = handler de l'effet Yield<T>`
sans développer. C'est le premier trou à combler : fichiers, sockets,
mailboxes d'acteurs, générateurs — tout doit partager **la même**
abstraction.

### Définition

    Stream<T> {
        next() : Option<T>
        close()
    }

Trois modes d'obtention :

1. **Pull** — l'appelant itère : `stream.next()`. Backpressure
   naturelle.
2. **Push** — le producteur pousse dans un buffer borné. Si plein,
   le producteur suspend (ou échoue selon la politique).
3. **Reactive** — la source notifie. Utilisé par `reactive` couche
   programmation (à préciser dans une spec future).

### Sources concrètes et leur mode

| Source | Mode | Précision |
|---|---|---|
| Fichier (`fs.open`) | Pull | — |
| Socket (`net.*`) | Pull/Push | — |
| Mailbox d'acteur | Pull | FIFO garanti |
| `Generator<T>` | Pull | — |
| `Interval` (`time`) | Push | `Monotonic<Rigorous>` si natif |
| Effect handler (`handle`) | Push | dépend de l'effet |

### Invariant partagé

Un `Stream<T>` est **linéaire** au sens QTT : une seule boucle de
consommation active à un instant donné. `next()` consomme, il n'y a
pas de duplication implicite. Pour observer plusieurs fois, il faut
explicitement `stream.tee()` (à spécifier).

Cette décision est cohérente avec C4 (structured concurrency) : un
`Stream` vit dans le scope qui l'a créé, il est clos à la sortie du
scope (comme un fichier en Rust).

## Effects ↔ Actors ↔ Scheduler

Trois couches interagissent constamment. Règles d'articulation :

### `perform`/`handle` et le scheduler

Un `perform` synchrone (`_effects.md` §contrat) **ne suspend pas**
le process. Un `perform` qui ne trouve pas de handler prend le
chemin `engine.last_performed`. Le scheduler n'intervient pas.

Un `perform` **asynchrone** (nouveau, à introduire avec les
continuations D8) suspend le process au prompt le plus proche. Le
scheduler reprend un autre process. C'est là que `pushPrompt` /
`popPrompt` (`_continuations.md`) entrent en jeu.

### Scoped effects (`bracket`/`local`/`catch`) et les scopes structurés

`bracket(setup, body, teardown)` garantit :
- `setup` s'exécute **avant** `body`
- `teardown` s'exécute **après** `body`, même en cas de crash
- Si `body` spawn un acteur dans un scope, l'acteur est **annulé**
  à la sortie du scope si non terminé (cohérent avec C4)

`local(name, val, body)` restaure l'ancienne valeur à la sortie,
même en cas de préemption native. La restauration est un
safepoint implicite.

`catch(body, default)` rattrape les crash du scope courant. Un
`catch` au-dessus d'un `scope { ... }` intercepte la propagation
par défaut (C4).

### Préemption et capture de continuation

Un safepoint (`_concurrency.md` C3) est un point où le scheduler
peut suspendre. À un safepoint :

- La continuation courante peut être capturée **si** on est sous un
  prompt (`pushPrompt` actif).
- Sinon, la suspension est locale au process (pas de capture
  utilisateur).

Cette distinction est **la** garantie qui empêche qu'un
`throwCont` saute par-dessus un `bracket` sans exécuter son
`teardown`. À valider en Prototype 3a-2.

## Capabilities ↔ Acteurs

Un acteur est créé avec un ensemble de capabilities. Règle stricte :

    spawn(handler, init, caps: Caps) -> Pid

`Caps` est un ensemble fini de capabilities (`_platform.md` P1).
À la création, l'acteur **reçoit** une copie ; il ne peut que
**restreindre** (`cap.restrict(...)`).

Interdictions :
- Un acteur ne peut pas créer une capability plus large que celles
  qu'il a reçues.
- Un acteur ne peut pas utiliser une capability d'un autre acteur
  sans qu'elle lui soit explicitement passée par message.
- Une capability ne peut pas survivre à l'acteur qui l'a créée si
  elle est `linear` (QTT).

### Passage par message

Un message peut contenir une capability. Cela permet la délégation :

    tell(pid_target, OpenFile(cap: FileCap, path: Path))

Le handler du target reçoit la capability et peut l'utiliser ou la
restreindre. La capability reste attachée à son propriétaire d'origine
pour l'audit — à préciser dans une spec sécurité future.

### Lien avec `_metrics.md`

Un acteur peut recevoir une `EnergyCap` (budget énergétique). Cette
capability n'est **pas** un budget QTT (qui est statique, 0/1/ω),
c'est un budget runtime (`_concurrency.md` §QTT et concurrence).
Les deux cohabitent sans se confondre.

## Frontière browser / WASM

Le modèle actor/effects/continuations est **uniforme**. Ce qui
change à la frontière browser :

| Concept Heaven | Traduction browser |
|---|---|
| `Future<T>` | `Promise<T>` (adaptateur entrée/sortie) |
| `Stream<T>` (pull) | `ReadableStream` (adaptateur) |
| `Channel<T>` | `MessageChannel` |
| `spawn` | `Worker` (implémentation possible) |
| `yield` | `queueMicrotask` / `scheduler.postTask` |

**Non-goal critique** : `Promise` n'est **jamais exposé** au code
Heaven. Un appel à `fetch()` natif traverse un adaptateur qui
retourne un `Future<T>`. Inversement, un `Future<T>` exposé à du
code browser est converti en `Promise<T>` à la frontière — et
seulement là.

Raison : si `Promise` fuit dans le langage, on aura un second
modèle de concurrence (`_concurrency.md` C1 le refuse explicitement).

Le mode `yield` en browser est **coopératif strict** (pas de
safepoints, cf. C1). Un process CPU-bound en browser bloque son
worker — c'est la contrainte WASM, pas un défaut.

## Non-goals (explicites)

- **Nouvelle primitive CIC** — interdit. Le runtime est orthogonal
  au kernel (cf. §Invariant fondateur).
- **Second modèle de concurrence** — pas de `Promise` exposé, pas
  d'`async`/`await` de surface, pas de `Worker` comme primitive.
- **Scheduler par paradigme** — un seul scheduler (`_concurrency.md`
  C5 sauf sous-scheduler logique explicitement tranché).
- **Superviseurs BEAM** — remplacés par structured concurrency (C4).
- **Migration distribuée en Prototype 2** — reportée à Prototype 4.
- **Duplication de `_concurrency.md`** — ce document renvoie, il
  ne redit pas.

## Ce que `_metrics.md` devra respecter

Trois contraintes imposées par cette spec :

1. **`Profile` est un effet scopé**, pas une primitive runtime. Il
   s'exprime avec `bracket` : `setup` démarre les compteurs,
   `teardown` les arrête et retourne l'artefact.
2. **Un `Profile` ne traverse pas un safepoint sans redéfinir son
   scope.** Sinon une préemption pourrait fausser la mesure.
3. **Les métriques disponibles dépendent des capabilities.** Un
   acteur sans `EnergyCap` reçoit `Energy<Unavailable>`, il ne
   reçoit pas de chiffre inventé.

## Prochaine étape

Cette carte est stable. Les specs qui en découlent :

1. **`_metrics.md`** — `Profile` comme terme réifiable, précision
   (`Energy<Measured|Estimated|Unavailable>`), boucle
   `Metrics → EGraph → Proof`.
2. **Spec sécurité future** — capabilities, identité, audit,
   autorisation. Actuellement : note dans `_platform.md` §Capabilities.

Aucun code runtime n'est écrit avant que `_metrics.md` soit stable.
Le Prototype 3a-2 (`captureCont`/`throwCont`) peut avancer en
parallèle — il ne dépend que de `_continuations.md` (D8) et de cette
carte.

## Références

- `_concurrency.md` — C1-C5, prototypes 1-3, découvertes P1
- `_effects.md` — perform/handle, bracket/local/catch
- `_continuations.md` — D8, Prototype 3a (prompts, captureCont)
- `_platform.md` — capabilities, précision, erreurs
- `_metrics.md` — à créer
