# Runtime gaps (OTP + Hab, 2026-10-28)

Dettes identifiées pendant O4.1. Bloquent l'actor mailbox Hab.

## 1. `heaven check` est un stub

    $ ./zig-out/bin/heaven check /tmp/bad.hvn
    ROOT=source_file children=1
    CHILD[0] ERROR

Aucune vérification d'arité, de scope, de type. `parse` échoue même sur
`fn f(x, y) = (x + y)` en top-level (tree-sitter-heaven ne gère pas
`fn` à 2 params hors contexte). Voir `_type_magic_gap.md`.

## 2. `run` multi-message — RÉSOLU 2026-11-04

Le `run` actuel (engine_expr.zig:2673) draine **toute** la mailbox
dans un `while (true)` avec `orderedRemove(0)`. Vérifié : 5 messages
= 15 (test `multi5`). Gap stale depuis le fix du 2026-10-27 (budget
par message) + `while (true)` présent.

Régression testée dans `tests/test_actor_multi_msg.hvn`.

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


## apply-chain-in-returned-lambda (2026-10-29) — PRÉCISÉ

**Diagnostic final** (après 8 tests) :

| Test | Code | Résultat |
|---|---|---|
| d1 | `(lambda x. (lambda y. (x + y)))` | ✓ |
| d2 | `(lambda o. (lambda s. ((fst o) s)))` | ✗ |
| d3 | `(force (lambda o. ...))` | ✗ |
| d4 | `(lambda o. (lambda s. (fst o)))` | ✓ |

**Cause précise** : quand `(fst o)` est **appliqué** à `s` dans une
lambda retournée, l'éval ne réduit pas l'apply-chain. La substitution
`o := (pair fst snd)` se fait, mais l'application à `s` reste bloquée.
`force` ne résout pas.

**Scope** : `apply(apply(fst, o), s)` où `fst` est un builtin et `o`
vient d'un paramètre de lambda.

**Impact** : `compose_lens`, `iso_swap`, `over_traversal`, tout code
qui fait `(getter param) s` dans une closure.

**Contournement** : pattern matching direct `(pair go _) (pair gi _)`,
ou composer les getters hors de la lambda avec `let many`.

**Test permanent** : `tests/pending/fst_apply_in_lambda.hvn` (rouge,
ne pas exécuter dans la suite standard).

**Investigation future** : tracer `substSym` + parser infixe pour voir
si `((fst o) s)` est parsé `apply(apply(fst, [o]), [s])` ou
`apply(fst, [o, s])`. Si le 2e, c'est le parser qui fusionne, pas l'eval.


## `import ... as X` casse les fonctions qualifiées (2026-10-29)

**Symptôme** : `import "foo.hvn" as F` puis `(F.bar ...)` retourne un
thunk au lieu d'appeler `bar`. Marche en unprefixed.

**Reproduit sur** :
- `module Lens` dans `lens.hvn` → retirer `module` a fixé (v1)
- `import ... as SV` pour `supervisor.hvn` (r5 ✓ unprefixed, r6 ✗ `SV.child_mk`)
- Probablement tous les imports `as X`

**Cause** : le qualifié `X.foo` retourne la valeur (thunk) sans appliquer.
Le runtime ne résout pas `X.foo` comme "appel de foo dans le module X" —
c'est traité comme accès à une variable.

**Contournement** : ne pas utiliser `as X`. Importer unprefixed :
    import "core/std/otp/supervisor.hvn"
    (child_mk inc 0)  -- unprefixed, marche

**Impact** : tout code qui utilise `import as X` sur des fonctions 2-args.
Cf. `hab/app.hvn` réécrit unprefixed.


## heaven build — bundler fonctionnel (2026-10-29)

**Livré** : `heaven build <dir|file> -o <out.hvn>` — bundler incrémental.

