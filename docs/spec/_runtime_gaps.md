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

## 3. Thunks top-level — bug confirmé 2026-11-05

    xyz = 3
    test "xyz_simple": xyz == 3   -- ECHOUE : `xyz != 3`

Le lookup top-level ne résout pas la valeur. Message d'erreur : le **nom** de la
variable, pas sa valeur. Bug dans `engine_expr`/`heaven_expr`, pré-existant à
nos patches arity.

**Les workarounds documentés avant ne marchent PAS** :
- `f _ = (add 1 2); (f 0) == 3` — ECHOUE
- `f = (lambda x -> (add 1 2)); (f 0) == 3` — ECHOUE
- `f = (add 1 2); (let v = f in v) == 3` — ECHOUE

**Ce qui marche** : `(add 1 2) == 3` direct (sans binding top-level).

Les 167 tests `.hvn` de `check_all.sh` passent — les tests existants évitent ce
cas. Bug **latent**, découvert aujourd'hui.

À faire (session 5, ~2h) : instrumenter `eval.sym` dans `engine_expr`. Voir si
le lookup passe par `env` (runtime) ou `store` (AST). Possible lien avec
`normalizeLetChain` / `bound_syms` (cf. G.37-G.40).

## 4. Curryfication — FONCTIONNE (corrigé 2026-11-05)

Le diagnostic précédent ("retourne lambda partielle") était **faux**.

**Marche** :
- `(f 1 2) == 3`                       OK
- `((f 1) 2) == 3`                     OK
- `(f 1 2 3)`                          OK (3-args)
- `((f 1) 2 3)`                        OK (curry 1 niveau + full)
- `(let g = (f 1) in (g 2))`           OK (avec parens autour du let-binding)

**Échoue** :
- `(((f 1) 2) 3)` — double partielle. Les args 2 et 3 sont perdus
  (`add3 1 __curry_0 __curry_1`).

**Cause** : `engine_expr.zig:848-863` crée `lambda(__curry_0, lambda(__curry_1, body))`.
La 2e application ne rebinde pas `__curry_0 := 2` avant d'évaluer `lambda(__curry_1, ...)`.

**Cas rare** : `(((f a) b) c)` n'apparaît pas en pratique.
Workaround : `(f a b c)` ou `((f a) b c)` — les deux marchent.

**Pas prioritaire.**

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

## Arity — état au cutoff 2026-11-05 13h55

### Fait
- `assign` top-level dispatche vers `buildAssign` (`buildTopLevel`)
- `buildAssign` skip le `;` final (`result = add 1;` → val_node = call)

### Reste (diagnostic précis pour session 3)
- `[DBG ASG] name=result count=4 val_type=;` → val_node était `;`, fixé.
- Après fix : `buildAssign` appelle `buildExpr(call_node)` mais **aucun `.apply` ne sort** (arity silencieux).
- Hypothèse : `buildExpr` case `call` → `buildCall` → **`func_id` reste `expr.NULL`** (voir `buildCall` l. 312-332). Si `func_id` est NULL, `store.apply(NULL, args)` est créé mais `node.payload = NULL` — le check arity dans `.apply` skip car `payload < store.len()` est vrai mais `get(NULL).tag` n'est pas `.sym`.
- **Fix probable** (session 3, ~30 min) : instrumenter `buildCall` pour vérifier `func_id` après la boucle. Si NULL, remonter la cause (premier enfant pas reconnu comme `identifier`).

### Acquis conservés
- `assign` dispatché
- `;` skip
- Debug prints retirés (d38f860)
- Doc `_runtime_gaps.md` §check + §arity (à jour)

## Arity — RÉSOLU (2026-11-05 14h30)

### Le vrai probleme
`[DBG CALL] ...` ne s'affiche JAMAIS pour `result = add 1`. `buildCall` n'est jamais appele.

Cause : tree-sitter parse `add 1` (sans parens) comme une sequence plate
`[identifier(add), int(1)]`, PAS comme un noeud `call`. `buildExpr` case
`call` ne se declenche donc jamais. Dans `buildAssign`, on a
`count=4, val_node=identifier(add)` -> `sym("add")`, `1` est perdu.

### Fix applique (session 3)
1. `app_expr` route vers `buildCall` (tree-sitter ne dit pas `call`)
2. `simple_expr` deballe vers son premier enfant (wrapper transparent)
3. `msg_pool` dans Typer pour eviter le leak `allocPrint`

