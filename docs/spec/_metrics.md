<!--
Cette spec utilise la notation pseudo-Heaven de _platform.md
(signatures descriptives, marqueurs de precision). Voir le
preambule de _platform.md.
-->

# Métriques et profiling Heaven — conception

**Date** : 2026-09-30
**Statut** : spécification. Aucune implémentation.
**But** : fixer le contrat du profiling, du typage des métriques,
et de la boucle `Metrics → EGraph → Proof`.
Dépend de `_platform.md` (P1-P5, précision) et `_runtime.md`
(§Contraintes imposées à `_metrics.md`).

## Constat

`src/core/profiler.zig` implémente `Profiler{start, stop}`
retournant un `ResourceMetrics` :

    ResourceMetrics {
        energy_joules    : f64,
        memory_peak_kb   : u64,
        cpu_cycles       : u64,
        cpu_instructions : u64,
        wall_time_ns     : u64,
        cpu_time_ns      : u64,
        ...
    }

`src/platform/profiler_linux.zig` lit RAPL directement :
`/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj`, sans
capability, sans distinguer mesure de l'estimation. Un appelant qui
reçoit `energy_joules = 0.0` ne peut pas savoir si :
- l'énergie mesurée est réellement 0 (impossible physiquement),
- RAPL n'existe pas sur cette machine,
- la lecture a échoué silencieusement (`catch 0`).

Quatre problèmes structurants :

1. **Pas de précision typée**. `f64` et `u64` nus — contrairement
   à `_platform.md` P3.
2. **Pas de capability**. La lecture RAPL est un accès device qui
   exige `EnergyCap` (`_platform.md` P1).
3. **Pas scopé**. `start()` / `stop()` manuels violent la
   contrainte 1 de `_runtime.md` : `Profile` doit être un effet
   scopé (`bracket`).
4. **Pas un terme**. `ResourceMetrics` est un struct C non
   réifiable : impossible de le hasher, comparer, stocker, ou
   l'injecter dans un `EGraph`.

## Décision structurante — `Profile` est un terme

Un `Profile` est une **valeur du langage**, pas un log :

    Profile {
        id          : ProfileId,           // hash stable
        parent      : Option<ProfileId>,   // pour les profils imbriqués
        metrics     : Map<MetricKind, Metric>,
        scope_kind  : ScopeKind,           // local | remote | ...
    }

Propriétés requises :

1. **Hashable**. `id = hash(scope_kind || metrics)` — deux profils
   identiques ont le même `id`.
2. **Comparable**. `profile.diff(p1, p2) : ProfileDiff` — compare
   les métriques disponibles dans les deux.
3. **Stockable**. `store.put(profile_id, profile)` — la sérialisation
   est une extension de `serialize.zig` HVN1 (voir `_serialize.md`).
4. **Injectible**. `profile.metrics` peut alimenter un `EGraph` —
   voir §Boucle Metrics → EGraph → Proof.

Un `Profile` n'est **pas** un `ResourceMetrics` réifié. C'est une
structure qui porte des métriques **typées par précision et par
disponibilité**, avec son identité stable et sa relation de
parenté.


### Implémentation (2026-09-30)

Voir `src/platform/abi/profile.zig` : `Profile` est une struct
avec 7 champs `Metric(T)` + `id`, `parent`, `scope`. `computeId()`
fait le hash content-addressed (Wyhash sur les 7 champs + parent +
scope). 22 tests.

`ProfileId` = `u64`. `ScopeKind` = `local | remote | nested`.

## Typage des métriques

Chaque métrique porte **trois informations** : sa valeur, sa
précision, sa source. Conforme à `_platform.md` P3.

### Types de précision

    Precision = Measured | Estimated | Unavailable

Pour les durées :

    Monotonic<Rigorous>   // insulated, monotone, garanti
    Monotonic<Standard>   // monotone, peut subir NTP/freq
    Monotonic<Unavailable>

