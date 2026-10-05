# Syntax gaps -- ecarts identifies

> Statut : index de veille. Chaque gap est documente avec un cas
> de reproduction minimal. Aucun n'est corrige pour l'instant.
>
> Les fichiers concernes (`elab.zig`, `heaven_expr.zig`, `parse.zig`)
> sont en WIP externe (session parallele). Ne pas modifier avant
> que leur travail soit commite.

## Gap 1 -- data multi-lignes

**Reproduction :**

    data TestOp
      = Op1 Int
      | Op2 Int Int

**Comportement actuel :**
- `data TestOp` -> `syntax error in data: '=' manquant`
- `= Op1 Int` -> `error.TypeError`
- `| Op2 Int Int` -> `continuation de garde sans clause precedente`

**Cause :** le parser attend `=` sur la meme ligne que `data X`.

**Workaround :** tout sur une ligne.

    data TestOp = Op1 Int | Op2 Int Int

**Impact :** lecture, ecriture de `data` non triviaux (EffOp a 6
constructeurs sur une seule ligne de 130 caracteres).

**Reference :** docs/spec/examples/http_server.hvn utilise cette
forme multi-lignes.

## Gap 2 -- `|` en debut de ligne

**Reproduction :**

    | Op1 Int

(isole, sans contexte)

**Comportement actuel :**
- `continuation de garde sans clause precedente`

**Cause :** le `|` en debut de ligne est capture par le parser
de gardes alignees (`f x | cond = ...`) avant tout autre
dispatch.

**Lien avec Gap 1 :** dans `data X = A | B | C` multi-lignes, les
`|` de continuation sont captures par les guards.

**Workaround :** eviter le `|` en debut de ligne en contexte
non-guard.

## Gap 3 -- perform (Op args) aplatit  [CORRIGE]

**Corrige le 2026-10-05** (commit af6710b). Trois parsers intervenaient :
- `parse.zig:308` — branche perform detecte S-expr -> un seul Id
- `parse.zig:237` — conversion `let x = expr` wrap expr composee
- `matrix_bridge.zig:178` — branche perform ne depouille plus les parens

`perform (Test 42)` produit maintenant `apply(perform, [apply(Test, [42])])`
sur les trois chemins (REPL direct, let avec parens, let sans parens).

**Reproduction :**

    data EffOp = Test Int
    let op2 = perform (Test 42)
    test "p" : op2 == (Test 42)

**Comportement actuel :**
- `op2 := 42` (l'argument `42`, pas le constructeur)
- `op2 != (Test 42)`

**Cause :** `perform (Test 42)` est parse comme
`apply(perform, [sym("Test"), lit(42)])` -- deux arguments.
Le `perform` historique (`perform "Op" arg`) prenait deux
arguments, et le parser aplatit toutes les S-exprs de la meme
maniere.

**Attendu pour la spec _effects.md section 5 :**
- `perform` doit accepter **un seul** argument qui est un `Id`
- `perform (Test 42)` -> `apply(sym("perform"), [apply(sym("Test"), [42])])`
- Le handler recoit cet `Id`, peut le pattern-matcher.

**Impact :** prerequis de la spec des effets structures. Sans ce
fix, `perform (ReadFile cap path)` retourne `path`, pas
`(ReadFile cap path)`.

**Localisation probable :** parser de S-exprs
(`src/core/parse.zig` ou `src/core/expr_parser.zig`) ou dispatch
`perform` (`src/core/engine_expr.zig:1192`).

**Reference :** docs/spec/_effects.md section 5.

## Note (pas un gap) -- clause 0-pattern

**Reproduction :**

    do_thing = 42
    test "p" : (do_thing) == 42

**Comportement actuel :**
- `clause enregistree pour 'do_thing'`
- `(do_thing) != 42`

**Interpretation :** `f = expr` cree une **clause de fonction a
0 patterns**, pas un binding de valeur. `f` est un symbole non
appele ; sa valeur est la clause elle-meme, pas son resultat.

**Convention :**
- `f args = body` -> fonction (args >= 1)
- `f = body` -> clause 0-pattern, non appelable via `(f)`
- `let x = body` -> binding de valeur, evalue immediatement

**A documenter** dans `docs/COMMANDS.md` ou le book.

**Pas un bug** : c'est un choix (coherent avec Haskell pour les
CAF et avec Prolog pour les faits a 0 argument).