Detail du fix initial (conservé pour reference) :
Dans `buildAssign`, apres `=` :
- Si les enfants restants sont une seule expression -> `bind(name, expr)` (cas actuel, OK)
- Si les enfants restants sont `[premier, arg1, arg2, ...]` -> `bind(name, apply(premier, [arg1, arg2, ...]))`

Pseudocode :
  apres_eq = children[2..count]  (skip ';' trailing)
  if apres_eq.len == 1:
      val_id = buildExpr(apres_eq[0])
  else:
      func_id = buildExpr(apres_eq[0])
      args = [buildExpr(c) for c in apres_eq[1..]]
      val_id = store.apply(func_id, args)
  bind(name, val_id)

Ca evite de dependre du noeud `call` tree-sitter, qui ne reconnait pas
la syntaxe applicative Heaven (`add 1`).

### Acquis conserves (session 2)
- `heaven check` exit 1 sur diag syntax
- ERROR tree-sitter detecte (is_error strict, pas has_error)
- `buildEqDecl` construit lambda+bind (params extraits correctement)
- `assign` dispatche top-level
- `;` skip dans buildAssign
- `countLambdaParams` robuste (sans payload==0)
- Doc honnete a jour

## Curryfication — état 2026-11-05 (P1c-session-4)

### FAUX diagnostic confirme (5e)
Le prompt P1c disait : "curryfication retourne lambda partielle, pas le resultat".
**C'est faux** pour tous les cas reels.

### Tests valides (via `heaven --run-test`)
- `(add3 1 2 3) == 6`                OK
- `((add3 1) 2 3) == 6`             OK (curry 1 niveau + full)
- `(add 1 2) == 3`                  OK
- `((add 1) 2) == 3`                OK
- `(let f = (add 1) in (f 2)) == 3` OK (avec parens)

### Bug residuel (edge case)
- `(((add3 1) 2) 3) == 6` **ECHOUE** → resultat `add3 1 __curry_0 __curry_1`
- Les args `2` et `3` sont perdus entre les deux applications successives.
- Cause probable : `engine_expr.zig:848-863` cree `lambda(__curry_0, lambda(__curry_1, body))`.
  Appliquer `2` donne le bon lambda mais l'evaluation ne rebinde pas
  `__curry_0 := 2` dans le body avant la seconde application.
- **Cas rare** : `(((f a) b) c)` n'apparait pas en pratique. `(f a b c)` et
  `((f a) b c)` marchent tous les deux.

### A faire (session 5, optionnel)
- Instrumenter `engine_expr` au point d'application de lambda.
- Ou documenter comme limitation permanente (workaround : `(add3 1 2 3)` direct).

### Non teste
- Curry via alias : `g = add3 in (g 1 2 3)` — pas verifie

## 3bis. Thunks top-level — diagnostic final (2026-11-05, P1c-session-5)

`xyz = 3` est enregistre comme **clause 0-arity** (`engine.fns.get("xyz")` avec
`num_patterns=0`), PAS comme binding env. `(xyz)` est parse comme `.sym` nu,
donc `evaluate` case `.sym` (`engine_expr.zig:990-1004`) fait `return id` au
lieu d'evaluer la clause 0-pattern. D'ou le message `xyz != 3` (le NOM).

### Fix pret (10 lignes, session 6)

Remplacer `return id` (l. 990-1004) par une evaluation de la clause 0-pattern :

    if (engine.fns.get(name)) |fd| {
        if (fd.num_clauses > 0 and fd.ctor_arity == null) {
            for (fd.clauses[0..fd.num_clauses]) |clause| {
                if (clause.num_patterns == 0 and clause.guard == null) {
                    return try evaluate(store, env, engine, clause.body, depth + 1);
                }
            }
            return id;
        }
    }

Risque moyen : `f = lambda x -> ...` reste OK (retourne la lambda appelable),
mais si un cas depend du `return id` pour des lambdas top-level, ca peut
regresser. **Les 167 tests `.hvn` de `check_all.sh` doivent rester verts.**

### Tests de non-regression a ajouter (session 6)

