# Runtime gaps (OTP + Hab, 2026-10-28)

Dettes identifiées pendant O4.1. Bloquent l'actor mailbox Hab.

## 1. `heaven check` est un stub

    $ ./zig-out/bin/heaven check /tmp/bad.hvn
    ROOT=source_file children=1
    CHILD[0] ERROR

Aucune vérification d'arité, de scope, de type. `parse` échoue même sur
`fn f(x, y) = (x + y)` en top-level (tree-sitter-heaven ne gère pas
`fn` à 2 params hors contexte). Voir `_type_magic_gap.md`.

## 2. `run` multi-message perd des messages

Voir STATUS.md:303. Contournement : 1 message par `tell` + `run`.

## 3. Thunks top-level non-déballables

    counter_comp = (H.mk_component ...)    -- thunk
    (H.component_init counter_comp)       -- échoue silencieusement

Fix : `counter_comp _ = (H.mk_component ...)` puis `(counter_comp unit)`.
Cf. `hab/apps/counter.hvn` v3.

## 4. `(f a b)` ne curryfie pas

    f x y = (x + y)
    (f 1 2)        -- retourne lambda partielle, pas 3
    (((force f) 1) 2)  -- pas mieux
    ((f 1) 2)      -- OK (curry explicite)

Fix : passer la fonction à `dispatch_from` qui fait `(force fn mvu msg)`
en inline — c'est le pattern qui marche.

## 5. QTT `erased` = 0 usage strict

    (let erased _ = 5 in 42) == 42       -- OK
    (let erased x = 5 in x == 5)         -- LinearViolation

Sémantiquement correct, erreur peu claire.

## Impact O4.1

L'actor mailbox (`component_actor_spawn` + `component_dispatch`) est
bloqué par 2+3+4. On expose l'API pure (`dispatch_from`, `lens`) qui
contourne 4 et permet le state-threading côté appelant.


## Check v1 (2026-10-28) — détection minimale

Hook dans `evalAssertionNative` (heaven_expr.zig) : walk AST `.apply`
avant évaluation. Attrape :

| Cas | Message |
|---|---|
| `(f 1)` où f prend 2 | `arity 'f': expected 2, found 1` |
| `(f 1 2 3)` où f prend 2 | `arity 'f': expected 2, found 3` |
| corps = lambda | `test body is a lambda (partial application?)` |

**Dette n3** : `(0 unit)` est détecté (échoue) mais avec message cryptique
`(0 unit) != 0` au lieu de `apply non-function '0'`. Raison : `(0 unit)`
produit `.apply(fn_id=apply(...), ...)` — le head n'est pas `.sym` ni `.lit`
mais `.apply` (curryfié). À améliorer en check-v2.

**Dette non-implémentée** : `UnboundVariable` (f non défini). Pour ça il
faut un scope tracking complet, pas juste `engine.fns.get`.

**Structure AST** : le parser produit `.apply` (payload=fn_id,
span_a=[fn_id, ...args]) — PAS `.call(name, args)`. Découverte qui a
coûté 3 itérations.


## Check v2 (TODO) — UnboundVariable + thunks top-level

Non-implémenté en v1. Nécessite un **scope tracking** complet :

- `let many x = ... in` → ajouter `x` au scope local
- `fn f(a, b) = ...` → ajouter `a, b` au scope local
- `.lambda x ->` → ajouter `x` au scope local
- Sinon → `.apply(head=sym)` où `head ∉ scope ∪ engine.fns ∪ magics` = unbound

