# Mémoire — conception

**Date** : 2026-10-13
**Statut** : P0 livré (couche Heaven), vision bootstrap à implémenter.
**But** : formaliser la gestion mémoire de Heaven dans la lignée QTT
+ Perceus/FBIP, et tracer le chemin de la couche actuelle vers le
bootstrap complet.

## Principe

En mode **bootstrap complet** (Heaven bare-metal, auto-hébergé),
le développeur n'écrit **jamais** `malloc` ni `free` manuellement,
et **aucun GC à balayage** n'intervient. La gestion dynamique est
distribuée entre :

- le **compilateur** (analyse QTT + Perceus/FBIP),
- le **système de types** (multiplicités 0/1/ω),
- la **couche plateforme** (`core/platform/mod.hvn`).

## Qui déclenche alloc et free

Les instructions sont **injectées par le compilateur** lors des
passes d'élaboration et de génération (MIR).

### Analyse QTT

Chaque ressource est étiquetée avec sa **multiplicité** :

- `0` — effacée (preuve, spécification) : 0 octet au runtime.
- `1` — linéaire : consommée exactement une fois, propriétaire
  unique.
- `ω` — libre : partagée ou réutilisable.

Deux règles en découlent :

- **`free` / `drop`** : injecté à la fin de portée d'une valeur
  linéaire (`1`) non réutilisée.
- **`alloc`** : injecté à l'instanciation d'un constructeur
  (`Cons`, `Tuple`, `Lambda`) si aucun bloc compatible n'est
  disponible dans la chaîne de réutilisation.

### Perceus / FBIP — drop-reuse

Si le compilateur détecte qu'une structure linéaire est détruite
juste avant qu'une nouvelle structure de même taille soit allouée
(ex. `map` sur une liste), la paire `free` + `alloc` est remplacée
par un **`drop-reuse`** : la mémoire est modifiée directement,
sans passage par l'allocateur système.

C'est le point-clé de l'approche « Functional But In-Place »
(FBIP) : des algorithmes fonctionnels purs, zéro réallocation
supplémentaire en régime permanent.

## Quand sont-ils déclenchés

- **`alloc`** : à l'évaluation d'un constructeur ou d'une lambda,
  si aucun bloc n'est réutilisable.
- **`free`** : au point de consommation finale (*last use*) d'une
  variable linéaire. La mémoire est restituée immédiatement —
  pas d'accumulation de mémoire morte, pas de pics GC.

## Comment au niveau bas niveau

En bootstrap autonome (sans libc hôte), les fonctions `alloc` et
`free` vivent dans `core/platform/mod.hvn` :

    alloc : Int -> Ptr
    free  : Ptr -> Int -> Unit

    alloc = sys.alloc
    free  = sys.free

Trois familles d'implémentation selon la cible :

### Linux x86_64 / ARM64

- `alloc size` → `@syscall mmap` (syscall 9 sur x86_64, 222 sur
  ARM64) : pages anonymes au noyau.
- `free ptr size` → `@syscall munmap` (11 sur x86_64, 215 sur
  ARM64) : restitution au système.

### Bare-metal / noyau d'OS (mode Vinix-like)

- `alloc` : allocateur de pages noyau (bump pointer ou buddy
  allocator).

### WASM (`wasm32-freestanding`)

- `alloc` : extension directe de la mémoire linéaire via
  `memory.grow`, ou gestionnaire de mémoire de l'hôte.

## Cas des calculs temporaires — arènes

Pour les structures éphémères (typage, unification miniKanren,
E-Graphs, sessions parsing), Heaven alloue les nœuds dans un
**`TermPool` par arène** (`std.ArrayListUnmanaged` côté Zig,
`Arena` côté Heaven).

Principe :

- **Aucun `free` individuel** pour chaque sous-terme logique.
- À la fin de la requête ou de la passe, **l'arène entière est
  libérée d'un seul bloc** via `arena.deinit()`.
- Zéro fuite par construction.

## État actuel (P0 — livré le 2026-10-13)

**`core/std/memory.hvn`** existe et fournit :

    alloc size         = (raw_alloc size)
    dealloc ptr size   = (raw_free ptr size)

    data Arena = MkArena Int Int Int
    arena_new cap
    arena_alloc a size    -- (pair ptr arena')
    arena_reset a
    arena_deinit a
    arena_used / arena_cap / arena_remaining

    memcpy64 src dst n

Chargé au boot via `std_loader.zig` (avant `list.hvn`).
Tests : `tests/test_memory.hvn` (14/14).

Ce qui est **livré** :

- couche mémoire Heaven, wrappers sur `raw_alloc`/`raw_free`,
- `Arena` bump-pointer immutable,
- `memcpy64` (encore naïf, à optimiser via un vrai magic).

Ce qui **reste à faire** :

- migrer `http.hvn`, `fs.hvn`, `net.hvn`, `json.hvn` vers la
  couche `memory.hvn`,
- exposer `engine.memory` (arène Zig contrôlée par Heaven) pour
  que `raw_alloc` pointe dedans,
- ajouter un magic `@mem_stats` pour le monitoring,
- QTT temps/énergie (hors scope actuel),
- auto-hébergement complet (phase E en cours).

## Premier consommateur cible — Vessel

**Vessel** (ancien serveur web, IDE, monitoring) est un vestige
en cours de remplacement par la stack HTTP Heaven-native. Il
utilise actuellement beaucoup d'allocations éphémères (E-Graph
viewer, monitoring process, ressources).

C'est le **premier client réel** de `memory.hvn` + `Arena` :
une arène par requête HTTP, libérée en bloc à la fin de la
requête.

## Dettes identifiées

- **Multi-shot continuations** : clonage d'environnement, à
  concevoir (voir `_continuations.md`).
- **QTT temps/énergie** : extension du système de multiplicités
  à des dimensions physiques (hors scope V0).
- **ABI C** : mentionnée dans le book, absente du code
  (remplacée par `@nom` + `raw_syscall`).