### Types de métrique

    Metric<T, P: Precision> =
        | Value(T)         // mesure disponible à precision P
        | Unavailable     // plateforme ne fournit pas

Une opération qui exige `Measured` ne peut pas utiliser un résultat
`Estimated` sans un `.promote()` explicite (qui documente
l'approximation). Le compilateur refuse les usages implicites.

### Catalogue (à aligner sur `_platform.md` §Familles)

| Métrique | Type | Précision native | WASI | Browser |
|---|---|---|---|---|
| `wall_time` | `Duration<Monotonic<Rigorous>>` | Rigorous | Rigorous | Standard |
| `cpu_time` | `Duration<Monotonic<Standard>>` | Standard | Unavailable | Unavailable |
| `rss` | `Bytes<Measured>` | Measured | Unavailable | Unavailable |
| `peak_rss` | `Bytes<Measured>` | Measured | Estimated | Estimated |
| `energy` | `Energy<Measured>` | Measured (RAPL/SMC) | Unavailable | Unavailable |
| `instructions` | `Count<Measured>` | Measured | Unavailable | Unavailable |
| `allocations` | `Count<Measured>` | Measured | Measured | Estimated |

### Accès aux métriques

Une métrique est lue **au sein d'un profil actif** :

    profile.metric::<Energy>() : Metric<Energy, P>

Si la plateforme retourne `Unavailable`, l'accès produit
`Metric<Energy, Unavailable>`. Pas de `0.0` sentinelle, pas de
`null`, pas d'erreur levée. C'est P3 + P4 de `_platform.md`.

## Capabilities requises

Chaque famille de métrique est associée à une capability :

| Métrique | Capability |
|---|---|
| `wall_time` | aucune (implicite) |
| `cpu_time`, `rss`, `peak_rss` | `ProcessCap` (lecture du process courant) |
| `energy`, `power` | `EnergyCap` |
| `instructions`, `cycles` | `ProcessCap` (perf_event sur Linux) |
| `network_bytes` | `NetCap` |
| `allocations` | aucune (compteur interne) |

Sans capability, l'accès retourne `Metric<_, Unavailable>`. Le
programme peut l'ignorer, mais il ne reçoit pas de valeur inventée.

### Note énergie

`EnergyCap` est **runtime**, pas QTT (`_concurrency.md` §QTT et
concurrence). Elle porte :
- `read_meters : Set<MeterId>` — quels compteurs peuvent être lus
- `budget : Option<Energy>` — budget énergétique optionnel
- `interval : Option<Duration>` — si le budget est lu par polling

Un acteur sans `EnergyCap` reçoit `Energy<Unavailable>` sur toute
lecture. Aucune exception.


### Implémentation (2026-09-30)

Voir `src/platform/abi/precision.zig` (types `Precision`,
`Monotonic`, `Value(T, P)` compile-time, `Metric(T)` runtime) et
`src/platform/abi/metric.zig` (`Metric(K, P)`, 7 Kinds :
`WallTime`, `CpuTime`, `Rss`, `PeakRss`, `Energy`, `Instructions`,
`Allocations`).

`Scalar(K)` : `Energy` en `f64`, les autres en `u64`.

`Metric(K, .unavailable)` n'a pas de champ `value`. `.init(v)` et
`.as()` sont des `@compileError` explicites, pas des panics
runtime.

## `Profile` = effet scopé

Contrainte 1 de `_runtime.md` : `Profile` doit s'exprimer avec
`bracket`, pas comme primitive runtime.

### Sémantique

    profile(name) {
        body
    }

se traduit en :

    bracket(
        setup    = fn () -> ProfileHandle { open_profile(name) },
        body     = fn () -> T { ... },
        teardown = fn (h: ProfileHandle) -> Profile { close_profile(h) }
    )

- **`setup`** : démarre les compteurs, crée un `ProfileHandle`
  (capture les valeurs initiales des compteurs cumulatifs).
- **`body`** : code profilé. Toutes les métriques lues dans ce
  scope sont associées au `ProfileHandle` courant.
- **`teardown`** : arrête les compteurs, calcule les deltas,
  construit le `Profile` final (hashable, comparable, stockable).

### Profils imbriqués

    profile("outer") {
        a();
        profile("inner") { b() };
        c();
    }

L'`id` du profil inner a le profil outer comme `parent`. Le
`teardown` inner s'exécute **avant** le `teardown` outer. Le
`Profile` inner est accessible au profil outer via son handle —
permet une hiérarchie (arbre de profils).

### Contrainte 2 — Pas de traversée de safepoint

Un safepoint (`_concurrency.md` C3) est un point de préemption.
Un `profile` ouvert **ne peut pas** être traversé par un safepoint
sans redéfinir son scope.

Raisons :
1. Un safepoint peut changer de process — la mesure serait
   attribuée au mauvais acteur.
2. Les compteurs cumulatifs du process suspendu ne sont plus lus
   pendant la suspension — la mesure serait faussée.
3. Un `throwCont` (`_continuations.md` D8) qui traverse un
   `profile` ferait fuir le `ProfileHandle`.

**Conséquence technique** : `open_profile` installe un **prompt**
(`_continuations.md` §3a-1). Toute capture de continuation entre
`setup` et `teardown` est bornée à ce prompt. Un `throwCont` qui
tenterait de traverser échoue (ou force une fermeture propre — à
trancher en Prototype 3a-2).

### `profile` et capabilities

Un `profile` peut exiger des capabilities en paramètre :

    profile(name, caps: {EnergyCap, ProcessCap}) { body }

Sans les capabilities listées, les métriques correspondantes sont
`Unavailable` — pas d'erreur, pas de refus. Le `Profile` final
contient les métriques que la plateforme peut fournir, et marque
les autres `Unavailable`.


### Implémentation (2026-09-30)

`Profile` est un terme réifiable (`profile.zig`), mais la syntaxe
`profile { body }` n'est pas encore implémentée. La structure
`bracket` est en place (`_effects.md`), l'articulation avec le
prompt (contrainte 2) dépend du Prototype 3a-2 (`captureCont`).

Politique d'accès explicite (`profile.zig`) :
`requireMeasuredEnergy` refuse les estimations,
`energyWithFallback` les annote (`Reading(T) { value: ?T,
estimated: bool }`). C'est la validation empirique de P3 dans un
langage dynamique : le caller doit choisir une politique, il n'y a
pas d'accès silencieusement mélangé.

## Boucle `Metrics → EGraph → Proof`

C'est le point différenciant de Heaven : ne pas seulement mesurer,
mais **exploiter** la mesure dans le moteur de transformation.

### Pipeline

    programme avec profile { body }
        ↓
    Profile { metrics, id, parent }
        ↓
    egraph.add_profile(profile)
        ↓
    Optimiseur : cherche des réécritures qui minimisent une métrique
        ↓
    Proof : certifie que la réécriture préserve la sémantique
        ↓
    Nouveau programme + Profile' + preuve

### Ce que `EGraph` reçoit

Un `Profile` injecté dans l'`EGraph` est représenté comme un **terme
annoté** :

    node(
        kind  = profile,
        scope = <hash of body>,
        cost  = { energy, time, rss, ... }
    )

Le `scope` est un hash du `body` profilé — deux profils sur le même
corps de code ont le même `scope`, ce qui permet à l'EGraph de
comparer leurs coûts. Le `cost` est un vecteur de métriques.

### Optimisations visées

- **`optimize for energy`** : chercher une réécriture équivalente
  qui minimise `energy.total()`.
- **`optimize for latency`** : minimiser `wall_time`.
- **`optimize for memory`** : minimiser `peak_rss`.
- **`optimize for throughput`** : maximiser un rapport entre
  `instructions` et `wall_time`.

Ces optimisations ne sont possibles que si :
1. Le coût est dans l'`EGraph` (fait par `add_profile`).
2. La réécriture est **prouvable équivalente** (`_proof.md`) — on
   ne remplace pas un programme par un autre « qui marche » sans
   preuve.

### Lien avec le noyau CIC

`Profile` est **orthogonal** au noyau (`_runtime.md` §Invariant
fondateur). L'ajout d'un `Profile` à l'EGraph n'ajoute aucune
primitive à `initNatAxioms`. Le noyau reste à 7 primitifs
(`Nat`, `zero`, `succ`, `add`, `mul`, `nat_ind`, `eq_rect_nat`).

La preuve `profile(A) ≈ profile(B)` est une preuve d'équivalence
de coût — elle se réduit, dans le noyau, à une égalité dans le
modèle arithmétique (arithmétique de Peano + lemmes de coût).

## Sérialisation

Un `Profile` doit pouvoir être stocké et transmis :

    serialize(profile) : Bytes
    deserialize(bytes) : Result<Profile, DecodeError>

Format proposé : extension de `serialize.zig` HVN1 avec une section
`Profile` dédiée. Le hash `id` est **content-addressed** : deux
profils identiques sérialisent au même `id`, permettant la dédup.

Pré-requis : `_serialize.md` doit acter l'extension (section
`Profile` du format HVN1).