**Effort** : ~150 lignes Zig, 1 session. Attrape `(undefined x)` et
`(counter_comp unit)` sur thunk top-level (dette #3).

Préparation faite : `engine_expr.isMagicSymbol` est `pub` (utilisable).

**Tests à ajouter** (TDD inversé) :
- `(undefined_fn 5)` → `unbound 'undefined_fn'`
- `let x = 5 in x` → OK (x local)
- `fn f(a, b) = a + b` → OK (a, b locaux)
- `(let x = 5 in (x 1))` → OK (x trouvé, mais checkCallArity détecte apply-non-fn)


## Partial application — message clair (2026-10-29)

Avant :
    ✗ test arity: (lambda __curry_0 (add 1 __curry_0)) != 1

Après :
    ✗ test arity: partial application (lambda result) at lhs = (add 1)
      = hint: missing argument? check arity of the function

Cause : interpForAssert catch id avale l'erreur d'éval partielle.
Fix : détecter .lambda après interpForAssert dans evalAssertionNative.

Note : le patch a été appliqué dans le bloc `test "name":` (où `name`
est déclaré), PAS dans `assert_eq` (où il n'y a pas de `name`).


## Session erreurs v1 (2026-10-29)

### Acquis
- `check-v1` fire `arity 'add': expected 2, found 1` — message clair
- Patch `partial application` en place (défense pour cas non couverts par check-v1)
- `(lambda __curry_0 ...)` n'apparaît plus dans les tests d'arité
- 142 fichiers `.hvn` testés top-level, cohérent

### Anomalies (non critiques)

1. **Crash bigint avalé en parallèle** : `test_bigint_d20.hvn` crash
   individuellement (error: TestFailed), mais dans `runTestDir` parallèle
   le crash n'apparaît pas dans la sortie (exit 0 global). Cause probable :
   `c.wait()` retourne `.Signal` non traité comme failure. Fix 5 lignes
   quand on voudra (traiter `.Signal` explicitement).

2. **`((add 1) 2)` ne fire aucun check** : c'est **correct** — curry
   explicite fonctionne, pas de faux positif. Le patch partial couvre
   les cas où `interpForAssert` retourne une lambda *involontaire*
   (application partielle sans curry explicite).

### Leçon

Le gain `check-v1` (message arity clair) est réel et acquis. Le patch
partial application est une défense en profondeur pour les cas non
couverts. Ensemble, ils donnent :
- `arity 'add': expected 2, found 1` (cas arity)
- `partial application (lambda result) at lhs = ...` (cas partial)

Les 290 `return error.` dans `engine_expr.zig` restent majoritairement
bruts. Étendre à 5-10 erreurs critiques = session future (types,
unbound variable, stack trace).


## Bug sémantique inversé runTestDir (2026-10-29)

**Avant :** `return !any_failed` — retourne `true` si AUCUN échec.

**Conséquence :** dans `test_cmd.zig`, `if (any_failed) return error.TestFailed` :
- Tous tests OK → retourne `true` → erreur faussement positive
- Un test crash → retourne `false` → erreur avalée, exit 0

**Symptôme observé :** `heaven test tests/` → exit 0 malgré
`test_bigint_d20.hvn` qui crash (signal).

**Fix :** `return any_failed;` (1 caractère).

**Bonus :** Signal traité explicitement (CRASHED signal N) au lieu
d'être avalé dans le `else => false`.


### Addendum : `!` en bash

Le `sed -i 's/return !any_failed/return any_failed/'` a échoué avec
`bash: !any_failed: event not found`. C'est l'**expansion d'historique**
`!` qui a mangé l'expression. Cause : `set +H` n'est pas activé par
défaut dans ce shell.

**Règle** : ne jamais utiliser `!` dans une commande shell sans
échappement (`\!`) ou quote simple (`'!'`). Préférer Python pour
les patches contenant `!`.


## `module X` casse les imports qualifiés (2026-10-29)

**Symptôme** : `import "core/std/lens.hvn" as L` puis `(L.view ...)`
échoue silencieusement (retourne un thunk). `(fst (L.lens_snd 0))`
ne donne pas `snd`.

**Cause** : le fichier `lens.hvn` commence par `module Lens`. Les
fichiers sans cette directive (`match.hvn`, `tdd.hvn`, `quickcheck.hvn`)
marchent en `L.foo`. Ceux avec `module X` sont cassés en qualifié.

**Fix immédiat** : retirer `module Lens` de `lens.hvn`.

**Impact** : 12 fichiers stdlib ont `module X` (`base.hvn`, `bool.hvn`,
`eq.hvn`, `free.hvn`, `lens.hvn`, `list.hvn`, `memory.hvn`,
`option.hvn`, `ord.hvn`, `pair.hvn`, `recursion.hvn`, `result.hvn`).
Tous potentiellement affectés s'ils sont importés en qualifié.

**Bug racine** : le parser/elab ne traite pas les modules comme des
namespaces. `module X` est une décoration ignorée au runtime — mais elle
**casse la résolution des fonctions 2-args via X.foo**. À fixer dans
`elab.zig` ou `bridge.zig`.

**Contournement** : aucun fichier ne doit déclarer `module X` tant que
le bug n'est pas fixé. Ou importer sans alias (`as L`) et utiliser
unprefixed (`view`, pas `L.view`).


## Syntaxe lambda — ce qui marche, ce qui casse (2026-10-29)

Tests empiriques sur 8 variantes :

| Forme | 1 arg | 2+ args | Statut |
|---|---|---|---|
| `\x. body` | ✓ | ✗ | Grammar: 1 arg seulement (Style 1) |
| `\x -> body` | ✓ | ? | Grammar: 1 arg seulement (Style 2) |
| `\x y. body` | — | ✗ | Multi-arg + dot cassé |
| `lambda x y -> body` | — | ✓ | **Word + arrow, marche** |
| `lambda x y. body` | — | ✗ | Word + dot, cassé |
| `λ x. body` | ✗ | — | Unicode + dot (encoding bug) |
| `λ x y -> body` | — | ✓ | Unicode + arrow, marche |

### Règle

- **1 arg** : `\x. body` ou `\x -> body`
- **2+ args** : `lambda x y -> body` (word, arrow, jamais dot)
- **Jamais** `.` (dot) avec multi-args
- **Jamais** `λ` (unicode) — encoding problematique

### Cause root

Le grammar tree-sitter (`vendor/tree-sitter-heaven/grammar.js:1598`)
définit `lambda` uniquement avec **1 identifier** (Styles 1 et 2). Le
mot `lambda` (7 lettres) n'est **pas** dans le grammar — il doit être
traité par un préprocesseur ou l'elaborator.

Pour 2+ args, la seule forme définie est Style 3 : `λ(x, y) => body`
avec parens. `lambda x y -> body` marche probablement par chance
(préprocesseur qui réécrit en lambdas imbriqués ?).

### Fix long terme (2 sessions)

Ajouter au grammar tree-sitter : `lambda ident+ arrow body` avec
`repeat1($.identifier)` au lieu d'un seul. Nécessite rebuild C.
Ou : ajouter un préprocesseur dans `bridge.zig` (`trLambda`) qui
détecte N identifiers et crée N lambdas imbriqués.

### Contournement immédiat

Toute fonction à 2+ args stockée en data (pair, liste) doit être
**nommée** (pas lambda) — cf. `compose_getter`/`compose_setter` dans
`lens.hvn`. C'est ce qu'on a fait, ça marche.


## Règle fst vs pattern matching (2026-10-29)

**Découverte** : `(fst param)` **dans une lambda** casse (thunk non réveillé).
**Mais** pattern matching direct dans les params de fn marche :

    make_getter (pair go _) (pair gi _) = (lambda s. (gi (go s)))
    -- ↑ MARCHE (y2 ✓)

    make_getter outer inner =
      (let many go = (fst outer) in
       (let many gi = (fst inner) in
        (lambda s. (gi (go s)))))
    -- ↑ CASSE (y1 ✗)

**Règle** : quand une fonction prend un pair et capture ses
composants dans une closure, utiliser **pattern matching dans les
params**, jamais `fst`/`snd`.

Exemples :
- ✓ `compose_lens (pair go so) (pair gi si) = (lens (lambda s. (gi (go s))) ...)`
- ✗ `compose_lens outer inner = (lambda s. ((fst inner) ((fst outer) s)))`

Ce bug est probablement le même que le `fst-in-lambda` : les thunks
créés par `fst param` ne sont pas forcés au moment de l'application
de la closure. Le pattern matching contourne en liant directement les
symboles (pas de thunk intermédiaire).

Impact : `compose_lens`, `lens_mvu_over`, `dispatch_from` (Hab).


## lens.hvn v1 — périmètre validé (2026-10-29)

**Fonctionne** : `view`/`set_via`/`over`, `lens_fst`/`lens_snd`/`lens_pp_fst`,
`compose_getter` (3 params natifs).

**Ne fonctionne pas** (retiré) : `compose_lens`, `iso_swap`, `over_traversal`
— tous affectés par le fst-in-lambda bug.

**Règle** : `(fst param)` dans closure = bug. Pattern matching
`(pair go _) (pair gi _)` fonctionne.