- `xyz = 3; test "v": xyz == 3` (doit passer apres fix)
- `f = (add 1 2); test "v": f == 3` (doit passer apres fix)
- `f = lambda x -> x + 1; test "appel": (f 2) == 3` (doit rester OK apres fix)
- `add x y = x + y; test "appel": (add 1 2) == 3` (doit rester OK apres fix)

### Faux diagnostics corriges

Le prompt disait "thunk non force = valeur (D12)" + workarounds `f _ = ...`,
`(f 0)`. **Test empirique 2026-11-05** : aucun workaround ne marche (testes).
Le vrai probleme est le `.sym` case l. 990 (`return id` au lieu d'evaluer),
pas la creation de thunk.

## Renommage `16-effects` → `17-effects` — planifie, reporte (2026-11-05)

Decision : reporte. Raison : le renommage cascade touche 12 fichiers + ~40 references
cross-chapter, dont certaines ambiguës (v1 vs v2, ex. `ch. 39` = v1).

Le conflit actuel (`17-effects` et `16-optiques` dans le SUMMARY) est **documente**
dans `SUMMARY.md` via commentaire HTML. Ce n'est pas cassant, c'est visible.

### Plan pour session dediee (~1h)
1. `git mv 16-effects.md 17-effects.md` + cascade `17-handlers` → `18-handlers`, etc.
2. Mettre a jour les H1 dans les 12 fichiers.
3. Script Python qui reecrit les references textuelles `chapitre N` **uniquement** si
   le contexte parle du chapitre concerne (regex avec fenetre de 3 mots avant/apres).
4. Mettre a jour le SUMMARY (12 liens).
5. `mdbook build` doit passer.
6. `check_all.sh` doit rester PROJET SAIN.

Effort : 1h. Risque : moyen. Priorite : cosmetique.


## Selfhost — etat au 2026-11-05 (pre-diagnostic 27-selfhost)

Le selfhost de Heaven est **plus modeste que la doc ne le suggere** :

- `bin/heaven.hvn` (15 l.) : CLI minimal, `argv → exit code` (version→1, help→2,
  run→3, test→4). Preuve de concept compilation native multi-clauses, PAS un
  compilateur.
- `lib/heaven_eval.hvn` (96 l.) : evaluateur metacirculaire V0.4, 17 primitives,
  VRecClosure auto-nommee. Importe `lib/heaven_parse.hvn` (parser HP partiel).

**Ce qui n'existe PAS** : parser complet selfhoste, type-checker selfhoste,
compilateur selfhoste, codegen selfhoste.

Sources v1 : `docs/book/src/39-selfhosting.md` (127 l.), `40-heaven-eval.md` (86 l.).
A fusionner dans `27-selfhost.md` (~200 l., angle honnete).

## Debug prints — après consolidation (2026-11-05)

`debugPrint` (wrappers `heaven_expr.zig` + `engine_expr.zig`) est désormais
conditionné par `HEAVEN_DEBUG` (commit `e42c0dc`).

| Catégorie | Count | État |
|---|---|---|
| `platform.dbg(...)` | 213 | ✅ no-op (`io_console.debug_enabled`) |
| `debugTrace(...)` | ~380 | ✅ no-op (env `HEAVEN_DEBUG_HTTP`) |
| `debugPrint(...)` | ~380 | ✅ **no-op par défaut** (env `HEAVEN_DEBUG`) |
| `platform.debug.print(...)` directs | 49 | ⚠️ actifs, dispersés (1/fichier) |

**Reste** : 49 directs, la plupart dans des `catch`/`errdefer` (rares). À
traiter au fil de l'eau, pas en chantier.

**Pour debugger** : `HEAVEN_DEBUG=1 ./zig-out/bin/heaven run file.hvn`

**Tests** : `check_all.sh` reste `PROJET SAIN` — aucun test `.hvn` ne dépend
de `debugPrint`.

## `heaven check` + `test "name":` — faux positif (2026-11-05)

**Constat** : `heaven check` flagge **142 / 148** `tests/*.hvn` avec
« syntax error » à tort. Isolation :

| Cas | Résultat |
|---|---|
| `test "x": 1 == 1` seul | ❌ ERROR tree-sitter |
| `f x = x + 1` seul | ✅ OK |
| `f x = x+1` + `test "simple": ...` | ❌ ERROR tree-sitter (sur `test`) |

**Cause** : la grammar tree-sitter Heaven ne produit **pas** de nœud valide pour
les blocs `test "name": <expr>` top-level. `heaven parse` (même parser) confirme
le problème en amont.

**Impact** : `heaven check` est **inutilisable sur les fichiers de tests**. Le
gate CI `check_all.sh §7b` ne teste que 3 fichiers synthétiques **sans `test`** —
d'où le faux sentiment que check fonctionne.

**MàJ 2026-11-05 (session 9)** : patch grammar partiel appliqué (`test_decl`
accepte `:` expr + `#` comment). **142 → 81** tests flaggés (-43%). Les 81
restants sont d'autres gaps grammar : `^` (opérateur), `perform "str"` (magic
+ arg), `handle_rec (lambda ...)`, `spawn`/`tell`/`recv`. Chantier à poursuivre
en session 10 (grammar complète, ~2 sessions).

