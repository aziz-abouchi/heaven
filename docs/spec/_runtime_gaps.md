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