### Implémentation (2026-09-30)

Voir `src/platform/abi/profile_ser.zig` et l'extension
`_serialize.md` §Profils (HVP1) :

Format HVP1 v1 : magic `"HVP1"` + parent flag + parent `u64` (opt)
+ scope + 7 champs (tag + valeur). 6 octets vide, 77 octets rempli.

L'`id` n'est **pas** sérialisé : `deserialize` le recalcule par
`computeId()`. Content-addressed : deux profils identiques
produisent les mêmes bytes et le même id.

8 tests dont 3 cas de corruption (`BadMagic`, `BadTag`,
`BadScope`).

Non implémenté (v2) : index optionnel de profils dans HVN1
(`profile_count` + chunks HVP1 self-contained).

## Non-goals (explicites)

- **`console.time()`** — API de log, pas de profiling.
- **`performance.mark()`** — équivalent navigateur, non réifiable.
- **`Profile` comme primitive runtime** — viole `_runtime.md`
  contrainte 1.
- **Métriques `null`** — voir `_platform.md` P4. Toujours `Value`
  ou `Unavailable`, jamais `null`.
- **`0.0` sentinelle** pour « indisponible » — viole P4. Un zéro
  physique (rare mais possible) et un « je ne sais pas » sont
  distincts.
- **Traversée de safepoint en cours de profil** — viole la
  contrainte 2 de `_runtime.md`.
- **Profiler le remote sans capability** — un acteur distant ne
  peut pas être profilé sans `RemoteProfileCap` (à spécifier en
  sécurité).

## Prochaine étape

Cette spec clôt la cascade `_platform.md` → `_runtime.md` →
`_metrics.md`. Chantiers qui en découlent :

1. **Extension `_serialize.md`** — section `Profile` dans HVN1.
2. **Spec sécurité future** — capabilities d'audit, `RemoteProfileCap`,
   propagation d'identité.
3. **Implémentation Prototype 4** — `add_profile` dans l'EGraph,
   optimisations coût-guidées.
4. **Kernel** — dériver les lemmes de coût (`add` et `mul` sur les
   métriques) comme théorèmes, pas axiomes.

Aucun code `src/metrics/` n'est écrit avant ces étapes.

## Références

- `_platform.md` — P1-P5, précision, capabilities, ABI
- `_runtime.md` — contraintes 1-3, effets scopés, safepoints
- `_proof.md` — équivalence prouvable
- `_serialize.md` — format HVN1, à étendre
- `src/core/profiler.zig` — état actuel (à refactorer)
- `src/platform/profiler_{linux,darwin,windows}.zig` — mesures brutes
