# Crash HTTP en Debug (2026-10-27)

## Symptôme

Serveur HTTP Heaven natif (`core/http_server.hvn` + `http_serve`).
- ReleaseFast : 200 OK sur `/repl.html` (38261 o) et `/heaven.wasm`
  (584755 o, sha256 identique), `Content-Type: application/wasm`.
- Debug : crash après ~10-15 requêtes consécutives, panic dans
  `std.heap.debug_allocator.alloc` :
  `assert(!gop.found_existing); // This would mean the kernel
  double-mapped pages.`

## Diagnostic

Ce n'est **pas un leak**. L'interner fait déjà du hash-consing
(`src/core/expr.zig:301`, `if (self.map.get(s)) |id| return id`).
Les strings répétées (`"HTTP/1.1 "`, `"Content-Type: "`,
`"application/wasm"`) sont partagées.

`!gop.found_existing` signifie : l'allocateur Debug a reçu une page
du noyau qu'il croit déjà posséder. C'est la signature d'un **heap
overflow** (écriture hors buffer) ou d'un **double-free**, pas d'une
croissance mémoire.

Même classe que les bugs fuzzer (Debug-only, ReleaseFast OK).
Déclencheur : charge (plusieurs requêtes HTTP → plusieurs évals
profondes → corruption détectée à l'allocation suivante, souvent
`interner.intern` appelé par `string_concat`).

## Cause probable

Patterns Zig bas niveau dans le moteur :
- `store.pool` growable (`std.ArrayListUnmanaged`) → slices
  `span_a` / `spanSliceConst` peuvent devenir dangling si le pool
  realloue pendant qu'une slice est tenue. Documenté au ch. 18
  ("le pool et l'invariant critique") du livre.
- `tco_spine_buf`, `tco_args_buf`, `capture_stack` : buffers
  fixes réutilisés entre évals.
- Interner long-vivant (par design) mais couplé aux évals
  qui peuvent le stresser.

## 3 niveaux de fix (band-aid → QTT)

### Niveau 1 — Arena par requête HTTP (band-aid, ~40 lignes Zig)
Dans `handle_one_client` (ou son équivalent Zig), créer une
`ArenaAllocator` adossée au GPA, y diriger les allocations
éphémères (response, parsing, caps locales), `arena.deinit()` à la
fin. L'interner reste long-vivant. **Masque le symptôme** mais ne
fixe pas la cause racine (dangling slices dans le pool).

### Niveau 2 — Arena par éval (band-aid, ~50 lignes)
`Heaven.eval` crée une arène, y dirige les allocations
intermédiaires (strings concat, env temporaires), la libère à la
fin. Toute la sémantique "expression pure = tout disparaît" est
préservée. **Réduit la surface** mais ne supprime pas les slices
dangling (elles peuvent encore vivre dans l'arène d'un éval parent).

### Niveau 3 — QTT (fix réel, multi-sessions, D19)
`linear` / `erased` / `many` vérifiés statiquement.
- `store.pool` devient linéaire : chaque `apply` consomme ses args,
  le pool ne peut plus être réalloué sous une slice tenue.
- Drop-reuse / FBIP : `map` sur liste linéaire = zéro allocation.
- Plus besoin d'arena : on sait exactement quand chaque octet meurt.

C'est **la réponse architecturale** au "Heaven doit gérer sa mémoire
plus finement que Zig". Voir `docs/spec/_memory.md` ch. 26.

## Workaround (vérifié 2026-10-27)

En Debug, le serveur HTTP fonctionne avec `HEAVEN_NO_LEAK_CHECK=1`
(10/10 requêtes, sha wasm identique). Cette variable désactive le
`DebugAllocator` leak-check et évite le panic `!gop.found_existing`.

- Serveur en **Debug** : `HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven ...`
- Serveur en **ReleaseFast** : pas besoin (fonctionne nativement)
- Le bug reste latent : c'est un **double-free/UAF** quelque part,
  pas un leak. Le panic se déplace avec l'ordre d'allocation.
- Valgrind sur le serveur : non concluant (serveur trop lent à
  démarrer, SIGTERM avant la 1ère requête). À relancer avec timeout
  long (≥120s) ou `heaptrack` via nix-shell.

## Recommandation

Pour débloquer le serveur en Debug rapidement : **Niveau 1 (arena
par requête)**. Pour fixer durablement : **Niveau 3 (QTT)**.

Entre les deux : traquer le heap overflow avec valgrind/heaptrack
(une session), puis décider. Mais QTT reste la cible.
