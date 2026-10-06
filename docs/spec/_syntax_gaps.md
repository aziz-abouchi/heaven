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

### Corrige : take masque par le prelude
- **Corrige le 2026-10-06.** `core/std/list.hvn` enregistrait
  `take zero _ = nil` au demarrage, masquant les clauses user
  ajoutees plus tard.
- Fix : flag `prelude_loading` (true pendant init, false apres) +
  set `user_redefined_names`. Au premier enregistrement user d'un nom,
  purge `num_clauses` + `ctor_arity` ; les clauses suivantes s'appendent.
- Debloque : `verify_book.hvn` 43/43 (vs 41/43).

### Bug restant : kanren query
- `query features_parent Alice _` retourne `(query features_parent Alice <?>)` au lieu de `1`.
- Zone : moteur kanren (`src/logic/kanren_expr.zig`).

### Corrige : REPL for sans parens
- **Corrige le 2026-10-06** (commit `f20568a`). `for (x <- L) B` tape
  au REPL n'etait pas detecte par le dispatch qui cherchait `(for `.
- Fix : detection de `for ` en tete, wrapper en `(for ...)` avant
  passage a `desugarFor`.

### Pas un bug : fact est reserve
- `fact 0 = 1 ; fact n = ... ; fact 5` -> `✓ fact 5 (0 arg(s))`.
- **Cause** : `fact` est intercepte par le pipeline kanren
  (`evalFact`, `heaven_expr.zig:1017`). Une ligne `fact X` sans `= `
  ajoute un fait au KB, elle ne fait pas un appel de fonction.
- **Resolution** : le book `04-recursion.md` utilisait `fact`, corrige
  en `fac` (utilise par le README). Aucune modification du code.
- **A documenter** : la liste des mots reserves (`fact`, `query`,
  `data`, `sig`, `theorem`, `prove`, `module`, `import`).

## Ecarts documentaires (non techniques)

Ces points ne sont pas des bugs du langage mais des divergences entre
la doc et le code, releves le 2026-10-06.

### README : honnetete factuelle
- **Corrige** (commit `6d986c7`) :
  - Accroche : QTT vise une strategie memoire sans GC, pas un GC effectif.
  - Acteurs : sequentiels aujourd'hui, distribues a terme.
  - Point 4 marque `[TARGET]`.
  - Tests : 47 tests Heaven (fichiers `.hvn`), pas 95.

### STATUS : lambda fleche
- **Corrige** : `λx -> body`, `λ(x,y) =>`, `λx y z.` supportes depuis
  `4e606c1` (la doc les donnait absents).

### GRAMMAR.md : "miroir exact"
- **Corrige** : le doc pretendait etre genere depuis `grammar.js`.
  Ecrit a la main. Reformule : `grammar.js` fait foi.

### Reste a auditer
- `HEAVEN_ARCHITECTURE_2026.md` (3 mois sans MAJ)
- `PROMPT_CONTINUITE.md` (16 KB, 2 oct. — pas resynchronise apres les
  6 fixes du 2026-10-05)
- `docs/book/src/10-under-the-hood.md` (utilise `data List<a>`, non
  supporte par le REPL — voir Gap "evalDataDecl" ci-dessous)
- `docs/book/src/02`, `03` : idem pour `List<a>`

### Gap ouvert : evalDataDecl generiques `<a>` (partiel)
- **Nom + params** : CORRIGE (commit local). `data List<a> = ...` donne
  maintenant `List` avec `1 param`, `data Pair<a, b>` donne `2 param`,
  `data Box<a : Type>` donne `1 param`. Les syntaxes `MyList a` et
  `Vec (n : Nat)` sont preservees.
- **Corps** : RESTE A FAIRE. Dans `Cons a (List<a>)`, l'argument
  `List<a>` est traite comme symbole litteral, pas comme
  `apply(List, [a])`. Impact : le TypeChecker ne peut pas verifier
  les usages generiques dans les constructeurs.
- **Tree-sitter** : accepte `<a>` depuis la regen du `.so`
  (`make` dans `vendor/tree-sitter-heaven/`).

### Bug : codegen_c non migre -> :toc casse
- `:toc <expr>` au REPL remonte `error.ArityMismatch`.
- Cause : `codegen_c.generate` (src/codegen/c.zig) est un stub
  `"/* codegen: not yet migrated to Expr */"`. Le vrai chemin
  passe par `Commands.toC` -> `format_ops.toC` -> `codegen_c`,
  qui attend des expressions pures mais recoit un `.bind`.
- Avant le fix des stubs (commit precedent), `:toc` retournait
  `"// stub"` — il ne marchait pas non plus, il mentait.
- Impact : faible. Les backends utilisables sont QBE et WASM
  (`compile-qbe`, `compile-wasm`). `:toc` est legacy.
- Fix possible : soit migrer `codegen_c` vers Expr (chantier),
  soit retirer `:toc` du shell (10 min).

### Cibles cross-compile : support reel

| Cible | Etat | Raison |
|---|---|---|
| `x86_64-linux` | ✅ | cible native |
| `x86_64-macos` | ✅ | POSIX compatible |
| `wasm32-freestanding` | ✅ | routing vers wasm.zig |
| `wasm32-wasi` | ⚠️ | meme code que freestanding (pas de libc WASI) |
| `aarch64-macos` | ❌ | TCC arm64 incomplet + code Linux-only |
| `x86_64-windows` | ❌ | TCC non compile sur Windows |

Avant la dedup (commit precedent), `aarch64_macos.zig` existait
mais etait byte-identique a `x86_64_linux.zig` (`posix.fork`,
`/proc/self/exe`). La cible n'a donc **jamais compile** sur macOS.

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

