<!--
Cette spec utilise une notation pseudo-Heaven pour décrire les
invariants : signatures, capabilities, marqueurs de précision.
Cette notation n'est PAS de la syntaxe Heaven définitive — elle
fixe le contrat sémantique. La grammaire concrète sera fixée dans
grammar.ebnf et `_validation.md`.

Exemples de notation descriptive utilisée ici :
  file.read(cap: FileCap, path: Path)   — signature
  Energy<Measured>                       — type paramétré par précision
  cap.restrict(constraints)              — opération capability
-->

# Plateforme Heaven — conception

**Date** : 2026-09-30
**Statut** : spécification. Aucune implémentation.
**But** : figer les invariants de la frontière Heaven ↔ OS / browser / WASI.
`src/platform/` est le point d'application, pas le point de conception.

## Constat

`src/platform/` contient 14 fichiers `.zig`, ~3258 lignes, organisés
**par OS+arch** : `x86_64_linux.zig`, `aarch64_macos.zig`,
`x86_64_windows.zig`, `wasm.zig`, `wasm32_freestanding.zig`. Chaque
fichier expose ~380-540 lignes d'API hétérogène (`dbg`, `getenv`,
`readEnergyUJ`, file I/O, raw mode...).

Trois problèmes structurels :

1. **Aucune capability**. Les opérations système sont accessibles
   directement. Aucun mécanisme ne restreint ce qu'un programme peut
   ouvrir, envoyer, lire.
2. **Erreurs fragmentées**. `error{Unsupported}` (wasm.zig:17),
   `error{FileNotFound}` (wasm.zig:228), `error{NotSupported}`
   (wasm.zig:237). Pas de type unifié, pas de distinction
   indisponible / refusé / échec.
3. **Précision invisible**. `readEnergyUJ() !u64` retourne un entier
   sans dire si la mesure est fiable, estimée, ou un placeholder.

Deux anomalies annexes : `wasm.zig` et `wasm32_freestanding.zig` sont
identiques (18616 octets, mêmes numéros de ligne) ; `shell_parser_types.zig`
(359 l.) n'a pas sa place dans `platform/`.

## Décisions structurantes

### P1 — Capabilities d'abord

Toute opération qui touche une ressource extérieure au programme
(fichier, socket, processus, périphérique, horloge haute précision,
énergie) exige une **capability** en argument explicite.

    file.read(cap: FileCap, path: Path) : Result<Bytes, PlatformError>
    net.http_get(cap: NetCap, url: Url) : Result<Response, PlatformError>

Une capability porte **le pouvoir effectivement accordé**, pas
seulement sa présence :

    FileCap {
        root        : Path,             // racine autorisée
        permissions : { read, write, exec, ... },
        constraints : { max_size, ... },
    }

    NetCap {
        protocols    : { http, https, ws, wss, tcp, udp, ... },
        destinations : { hosts | CIDR | domains },
        ports        : { min..max },
        permissions  : { connect, listen, ... },
    }

Une opération est refusée si la capability ne couvre pas la
ressource demandée — même si une capability du bon type existe.

### P2 — Pas d'authority ambiante

Aucune fonction ne peut accéder à une ressource sans capability.
Pas d'`open(path)` global, pas d'`env.get()` implicite, pas de
`now()` qui lise l'horloge système sans cap quand une précision est
revendiquée. La capability peut être très large (root = `/`,
permissions = all), mais elle est **explicite**.

Cette règle est ce qui distingue Heaven d'un wrapper POSIX. Sans
elle, `platform` redevient un portier transparent.

### P3 — Précision dans le type

Toute mesure quantitative (temps, énergie, instructions) porte sa
précision dans le type, pas dans une valeur sentinelle.

    Monotonic<Rigorous>   // insulated, monotone, garanti
    Monotonic<Standard>   // monotone, peut subir NTP/freq scaling
    Monotonic<Unavailable>

    Energy<Measured>      // RAPL, SMC — mesure hardware
    Energy<Estimated>     // Δénergie/Δt, modèle
    Energy<Unavailable>

Une fonction qui exige `Measured` ne compile pas si la plateforme
n'offre que `Estimated`. C'est vérifiable statiquement — c'est le
lien avec QTT (voir §Précision et QTT).

### P4 — Pas de `null`

L'absence est exprimée par `Option<T>` ou `Result<T, PlatformError>`.
Jamais `null`, jamais `0` sentinelle, jamais `undefined`.

### P5 — Une seule erreur

`PlatformError` est un type unique, à trois variantes :

    PlatformError {
        Unavailable,   // la plateforme ne fournit pas l'opération
        Denied,        // capability insuffisante
        Failed(why),   // l'opération a échoué pour une raison locale
    }