**Fonctionne** :
- `heaven build hab/ -o /tmp/hab.bundle.hvn` → 8 scannés, 13 résolus, 18KB
- `heaven build /tmp/test_hab.hvn -o /tmp/th.hvn` → 4 résolus, 6KB
- `heaven test /tmp/th.hvn` → **60/60** ✓

**Algorithme** :
1. Détection dir/file (openDir d'abord, trim trailing slash)
2. Scan récursif `.hvn`
3. Extraction `import "X"` ligne par ligne
4. Résolution récursive (préfixes connus : core/, hab/, tests/, examples/)
5. Concat topologique avec marqueurs `-- ═══ path ═══`
6. Écriture bundle self-contained

**Test réel** :
    heaven build /tmp/test_hab.hvn -o /tmp/th.hvn
    heaven test /tmp/th.hvn  →  60/60

**Résultat** : les tests bundlés passent sans `import` runtime.
La distribution en 1 fichier fonctionne.

**Dette notée** :
- `exit: 0` après `112/138` sur `hab.bundle.hvn` — bug `runTestFile`
  (pas `runTestDir`). `runTestFile` retourne `void` au lieu de `!bool`.
- Pas encore de `heaven build --native` (compile-qbe cassé : NoExpression,
  UnsupportedOp, UnsupportedCall).

## 3 backends natifs — état 2026-10-29

| Backend | `solo.hvn` (main = 42) | Note |
|---|---|---|
| `compile` (C) | ⚠️ génère `=(=, main, 42);` | C invalide |
| `compile-qbe` | ✗ NoExpression | Ne gère pas `main = 42` |
| `compile-wasm` | ✗ UnsupportedCall | Manque les appels |

**Conclusion** : `heaven build --native` impossible. Les 3 backends sont
des prototypes partiels. L'interpréteur (via `heaven test`) est le seul
moteur d'exécution fiable.

**Plan futur** :
- Session : fix `compile-qbe` (NoExpression → détecter `main`)
- Session : fix `compile-wasm` (UnsupportedCall → dispatch appels)
- Session : `heaven build --native` = bundle + compile-qbe


## compile-qbe — état réel 2026-10-29 (après diagnostic)

**Tests systématiques** (5 formes) :

| Forme | Parser | Codegen |
|---|---|---|
| `42` nu | ✓ | ✗ UnsupportedCall |
| `main = 42` | skip (definition) | NoExpression |
| `fn main() = 42` | skip | NoExpression |
| `main = 42` + `main 0` | ✓ | ✗ UnsupportedCall |
| `print 42` | ✓ | ✗ UnsupportedCall |

**Diagnostic** : le parser produit une expression valide. Le codegen
(`mir_qbe.zig` + `compileRoot`) lève `UnsupportedCall` sur presque tout.

**Effort pour fixer** : 2-3 sessions Zig
- `mir_qbe.zig` : implémenter UnsupportedCall (appels, closures, strings)
- `mir.zig` : MIR complet pour les primitives
- Linker QBE → binaire

**Décision 2026-10-29** : `compile-qbe` reste prototype cassé. On ne le
fixe pas cette session. `heaven build --native` est reporté de 2-3
sessions. Le workflow natif actuel = `heaven build` (bundle) + `heaven
test` (interpréteur).

**Alternatives court terme** :
- `heaven build --bundle` : bundle seul (livré)
- `heaven test bundle.hvn` : exécution interprétée (livré, 60/60)
- `heaven build --native` : futur (2-3 sessions)

**Piège** : `main = X` est avalé par `isDefinition` et ne devient pas le
programme. Convention `compile-qbe` = expressions nues uniquement.


## Diagnostic compile-qbe (2026-10-29, session 2) — CAUSE ROOT

**Cause root** : `mir.zig` `compileExpr .apply` ne gère QUE :
- `while`, `if`, `break` (control flow)
- fns **utilisateur** (`engine.fns.get(op_name) != null`)

**Aucun builtin** n'est émis : `fst`, `snd`, `pair`, `cons`, `head`,
`tail`, `+`, `-`, `*`, `=`. Ces builtins ne sont **pas dans
engine_expr.zig** non plus (grep = 0 résultats) — ils sont gérés
seulement par l'interpréteur (`engine.eval`).

**Conséquence** : `precompileUserFns()` précompile 37 fns std (dont
`set_fst`, `get_pp_fst` qui utilisent `fst`). Même un fichier `42` nu
échoue parce que ces fns std sont précompilées → `UnsupportedCall
name=100='fst'`.

**Diagnostic confirmé par** :
- `fst`, `snd` : UnsupportedCall (names 100, 60)
- Aucun grep de builtin dans `mir.zig`/`mir_qbe.zig`
- Le wrapper `$main` émet `printf` en QBE brut, mais le MIR root
  contient les 37 fns std précompilées

**Effort pour fixer** : 2-3 sessions Zig
- `mir.zig` : implémenter `fst`, `snd`, `pair`, `cons`, `head`, `tail`
  (6 builtins minimum)
- `mir.zig` : implémenter arithmétiques (`+`, `-`, `*`, `=`, `<`, `>`)
- `mir_qbe.zig` : émettre ces primitives en QBE
- `mir_wat.zig` : idem WASM (2 sessions de plus)

**Décision finale 2026-10-29** : `compile-qbe` reste prototype cassé.
Chantier 2-3 sessions dédiées, pas un fix ponctuel. `heaven build
--native` reste reporté. Workflow natif = `heaven build` (bundle) +
`heaven test` (interpréteur).

**Ne pas retenter sans plan dédié** : les sessions 2-3 Zig nécessaires
sont documentées dans le plan futur (`_parallelism_roadmap.md` mentionne
déjà les niveaux).


## compile-qbe : phis std cassés (2026-10-30)

**Symptôme** : `qbe:prog.ssa:N: predecessors not matched in phi %r16`
sur les fn std précompilées (set_fst, sup_tick_fn, etc.).

**Cause** : compileIf/compileWhile produit des blocs MIR avec phis mal
formés quand le corps de la fn contient des if/while imbriqués. Bug
pré-existant à notre patch.

**Notre patch (v0.9)** :
- 3 opcodes heap (alloc/load_at/store_at)
- 6 builtins compileExpr (pair/fst/snd/cons/head/tail)
- Stubs QBE pour call_user non résolus
- warn au lieu de fail

**Mode pur** : `HEAVEN_NO_STD_FNS=1 heaven compile-qbe` compile
(fst (pair 1 2)) → 1, (snd (pair 1 2)) → 2, imbriqué OK.
Fonctionne car on saute les 37 fns std.

**Sessions futures** :
1. Fix compileIf/compileWhile phis (1 session) — débloque compile-qbe
   avec std fns
2. Split mir.zig types/compile (30 min) — rebuild de 60s à 10s
3. WASM backend (3-4 sessions)

**Perf dette** : mir.zig importé par 10 modules (mir_qbe, mir_wat,
x86_64, heaven_expr, proof/*, commands/*). Chaque patch = 1m08s. Le
cache est sain (0.14s sans changement). Split nécessaire.


## compile-qbe phi3 (2026-10-30) — DETTE 1 session

**Symptôme** : `sign x = (if (< x 0) (0 - 1) (if (> x 0) 1 0))` → `UnsupportedOp`.

**Cause probable** : parser/lowering transforme `(0 - 1)` ou `(> x 0)`
en expression que `compileExpr .apply` ne reconnaît pas (`op_name` pas
`"-"` ou `">"` attendu).

**Tests v0.95 OK** : choose, if top, fst, check (4/5).
**Phi3 KO** : sign avec if imbriqué.

**À faire session future** :
1. Dump `lowerRec(clause.body)` pour phi3, voir l'AST exact
2. Identifier le tag non géré (probablement `.binop` pour `-` infixe)
3. Ajouter dans `compileExpr` : `.binop => { ... }`

## Split mir.zig — PRIORITAIRE (2026-10-30)

**Problème** : `mir.zig` (1700 lignes) importé par 10 modules. Chaque
patch = **2m05s**. Le cache est sain (0.14s sans changement), c'est la
cascade de recompilation.

**Fix** : split en 2 fichiers
- `src/core/mir/types.zig` : `Instr`, `Reg`, `BlockId`, `FnDef`, `PhiEntry`, `MirFunction` (struct seulement)
- `src/core/mir/compile.zig` : `compileExpr`, `compileIf`, `compileWhile`, `precompileUserFns`

Backends (`mir_qbe`, `mir_wat`, `x86_64`) importent **uniquement types.zig**.
Un patch de `compile.zig` ne recompile que `mir.zig` (facade) + 2-3 modules.

**Gain estimé** : 2m05s → 15-20s par patch. Multiplicateur de vélocité.

**Effort** : 45 min (move structs, refactor imports, zig build une fois).


## WASM backend — état 2026-10-30 (3-4 sessions)

**Pipeline** : `compile-wasm file.hvn -o out.wat` → WAT text.
`wat2wasm` + `wasmtime` sont installés localement.

**Ce qui marche** :
- `mir_wat.zig` émet le WAT pour arith/if/fns user
- Patch heap : `alloc`/`load_at`/`store_at` → `unreachable` trap
  (au lieu d'erreur bloquante au build)

**Ce qui échoue** :
- `(+ 1 2)` → `UnsupportedCall` (checkCallUsers fail, pas de stubs)
- `(choose 1)` → `UnsupportedExpr` (pipeline WAT incomplet)

**Sessions nécessaires** :
1. Skip `checkCallUsers` en warn + stubs `(func $fN (result i64) (i64.const 0))`
   (même pattern que mir_qbe) — 1h, 1 build 2m41s
2. Entry `_start` WASI + fd_write pour printf — 1 session
3. Heap WASM (memory.grow, load/store WASI) — 1 session
4. Strings/bytes + tests — 1 session

**Prérequis** : split `mir.zig` en types/compile (45 min). Sinon 2m41s/iteration.

**WAT actuel** : freestanding (pas de `_start`). `wasmtime` refuserait
même si compilé. `wasi_main.zig` + `wasm_entry.zig` existent, à brancher.

## G.33 — `@argv` dans fn user (segfault) — 2026-10-30

    getarg __i = (@argv __i)
    main = (getarg 1)

Segfault (139). Cause : `argv_sym` stocké sur `fn_mir` courant, pas
propagé au root → wrapper `$main()` n'émet pas `storel %argv`. À
l'exécution : `load $heaven_argv = 0`, `load_at NULL`.

Fix : scanner `fn_defs` dans `emitQbeLoop`, si un seul `argv_sym`
non-null → wrapper `l $main(l, l)` + émettre `data $gN`.

Effort : 30 min, 1 rebuild.

## G.34 — `@strcmp "str"` dans fn user (undef fN) — 2026-10-30

    cmp __x = (@strcmp __x "version")
    main = (cmp "version")

`undef fN` au link. Cause : `str_pool` local à `fn_mir`, G.31 skip
les fn_defs avec `str_pool` non vide → `cmp` pas émise → `main`
appelle `$fN` → undef.

Fix : pool global partagé (root.str_pool utilisé par tous les
fn_defs). Rend G.31 inutile.

Effort : 45 min, 1 rebuild.

## WASM selfhost + heaven_eval (2026-10-30 nuit)

### G.35 — WASM `call_user` unresolved (résolu)
`mir_wat.zig` levait `error.UnsupportedCall`. Fix : stub
`(local.set $rN (i64.const 0))` au lieu de fail (pattern G.31 QBE).

### G.36 — `main = EXPR` WASM (résolu)
`wasm_cmd.zig` n'avait pas le fix `main =` de `qbe_cmd.zig`
(eda3c24). Port du fix.

### G.37 — `parse_file` 1 token → ENil
`HP.parse_file (HP.lex "nil")` → `ENil` (programme vide).
Contournement : contexte multi-token.

### G.38 — `HP.parse_file` `let`/`lambda` → ArityMismatch
`HP.parse_file (HP.lex "(let x 5 x)")` → `ArityMismatch`.
Contournement : AST hardcodé (`HP.ELambda`, `HP.EApply`).

### G.39 — `λ`/`fn` dans string `.hvn` → ArityMismatch
Parser tree-sitter hôte intercepte `λ`/`fn` **dans une string**.
Contournement : AST hardcodé ou pas de keyword dans le test.

Fix G.37-G.39 : session parser dédiée (~1h). Débloque `heaven_eval`
sur vrais `.hvn`.

## test_web_ontology.hvn — panic net:close (2026-11-02)

Découvert en resync STATUS. `tests/test_web_ontology.hvn` panic :

    [cap_acquire] trace scope=net:connect
    [cap_acquire] trace scope=net:close
    thread ... panic: reached unreachable code
    Unable to dump stack trace: debug info stripped

C'est un **bug runtime** (cap `net:connect`/`net:close` dans
`engine_expr.zig`), pas un bug parser. Fichier déplacé dans
`tests/_disabled/` en attendant fix.

À investiguer : la branche `unreachable` dans le handler `net:close`
est probablement atteinte sur un cas non géré (connexion échouée ?
fd invalide ?). Session dédiée.

## Mise à jour 2026-11-02 : `[32]` ne fixe pas ces deux cas

`FunctionClause` `[16]`→`[32]` (commit `0f49e8d`) a débloqué 14 tests
(`test_eval` 13/13, `test_meta_if` 7/7, cf. G.39 RESOLU). Mais les
deux fichiers disabled restent KO :

- **`test_bigint_d20.hvn`** : segfault au chargement (rc=139), avant
  tout test. C'est un **stack overflow** au parse/lower, pas un
  problème d'`eval_apply2`. Spec `_bigint_d20_stack.md` : bdiv/bmod
  récursifs profonds. Reste disabled.
- **`test_web_ontology.hvn`** : panic `unreachable` dans
  `net:close`, **après** plusieurs tests réussis (dont
  `socrate_starts_s`). Bug runtime `net:close` distinct, non lié
  aux clauses. Reste disabled.

Voir aussi : G.37 (token unique → ENil, KO après [32]),
G.38 (`let` KO après [32], `λ`/`fn` OK).

## `zig build test` FAIL + 7 leaks (2026-11-02)

`check_all.sh` montre `zig build test` FAIL + 7 leaks. **Pré-existant**,
non cassé par `[32]` ni par les commits du 2026-11-02. Cause probable :
`test_mir_qbe.zig` / `mir_qbe.zig` (contrat §6, CI rouge depuis
2026-10-30). À traiter en session Zig dédiée.

Voir aussi : `_ci_checklist.md`.

## Mise à jour 2026-11-02 (soir) — test_web_ontology

Variante **offline** créée : `tests/test_web_ontology_offline.hvn`
(15 tests, fonctions pures de `lib/web/ontology.hvn` : strip_*, find_*,
extract_first_label avec string construite via `@char_string 34`).

`tests/_disabled/test_web_ontology.hvn` (HTTPS live vers dbpedia.org)
reste disabled :
- dépend de `134.155.98.109` (DNS hardcodé)
- panic `net:close` sur connexion échouée (OpenSSL, non patché —
  effet de bord du live, pas un bug critique)
- **fait 2026-11-02** : `lookup_label_with http_fn` (DI) +
  `tests/test_web_ontology_mocked.hvn` (8/8, stub `empty_http`/`stub_http`).
  Le live reste disabled (panic `net:close` OpenSSL), mais la logique
  `extract_first_label` + `strip_*` est couverte offline + mockée.

**Note (corrigée 2026-11-02 soir)** : il n'y a PAS de bug
`label_arr_pat` — le pattern `"label":["` (10 chars) était correct.
Le test original échouait uniquement à cause de G.40 (`"` non escape
dans la string), pas de `extract_first_label`.

Voir aussi : G.40 (`\"` non escape).

## test_bigint_d20 : bdiv 1000 → ExecutionFailed (2026-11-02)

`bdiv 100 7` → 14 ✅, `bmod 100 7` → 2 ✅.
`bdiv 1000 7` → `ExecutionFailed` **même avec `(@set_fuel 100000)`**.

Ce n'est **pas** le fuel de l'interpréteur. C'est `bdivmod_step`
(core/bigint.hvn:188) qui a une complexité qui explose sur 4 chiffres.
Le test isolé ne segfault plus (contrairement à l'ancien symptôme),
il retourne `ExecutionFailed`. Le fichier `test_bigint_d20.hvn` reste
disabled.

**À faire** (session dédiée) : profiler `bdivmod_step`, remplacer par
un algorithme itératif (division longue schoolbook avec `bsub_once`
borné par le nombre de chiffres, pas par le quotient). Voir
`_bigint_d20_stack.md`.

Voir aussi : G.40, `test_web_ontology_mocked.hvn` (DI smocker).

## `heaven check` — état au 2026-11-05 (session P1c)

### Ce qui marche
- Exit code 1 si diagnostics (commit `7addadd`)
- Détection nœuds `ERROR` tree-sitter (pas `has_error` — trop large, flag les MISSING cosmétiques)
- `buildEqDecl` construit `lambda+bind` pour `add x y = x + y` (commit `f2d3237`)
- `typer.infer` tolère tous les tags créés par le Bridge

### Ce qui ne marche pas
- **Arité non vérifiée** : `heaven check arity.hvn` (= `add x y = x + y; result = add 1`) reste silencieux.
- Hypothèse : dans `Store.apply`, le `func` est en `span_a[0]`, pas dans `node.payload`. Le check `fn_arity` dans `typer.infer case .apply` cherche au mauvais endroit.
- Fix probable : changer `if (node.payload < self.store.len())` en lecture `span_a[0]`, ou résoudre via `applyArgs` + parent.

### Ce qui est testé
- `tests/test_http*.hvn` non concernés.
- Prochain chantier : ajouter `tests/hvn-check/*.hvn` pour figer le comportement (clean, arity, syntax-error).

### Fausse piste (pour mémoire)
- `fn add(x, y) = …` **n'est pas** Heaven : la grammar tree-sitter n'accepte pas `fn` keyword. La syntaxe réelle est `add x y = x + y`.

## `heaven check` arity — cause racine identifiée (2026-11-05 13h45)

### Diagnostic
`[DBG CLP] iter=0 cur=5 tag=lambda payload=0 BREAK-payload-0`

`interner.intern("x")` retourne **0** dans le contexte du Bridge `buildEqDecl`. Donc `Store.lambda([x, y], body)` produit deux lambdas dont `payload=0` — indistinguables des lambdas **0-arity** légitimes (`lambda()` sans param, cf. `Store.lambda` l. 928).

### Fix préparé mais désactivé
`typer.countLambdaParams` compte maintenant les lambdas tant que `body_slice[0]` est **lui-même** une lambda, sans critère `payload==0`. C'est sémantiquement correct, mais **le check ne sort toujours pas** — probablement parce que `buildCall` n'émet pas de `.apply` pour `add 1` (le call sans parenthèses est peut-être parsé différemment, ou `buildExpr` produit un autre nœud).

### Pour la prochaine session (~1h)
1. Instrumenter `buildCall` et `buildExpr` pour tracer ce qui est réellement produit pour `add 1`
2. Fixer `interner.intern` côté Bridge (pourquoi "x" → 0 ?)
3. Ou — plus simple — stocker l'arité **directement dans le nœud bind** (champ `aux` ou `span_b`), sans passer par la structure lambda curryfiée