## Corriges recents (hors Gap 1/2/3)

### λ : support etendu
- `λx => body`, `λx -> body` : ajoute le separateur `=>`/`->`
- `λ(x, y) => body` : params entre parens
- `λx y z. body` : multi-params
- Commit `4e606c1`, branche `expr_parser.zig:64-115`

### Clause 0-pattern applicable
- `f = λx. x` puis `f 42` retournait `ArityMismatch`.
- Fix `engine_expr.zig:569-583` : fallback si clause 0-pattern retourne une lambda.
- Commit `6b4650f`.

### Corrige : beta-reduction par substitution AST
- Avant : `f = λx. λy. (+ x y) ; f 3 4` retournait `(lambda y (+ x y))`
  car la beta ne capturait pas l'environnement.
- Fix `expr.zig` (`substSym`) + `engine_expr.zig` (beta recurse sur args).
- Commit `d4e8cd3`.

### Corrige : panic kernel shift/subst
- `prove x + 0 = x by induction on x` faisait exploser le TermPool
  (100k cap, `@panic unreachable`).
- Cause : `shift`/`subst` allouaient systematiquement un nouveau terme,
  meme sans changement.
- Fix `kernel/peano.zig` : court-circuit si les enfants rendent le
  meme index.
- Commit `1283237`.

### Corrige : for...when
- `(for (x <- L) (when P) B)` desugairait en `(filter (λx. (P x)) L)`,
  appliquant P a x en plus.
- Fix `heaven_expr.zig:1656` : `(filter (λx. P) L)`.
- Commit `5652ce9`.

### Bug restant : take masque par le prelude
- `core/std/list.hvn` enregistre `take zero _ = nil` au demarrage.
  Quand l'user redefinit `take zero s = s`, sa clause s'ajoute en
  queue et la clause prelude matche en premier -> `nil`.
- Repro : `take zero s = s` puis `take zero 42` -> `nil` au lieu de `42`.
- Non-regression : `head`, `reverse`, `map`, `filter`, `foldl` sont
  aussi dans `list.hvn` mais **sans clause zero en tete**, donc pas
  touches.
- Zone : `heaven_expr.zig` — `evalEquation` (~1943) ne purge pas les
  clauses prelude. `std_loader.loadAll` (~26) charge `list.hvn` puis
  `stream.hvn`.
- Fix propose (patch pret, non applique) : ajouter `prelude_loading: bool`
  (true pendant init) + `user_redefined_names` set. Au 1er enregistrement
  user d'un nom, purger `num_clauses` + `ctor_arity`. Les clauses
  suivantes (multi-clause) s'appendent normalement.
- Debloque : `verify_book.hvn` 43/43 (2 echecs `take` + `reverse`).

### Bug restant : kanren query
- `query features_parent Alice _` retourne `(query features_parent Alice <?>)` au lieu de `1`.
- Zone : moteur kanren (`src/logic/kanren_expr.zig`).

### Bug restant : REPL for sans parens
- `for (x <- L) B` tape au REPL echoue (UnboundVariable), alors que
  `(for (x <- L) B)` ou la meme ligne dans un fichier `.hvn` marche.
- Zone : `heaven_expr.zig` wrapper "forme composee sans parentheses" (3143).

### Bug restant : fact 5 et les equations
- `fact 0 = 1 ; fact n = n * fact (n - 1) ; fact 5` retourne
  `✓ fact 5 (0 arg(s))` au lieu de `120`.
- Zone : `defs.zig` (evalEquation) vs `parse.zig`.

## Priorite

| Gap | Impact | Effort estime |
|---|---|---|
| Gap 3 (`perform` structure) | ✅ Corrige | — |
| Gap 1 (`data` multi-lignes) | Confort de lecture | 1 session |
| Gap 2 (`|` en tete) | Lie a Gap 1 | 1 session |
| Note (clause 0-pattern) | Documentation | 30 min |

Gap 3 doit etre traite en premier : c'est le prerequis des effets
structures, et donc de `eval.hvn` et du serveur HTTP.

## Etat

| Gap | Documente | Corrige |
|---|---|---|
| 1 | oui | non (WIP externe) |
| 2 | oui | non (WIP externe) |
| 3 | oui | oui (af6710b) |
| Note 0-pattern | oui | n/a |