`Unavailable` et `Denied` doivent être distinguables — un programme
qui obtient `Unavailable` peut retomber sur un fallback ; un
programme qui obtient `Denied` ne doit pas insister.

## Familles de l'ABI

L'ABI Heaven est organisé en **familles fonctionnelles**, pas en
traduction d'APIs OS. Chaque famille définit ses primitives, les
capabilities qu'elles exigent, et la précision qu'elles revendiquent.

    time     — monotonic, wall, sleep
    mem      — alloc, free, total, rss, peak
    random   — bytes, int      (distinct de crypto.random)
    cpu      — cores, loadavg, user_ns, sys_ns
    process  — spawn, kill, wait, exit_code
    thread   — spawn, join, tls
    io       — read, write, flush, seek
    fs       — open, read, write, stat, list, unlink
    net      — http, tcp, udp, ws, dns
    crypto   — hash, mac, sign, key, tls, random
    system   — platform, hostname, user, temp_c
    energy   — total, power, budget
    display  — dpr, resolution, fullscreen

Chaque famille a une définition stricte dans la spec de son
domaine. `_platform.md` ne fixe que les invariants communs.

### Frontières explicites

- `random` ≠ `crypto.random`. Le premier est statistique, peut être
  seedé, ne garantit rien. Le second est cryptographique, insensible
  au seed utilisateur, sans état réutilisable.
- `time.monotonic` ≠ `time.wall`. Le premier mesure des durées, le
  second lit du temps civil. Ils ne sont **jamais** interchangeables.
- `system.platform` retourne un ensemble fini d'identifiants
  (`linux`, `macos`, `windows`, `wasm`, `android`). Pas de chaîne
  libre, pas de version détectée à runtime.

## Modèle de capability

Sept capabilities couvrent les ressources externes :

    FileCap      — voir P1
    NetCap       — voir P1
    ProcessCap   { allowed_executables, max_children, ... }
    DeviceCap    { device_class, ... }
    CryptoCap    { allowed_operations, key_handles }
    DisplayCap   { windows, fullscreen, ... }
    EnergyCap    { read_meters, set_budget }

Les capabilities sont des **valeurs de premier ordre**. Un programme
peut en recevoir, en dériver (par restriction, jamais par extension),
et les passer à un acteur ou à une fonction.

Règle de dérivation : `cap2 = cap1.restrict(constraints)` est
toujours autorisé. `cap2 = cap1.extend(constraints)` est refusé à
la compilation sauf si `cap1` a été créée par une source racine
(bootstrap, ligne de commande, capability ambiante d'un acteur
parent — à préciser dans `_runtime.md`).

## Modèle d'erreur

`PlatformError` est retourné par toute opération faillible :

    Result<T, PlatformError>

Distinction stricte :

- `Unavailable` → la plateforme ne fournit pas l'opération.
  Le programme peut essayer un fallback (`profile` réduit, mesure
  estimée, etc.). Ne doit pas bloquer.
- `Denied`    → la capability ne couvre pas la ressource.
  Le programme ne doit pas réessayer avec d'autres arguments —
  c'est une erreur de conception.
- `Failed(why)` → la ressource est accessible, l'opération a échoué
  pour une raison locale (disque plein, connexion refusée, ...).
  `why` est un code stable, pas une chaîne libre.

Aucun autre type d'erreur ne traverse la frontière `platform`.
Les erreurs OS sont traduites au point d'entrée.

## Précision et QTT

Les marqueurs de précision (`Measured`, `Estimated`,
`Unavailable`, `Rigorous`, `Standard`) sont des **paramètres de
type**, pas des valeurs runtime.

Deux usages :

1. **Fallback runtime**. Un programme qui demande
   `Energy<Measured>` peut accepter `Energy<Estimated>` s'il écrit
   `energy.total() : Option<Energy<P>>` avec `P ∈ {Measured, Estimated}`.

2. **Contrainte statique (QTT)**. Une fonction qui exige
   `Monotonic<Rigorous>` (par ex. un benchmark) ne peut pas être
   appelée sur une plateforme où `time.monotonic` retourne
   `Monotonic<Standard>`. Le compilateur refuse, pas le runtime.

Lien avec QTT : la précision devient une multiplicité de la
mesure. Une valeur `Energy<Estimated>` peut être multipliée par 0
(non utilisée), 1 (lue une fois), ou ω (loggée en continu) — le
système de multiplicité peut exprimer « cette mesure doit rester
valide pour toute la durée du profil », etc. À préciser dans
`_metrics.md`.

## Frontière WASM / natif / OS

`platform` garantit les mêmes **invariants** sur toutes les cibles,
pas la même **disponibilité**.

