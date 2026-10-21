# Heaven — PRIMER (contrat implicite, 2026-10-20)

Ce document fixe **ce qui est auto-charge au boot** (sans `import`), ce
qui s'importe, et ce qui est legacy. Sans ce contrat ecrit, chaque
contributeur reinvente des fonctions qui existent deja (7 fichiers
`stdlib/*` morts constates en 2026-10-20, causes par cette ignorance).

## Chargement automatique au boot

Deux mecanismes, avant tout autre code utilisateur :

### 1. `src/main.zig:396-420` -- bootstrap + kernel + prelude

Ingeres via `uni_ingest` dans l'ordre :

1. `core/bootstrap.hvn`
2. `core/kernel.hvn`
3. `core/logic.hvn`
4. `core/prelude.hvn` -- **imports** : Nat, Bool, Option, Result, List, Pair
5. `core/io.hvn`

### 2. `src/core/std_loader.zig` (via `Heaven.init` -> `loadStdIO`)

20 fichiers ingeres par `heaven.eval` (donc tous les ctor sont enregistres) :

    core/io.hvn                    core/std/array.hvn
    core/std/bool.hvn              core/std/string.hvn
    core/std/memory.hvn            core/std/hashmap.hvn
    core/std/list.hvn              core/std/recursion.hvn
    core/std/option.hvn            core/std/lens.hvn
    core/std/pair.hvn              core/std/free.hvn
    core/std/result.hvn            core/std/base.hvn
    core/stream.hvn                core/std/eq.hvn
    core/io_stream.hvn             core/std/ord.hvn
    core/http.hvn
    core/bigint.hvn

**Consequence** : TOUT le contenu de ces 25 fichiers (5 main + 20
std_loader) est disponible **sans aucun `import`** dans tout `.hvn`.

Sont donc auto-disponibles : Nat, Bool, Option, Result, List, Pair,
Array, HashMap, BigInt, Stream, Http, Lens (`lens_fst`, `view`, `set`,
`over`, `set_via`), Free (`Push`, `Add`, `LogOp`, `run_stack`),
Eq/Ord typeclasses, recursion helpers, string helpers, memory helpers,
IO de base.

## Comparaison avec les meilleurs langages

| Aspect | Haskell | Idris 2 | Rust | Heaven |
|---|---|---|---|---|
| Socle auto | `Prelude` | `Prelude` | `std::prelude` | **25 fichiers** (main + std_loader) |
| Extension explicite | `base`, `containers` | `base` | crates | `stdlib/*.hvn` |
| Documentation | oui (spec) | oui | oui | **ce fichier** |

Heaven est **plus large** que les `Prelude` classiques : 25 fichiers
contre ~5-10 chez Haskell/Idris. C'est un choix (batteries included),
mais il **doit** etre documente pour ne pas etre invisible.

## `stdlib/` : API avancee, import explicite

Ne s'importe PAS automatiquement. A importer pour utiliser :

| Module | Concept |
|---|---|
| `stdlib/string.hvn` | helpers avances (split, ends_with, matches_at) |
| `stdlib/fs.hvn` | filesystem (`@fs_read`) |
| `stdlib/ontology.hvn` | KB / RDF |
| `stdlib/mpst.hvn` | Session types (MPST V0.5) |
| `stdlib/effects.hvn` | effets algebriques (`perform`, `handle`) |
| `stdlib/fantasy_land.hvn` | 10 classes McKenna via HKT V1b |
| `stdlib/option.hvn` | Option avance (`catMaybes`, `mapMaybe`) |
| `stdlib/http_body.hvn` | parse HTTP body |
| `stdlib/json/parse.hvn` | parseur JSON |
| `stdlib/net/*.hvn` | ip, udp, tcp, dns, dns_parse, http_client, https, urlencode |

## `stdlib/legacy/` : NE PAS UTILISER (morts 2026-10-20)

Faux doublons de modules **deja auto-charges** :

- `optics.hvn` -> voir `core/std/lens.hvn`
- `free.hvn` -> voir `core/std/free.hvn`
- `profunctor.hvn`, `transformers.hvn`, `json/build.hvn` -> jamais utilises

## `lib/` : runtime core, NE PAS MODIFIER

- `lib/heaven_eval.hvn` (meta-evaluateur)
- `lib/heaven_parse.hvn` (meta-parser)
- `lib/legacy/` : `list.hvn`, `prelude.hvn` (moved 2026-10-20)

## Regles pour les contributeurs

1. **Avant de creer** une fonction dans `stdlib/`, verifier qu'elle
   n'existe pas deja dans les 25 fichiers auto-charges. `grep -r "fn_name" core/std/ core/*.hvn` en 2 secondes.
2. **Etendre** le module canon (`core/std/lens.hvn`) plutot que creer
   `stdlib/optics_v2.hvn`.
3. **Toute API dans `stdlib/`** doit etre importee explicitement.
4. **Documenter** les ajouts dans `docs/STDLIB.md` + `docs/PRIMER.md`.
5. Si un concept manque vraiment et merite d'etre socle : l'ajouter a
   `std_loader.zig` files ET a ce PRIMER.


## Debug : `HEAVEN_DEBUG=1`

`platform.dbg(...)` (`src/platform/io_console.zig:6`) est muet par defaut.
`HEAVEN_DEBUG=1 ./zig-out/bin/heaven ...` active les logs d'instrumentation.
Indispensable pour tracer `perform`/handler IO.

## `lib/` : modules ecosystem

Ne s'importent PAS automatiquement. A importer explicitement.

| Module | Concept |
|---|---|
| `lib/random.hvn` | PRNG LCG + `rand_os_linux` (entropie OS) |
| `lib/syscall/linux_x86_64.hvn` | getrandom/read/write/openat/close via `raw_syscall` |

`lib/heaven_eval.hvn`, `lib/heaven_parse.hvn` : runtime meta, ne pas modifier.


## Debug `.zig` : `std.debug.print` vs `platform.dbg`

`platform.dbg(...)` (io_console.zig:6) est **muet** sans `HEAVEN_DEBUG=1`.
Pour instrumenter un bug, utiliser `std.debug.print` (natif seulement,
wasm KO — protéger avec `comptime target.os != .wasm32`).

Leçon session 2026-10-21 : 3 blocs perdus à cause de `platform.dbg` muet.
Toujours préfixer l'instrumentation par `HEAVEN_DEBUG=1 ./zig-out/bin/heaven ...`
ou utiliser `std.debug.print` natif-only.