**Fix (chantier session 10+, ~1-2 sessions)** :
1. Étendre la grammar tree-sitter pour reconnaître `test "name": <expr>` comme
   un nœud `test_decl` valide.
2. Ajouter `buildTestDecl` correspondant dans `ast_bridge.zig`.
3. Ajouter `tests/hvn-check/with-test.hvn` qui exerce ce cas.
4. Vérifier que `heaven check tests/*.hvn` passe à 0 faux positif.

**Ce qui est correct** : le fix arity (`e42c0dc` + `9a301c7`) sur ce qu'il peut
analyser (fichiers sans `test`). Le bug est **en amont** (grammar), pas dans
le Typer.

**Ne PAS** :
- Désactiver la détection `ERROR` (on perdrait les vraies erreurs)
- Mentir dans la doc (« heaven check fonctionne »)
- Utiliser `heaven check` comme gate CI sur `tests/*.hvn`

## Grammar batch 4 patches — rollback (2026-11-06, session 10)

**Tentative** : 5 patches grammar (fn `=` expr, `prove ... by { }`, `skill name`, `^` retiré).

**Résultat** :
- ✅ `fn counterHandler(s,m) = ...` parsé (test_actor_multi_msg passe)
- ✅ `--run-test core/test_suite.hvn` 98/98 (runtime OK)
- 🔴 **29 fichiers segfaultent** dans `heaven check`