| Famille | Native | WASI | Browser/WASM |
|---|---|---|---|
| time.monotonic | Rigorous | Rigorous | Standard |
| time.wall | Standard | Standard | Standard |
| mem.rss | Measured | Unavailable | Unavailable |
| mem.peak | Measured | Estimated | Estimated |
| cpu.cores | Measured | Standard | Standard |
| cpu.user_ns | Measured | Unavailable | Unavailable |
| energy.total | Measured (si RAPL/SMC) | Unavailable | Unavailable |
| fs.* | FileCap | FileCap (sandbox WASI) | Unavailable |
| net.http | NetCap | NetCap | NetCap (fetch) |
| crypto.* | ✓ | ✓ (impl interne) | ✓ (WebCrypto) |

Règles :

1. Une opération indisponible retourne `Unavailable`, jamais une
   valeur sentinelle, jamais un panic.
2. Un `profile { ... }` n'échoue pas si une métrique est
   `Unavailable` — il rapporte ce qui est disponible.
3. Le code **portable** est celui qui n'utilise que les opérations
   `Rigorous` / `Measured` **disponibles sur toutes les cibles
   visées**. Le reste est optimisé par plateforme.

## Réorganisation cible de src/platform/

    src/platform/
    ├── abi/                 — définitions de types (Cap, Precision, Error)
    │   ├── capability.zig
    │   ├── error.zig
    │   └── precision.zig
    ├── time.zig             — façade uniforme
    ├── mem.zig
    ├── random.zig
    ├── crypto.zig
    ├── cpu.zig
    ├── process.zig
    ├── thread.zig
    ├── io.zig
    ├── fs.zig
    ├── net.zig
    ├── system.zig
    ├── energy.zig
    ├── display.zig
    └── impl/                — implémentations par cible
        ├── linux.zig
        ├── macos.zig
        ├── windows.zig
        ├── wasi.zig
        ├── wasm_browser.zig
        └── android.zig

Règle d'axe : **famille d'abord, cible ensuite**. Un fichier
`time.zig` déclare l'API ; `impl/linux.zig` fournit les primitives
`clock_gettime(CLOCK_MONOTONIC_RAW)`, `impl/wasm_browser.zig` appelle
`performance.now()`, etc.

Les fichiers actuels (`x86_64_linux.zig`, `wasm.zig`, ...) sont
migrés progressivement dans `impl/`, par famille, pas par big bang.

## Non-goals (explicites)

Les éléments suivants ne font **pas** partie de `platform` et ne
doivent jamais y apparaître :

- **`Promise`**, **`async`/`await`** — modèle de concurrence, voir
  `_runtime.md`. La frontière browser traduit `Promise` → `Future<T>`
  au point d'entrée, rien de plus.
- **`navigator.*`** — pas un modèle. `cpu.cores()` est défini par
  Heaven, pas par le navigateur.
- **`null`** — voir P4.
- **DOM**, **`ui.panel`**, **`ui.editor`**, **GTK**, **Qt**,
  **WinUI**, **SwiftUI** — appartiennent à `vessel/` ou à une
  bibliothèque UI séparée.
- **GPU** (`gpu.compile`, WebGPU, Metal, Vulkan) — chantier dédié,
  pas primitive cœur. Renvoi : futur `_gpu.md`.
- **WebRTC** comme primitive. Le transport est un détail
  d'implémentation derrière `Peer` / `Channel` / `Transport`
  (voir `_runtime.md`).

## Prochaine étape

`_platform.md` fixe les invariants. Les specs suivantes en découlent :

1. **`_runtime.md`** — effects, streams, actors, scheduler. Réconcilie
   `_concurrency.md` (C1-C5), `_effects.md`, `_continuations.md` (D8).
   Les capabilities y sont le point d'entrée d'un acteur ; le
   scheduler y consomme `cpu.cores()` et respecte les `EnergyCap`.
2. **`_metrics.md`** — `Profile` comme terme réifiable, typé par
   précision, alimentant la boucle `Metrics → EGraph → Proof`.
   Les familles `cpu`, `mem`, `energy`, `time` de `platform` y
   trouvent leur usage principal.

Aucun code `src/platform/` n'est écrit avant que ces trois specs
soient stabilisées. Aucun fichier de `platform/` n'est réécrit avant
que `_platform.md` soit actée.

## Références

- `src/platform/` — état actuel (14 fichiers, 3258 l.)
- `docs/spec/_concurrency.md` — C1-C5, prototypes 1-3
- `docs/spec/_effects.md` — bracket/local/catch, contrat perform/handle
- `docs/spec/_continuations.md` — Option B, prototype 3a
- `docs/spec/_metrics.md` — à créer
- `docs/spec/_runtime.md` — à créer