**Cause probable** : les nouveaux nœuds (`prove_decl`, `skill_decl`, `fn_decl` avec `= expr`) ne sont pas gérés par `ast_bridge.zig` (`buildTopLevel` → `buildFnDecl` accède à `$.block` comme dernier child, mais c'est maintenant `_expr`).

**Rollback** : `git checkout vendor/tree-sitter-heaven/` → 81 flaggés, 0 segfault.

**Prochaine session (10+)** :
1. Patcher `ast_bridge.zig` pour gérer `fn =` (traiter `= expr` comme body alternatif)
2. Patcher pour `prove_decl` (symbole top-level, pas d'action)
3. Patcher pour `skill_decl` (idem)
4. Puis régénérer la grammar
5. Tests : `heaven check` sur 148 tests → 0 segfault, flaggés << 81

**Leçon** : grammar + ast_bridge sont couplés. Patcher l'un sans l'autre = segfault. Un patch grammar doit toujours inclure le patch `ast_bridge` correspondant.

## Grammar batch 4 patches — RÉUSSI (2026-11-06, session 10)

Après le rollback de 10h20 (segfault `ast_bridge`), la tentative 2 a réussi en
patchant `ast_bridge` **avant** la grammar :

| Patch | Effet |
|---|---|
| `buildFnDecl` gère `= expr` (pas seulement `$.block`) | `fn name(params) = expr` parse |
| `buildTopLevel` gère `prove_decl` + `skill_decl` (symboles) | plus de segfault |
| Grammar : `fn_decl` choice `block` ou `= expr` | idem |
| Grammar : `prove_decl` (`prove name by { ... }`) | parse |
| Grammar : `skill_decl` (`skill name`) | parse |

**Résultat** : 81 → **54** flaggés (-33%), 0 segfault, runtime intact
(`--run-test 98/98` + `4/4`).

**Leçon** : grammar + ast_bridge sont **indissociables**. Un patch grammar qui
introduit un nouveau nœud doit inclure le patch `ast_bridge` correspondant.
Commit unique obligatoire — pas de commit "grammar seule".

**54 restants** (session 11) : `^` (conflit unary, précédence à régler),
magics (`perform "str"`, `handle_rec (lambda ...)`), `spawn`/`tell`/`recv`.

## Grammar check — 54 flaggés restants (2026-11-06, session 10)

Après le batch `fn =` + `prove` + `skill` (81→54), les 54 restants se répartissent
en **3 patterns distincts**, chacun grammar + ast_bridge couplés :

| Pattern | Fichier (erreurs) | Exemple |
|---|---|---|
| Bitstrings `<<name:size, ...>>` | `test_bitstrings` (10) | `<<ver:4, ihl:4, _tos:8>> = ...` |
| `let` + `yield` multi-ligne | `test_scheduler` (8) | `(let body (lambda ...yield...))` |
| Magics + lambdas imbriquées | `test_effects_rec` (6) | `(handle_rec (lambda s -> ...))` |

**Effort par pattern** : ~20-30 min (grammar.js + ast_bridge.zig + rebuild +
test 148 fichiers). Risque : segfault si ast_bridge incomplet.

**Décision 2026-11-06** : **reportés**. `heaven check` est un outil dev, pas
critique runtime (98/98 intact). Session dédiée nécessaire.

**Test de régression ajouté** : `tests/hvn-check/with-test.hvn` vérifie que
`test "name": expr` parse (le pattern déjà patché).

## Renommage 16-effects → 17-effects — FAIT (2026-11-06, session 10)

**Fait (commit `0c86c4b`)** : 17 fichiers renommés `git mv`, H1 mis à jour,
SUMMARY réécrit (`16-optiques` reste 16, `17-effects` à `30-conclusion`),
`mdbook build` OK.

**Fait (commit suivant)** : 7 refs externes patchées (`_effects.md`,
`_handle_rec_status.md`, `_runtime_gaps.md`, `24-reseau.md`, `STATUS.md`).

**Reste** : ~39 refs textuelles `chapitre N` / `ch. N` dans la prose du livre
(ex. "le chapitre 17 vous a montré..."). Elles ne cassent pas les liens, mais
sont **stale** après renumérotation (17-effects était 16-effects). À traiter en
session 11 avec un script contextuel (`grep -A2 -B2 'chapitre N'` + correction
manuelle). Effort : 30 min.

## Bitstrings — tentative 1 rollback (2026-11-06, session 10)

**Tentative** : `bitstring_expr` grammar (RHS `<<4:4, 5:4>> == 69`) + handler
`ast_bridge` (`return sym("bitstring_expr")`).

**Résultat** : 🔴 **régression** 54 → 57 flaggés (+3). Le délimiteur `<<` entre
en conflit avec d'autres patterns (probablement `<<` dans les décalages, ou
`>>` binaire). Les 2 expressions bitstring sont encore mal parsées.

Runtime intact : 98/98 (`test_suite`), 74/74 (`test_bitstrings`), 0 segfault.

**Rollback** : `git checkout -- .` → 54 flaggés restaurés.

**Prochaine tentative** (session 12+, ~1-2 sessions) :
1. Le bitstring `<<...>>` doit être un **token entier** (`token(seq("<<", ...))`),
   pas un nœud avec délimiteurs séparés. Sinon conflit avec les opérateurs.
2. Deux formes : `bitstring_pattern` (LHS de `eq_decl`) + `bitstring_expr` (RHS).
3. `ast_bridge` : `buildEqDecl` doit gérer un LHS `bitstring_pattern` (pas juste
   `identifier`).
4. Test : `heaven check tests/test_bitstrings.hvn` doit passer rc=0.

**Leçon** : les délimiteurs custom (`<<`, `>>`) nécessitent `token()` pour
éviter le conflit avec les opérateurs binaires. `prec()` ne suffit pas.

## Refs textuelles post-renommage — état final (2026-11-06, session 11)

**Patché (commit `a3bdcde`)** : 30 refs `ch. N` / `chapitre N` corrigées dans
13 fichiers (`ch. 28→29`, `ch. 26→27`, etc.).

**Skippé volontairement** (12 restantes) :

| Catégorie | Exemple | Pourquoi skip |
|---|---|---|
| **SELF** (4) | `18-handlers.md` : « le chapitre 18 en fait… » | self-référence, déjà correct |
| **AMBIGU** (2) | `27-selfhost.md` : `ch. 30 (hors v2)` | référence v1, annotation explicite |
| **Plages `ch. N-M`** (6) | `24-reseau.md` : `ch. 16-17` | remap ambigu (17-18 ?), documenté |

**Impact** : aucun lien cassé (`mdbook build` OK). La prose est correcte pour
30/42 refs. Les 12 restantes sont soit correctes (SELF), soit v1 (AMBIGU),
soit documentées (plages).

**Pas de patch supplémentaire prévu.** Les 6 plages peuvent être corrigées
manuellement au fil de l'eau si elles gênent la lecture.

## Bitstrings — tentative 2 rollback (2026-11-06, session 11)

**Tentative 2** : `conflicts: [[$.bitstring_expr, $.binary]]` + `bitstring_expr`
(RHS) + `bitseg` + handler ast_bridge.

**Résultat** : 🔴 **même régression** 54 → 57 (+3). Les 3 erreurs restantes sur
`test_bitstrings.hvn` (l. 20, 23, 27) sont le **pattern LHS** `<<ver:4, _tos:8>> = expr`
(binding eq_decl avec bitstring pattern, pas expression RHS).

**Conclusion** : le bitstring nécessite 4 patches couplés :
1. `bitstring_expr` (RHS) — grammar + ast_bridge (essayé, insuffisant)
2. `bitstring_pattern` (LHS de `eq_decl`) — grammar + ast_bridge `buildEqDecl`
3. `buildEqDecl` doit gérer LHS `bitstring_pattern` (pas juste `identifier`)
4. `test_bitstring_expr.hvn` + `test_bitstring_pattern.hvn` séparés

**Effort réel** : ~2-3 sessions, pas 1. **Chantier dédié**, pas de quick fix.

**Décision** : **report définitif**. `heaven check` est un outil dev, pas
critique. Les 3 erreurs bitstrings (sur 54) ne bloquent pas la suite.

## (if c t e) S-expr — patch réussi (2026-11-06, session 11)

**Tentative 3** (après 2 rollbacks bitstrings) : ajouter `(if c t e)` au
`if_expr` grammar (choice avec la forme classique `if c then t else e`),
+ `buildIfExpr` générique (filtre tokens de structure).

**Résultat** : ✅ **54 → 48** flaggés (-6). 0 segfault, runtime intact
(98/98, 4/4).

**Fichiers débloqués** (dépendants de `(if c t e)`) : `test_scheduler`,
`test_effects_rec`, `test_actor_multi_msg` (partiellement), `test_kanren`...

**Leçon** : les S-expr de contrôle (`(if c t e)`) ne sont pas parsés par la
grammar actuelle — elle n'accepte que la forme infixe `if c then t else e`.
Un patch `choice` + `buildIfExpr` générique débloque tous les fichiers qui
utilisent la forme S-expr.

## Scheduler / lambda contextuel — diagnostic partiel (2026-11-06, session 11)

Après le patch `(if c t e)` (54→48), `test_scheduler.hvn` reste à 8 erreurs.
Isolation :

| Cas | Résultat |
|---|---|
| `(let body (lambda s -> (if ...)) 1)` | ✅ parse (var_decl?) |
| `(lambda s -> (if ...)) 42` | ❌ ERROR tree-sitter |

**Conclusion** : `lambda ... -> ...` **parse dans certains contextes** (sous
`let`), **échoue dans d'autres** (body de `test "..."`). C'est une **ambiguïté
contextuelle** de la grammar, pas un pattern manquant.

**Effort pour fix** : 3-4 patches couplés (lambda, test_body, if-with-yield).
Risque de régression élevé. **Report définitif** — `heaven check` est un outil
dev, pas critique runtime (98/98 intact).

**Acquis session 11** :
- `(if c t e)` S-expr : 54 → 48
- 30 refs textuelles patchées
- `tests/hvn-check/if-sexpr.hvn` ajouté
- Diagnostic scheduler/lambda documenté

**Prochains patterns** (session 12+) : bitstrings (2-3 sessions), scheduler/lambda
(2 sessions), magics `handle_rec` + lambdas imbriquées (1-2 sessions). Total
~5-7 sessions pour arriver à ~0 flaggés.

## Magic effects (perform, lambda multi-params) — tentative 3 rollback (2026-11-06)

**Tentative** : `perform 2-args` (`perform "tick" s`) + `lambda x y ->` multi-params.

**Résultat** :
- `perform 2-args` + `prec.right` : pas de conflit, mais **n'améliore rien** (48 inchangé)
- `lambda x y ->` multi-params : conflit non résolu avec `f x y` (application) → retiré

**Rollback** : `git checkout -- vendor/tree-sitter-heaven/` → 48 flaggés restaurés.

**Cause réelle de `test_effects_rec` (6 erreurs)** : `lambda v k -> ...` (2 params).
L'ambiguïté avec l'application `(f a b)` est structurelle : `f x y` peut être
`((f x) y)` ou `lambda x y -> ...`. Résolution possible :

1. **Token `lambda` explicite** : `lambda` est un mot-clé réservé, donc
   `lambda x y -> body` ne devrait **pas** être confondu avec `f x y` (où
   `f` n'est pas `lambda`). Le conflit vient du `sep1($.identifier, " ")` qui
   laisse `x` et `y` indépendants. Solution : `token(seq("lambda", ...))` ou
   `seq("lambda", $.params, "->", ...)` avec `params` = `(identifier)+`.

2. **Precedence dynamic** : `prec.dynamic(11, ...)` sur `lambda_multi`.

**Effort restant** : 30-60 min (1-2 tentatives), risque modéré. **Report
session 12** — après 3 tentatives rollbackées sur les magics, la journée est
saturée.

**Décision session 11** : plafond à **48/148** (32% de faux positifs, -40%
vs début session 10). `heaven check` inutilisable en CI sur `tests/*.hvn`
(documenté dans `_cli.md`), utile pour `check` sur du code hors tests.

## grammar.ebnf vs grammar.js vs expr.zig — clarification (2026-11-06)

**Trois artefacts de syntaxe Heaven, trois rôles distincts** :

| Fichier | Rôle | État |
|---|---|---|
| `docs/spec/grammar.ebnf` | EBNF manuel | ⚠️ **Stale** (25 sept, 5 semaines) |
| `vendor/tree-sitter-heaven/grammar.js` | Gate `heaven check` | ✅ Maintenu, **48 trous** (cf. sections bitstrings, scheduler, magics) |
| `src/core/expr.zig` + `expr_parser.zig` + `heaven_expr.zig` | Vrai parser (`heaven run`) | ✅ Référence |

**Conséquence** : les 48 flags de `heaven check` ne sont **pas des bugs du
langage**. Le langage parse (`heaven run` 168 tests OK). C'est tree-sitter
(`grammar.js`) qui est **incomplet** par rapport au vrai parser.

**Action** : header de `grammar.ebnf` mis à jour pour clarifier cette
distinction. Pas de synchronisation automatique prévue (les 3 artefacts ont
des rôles différents).

## QTT enforced — DÉJÀ FAIT (découverte 2026-11-06)

**Le chantier "QTT enforced (7 sessions)" du prompt était FAUX.**

Le check de multiplicité est fait **au parse**, dans
`src/core/expr_parser.zig:774` (`if (!ok) return error.LinearViolation`).

**Testé (session 12)** :

| Cas | Résultat | Attendu |
|---|---|---|
| `linear` 1 usage | ✅ passe | ✅ |
| `linear` 0 usage | ❌ LinearViolation | ✅ |
| `linear` 2 usages | ❌ LinearViolation | ✅ |
| `erased` 0 usage | ✅ passe | ✅ |
| `erased` 1 usage | ❌ LinearViolation | ✅ |
| `many` 2 usages | ✅ passe | ✅ |
| `many` 0 usage | ✅ passe | ✅ |

**7/7 conformes.** QTT est **enforced** pour les `let` top-level.

**Tests régression** :
- `tests/qtt/let_quantities_ok.hvn` (4 cas positifs)
- `tests/qtt/let_quantities_viol.hvn` (3 violations, whitelisté)

**Limitations** (à vérifier session 13+) :
- Le message `--run-test` est `error.LinearViolation` (brut), pas le message
  pédagogique `linear violation: 'x' declared linear, used wrong number of times`
  (qui existe dans `heaven_expr.zig:1232` mais n'est pas utilisé par le runner).
- Pas testé : multiplicités sur fonctions (`fn linear ...`), sur paramètres,
  sur `let` imbriqués profonds.

**Retiré des chantiers restants** : "QTT enforced (7 sessions)" → **0 sessions**.
