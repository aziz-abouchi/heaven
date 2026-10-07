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

### Limitation : autofab/JIT est x86_64-only
- `src/runtime/autofab.zig` utilise l'API JIT de libtcc
  (`tcc_new`, `tcc_compile_string`, `tcc_relocate`, `tcc_add_symbol`,
  `tcc_get_symbol`) pour compiler et executer du C en memoire.
- TCC ne compile que sur x86_64-linux/macos. Sur les autres cibles,
  `tcc_stub.c` retourne NULL -> `error.TccInitFailed`.
- Autofab est utilise par : `main.zig`, `runtime/heaven.zig`
  (5 sites), `shell/init.zig`, `vessel/bridge.zig`.
- **Impact** : sur aarch64-macos, wasm32-*, x86_64-windows, les
  commandes qui passent par autofab (forge/JIT) echouent
  proprement. Le reste du langage fonctionne.

### Chantier futur : remplacer TCC
- Candidats JIT multi-plateforme : Cranelift (Apache 2.0, Rust),
  libgccjit (GPL), LLVM ORC (Apache 2.0).
- Contrainte : `tcc_add_symbol` (injection de symboles natifs) doit
  avoir un equivalent. Les trois candidats le supportent.
- Effort : 2-4 sessions. Pas urgent.

### Etat : Prolog (moteur logique separe)

`src/runtime/prolog.zig` (308 LOC) est un moteur Prolog distinct du
kanren (`src/logic/kanren_expr.zig`).

**Caracteristiques :**
- Backend : `Matrix` (pas `Store`) — depend de l'archi en cours
  de depreciation (voir `_vessel_decouple.md`, D9).
- Aucun mot-cle REPL : pas de `?-`. Pas exposable au shell.
- Aucun test : ni unitaire Zig, ni `.hvn`.
- Usage reel : seul `:explain` (`cmdExplain`) interroge le KB Prolog.

**Statut : expose au REPL, fonctionnel.**
- `:p-fact pred(args)` : ajoute un fait.
- `:p-rule head(args) :- b1, b2` : ajoute une regle Horn.
- `?- pred(args)` : requete (goal).
- `?- pred(args, X)` : requete avec variable, affiche `X = value`.
- Backtracking : plusieurs solutions affichees ligne par ligne.
- Dedup memoire : `PrologEngine.deinit` libere pred + args.

**Limites restantes** :
- Pas de recursion (profondeur max 30, cap 20 solutions).
- Pas de fichier `.pl` via `:load`.
- Backend reste Matrix (D9 futur).

**Chantier futur** : reecrire sur `Store` pour supprimer la
dependance Matrix (D9).

### Doc : doctests book (12 corrections, 6 residus)

`scripts/doctest.py` rejoue les 193 blocs `heaven> X` du book et
signale les erreurs d'eval. Corrections faites (commit 8dd0c19) :

- `data Stream` + `mapStream`/`inc`/`dbl` ajoutes avant usage (01, 05, 07)
- `data MyList` + `data Maybe` ajoutes avant usage (04)
- `name Unknown`, `head Empty`, `inconnu 42` marques skip (pedagogiques)
- `accumulateur`, `import util.hvn` marques skip (illustratifs)
- `prove ... by {` skippe (interactif)
- `B-erreurs.md` entier en `skip-file` (chapitre pedagogique)

Residus (6 erreurs) : cascades autour de streams/zip dans 05 et 07,
`strict on` + U.public dans 11. Exemples qui dependent d'un contexte
que le doctest lineaire ne reproduit pas. Acceptes tels quels :
- CI utilise `--warn-only` (informe sans bloquer).
- Un futur passage peut les traiter individuellement.

### Feature : alias de type (`type Nom = Cible`)

**Implemente** :
- `type Nom = Cible` enregistre un alias (commit ef743b0).
- `type Nom` retourne la cible.
- Redefinition : derniere gagne.
- Resolution dans `sig` (commit suivant) : `sig f : Nom -> Int`
  est enregistre comme `String -> Int`. Alias chaine (A->B->Int)
  fonctionne par composition.

**Non implemente (chantier)** :
- Resolution dans les arguments de type composes (`List<Nom>`
  reste `List<Nom>`) et dans les expressions.
- Resolution dans `data` (`data D = C Nom` reste tel quel).
- Verification que la cible est un type valide : `type X = bidule`
  est accepte.
- Effort : ~2h pour etendre `resolveAliasesInType` a d'autres
  sites d'appel. Risque faible une fois le pattern valide.

### Knowledge : Turtle fonctionnel

**Implemente** (commit suivant) :
- `:load <file.ttl>` charge via `triple_store.addTurtle` (TurtleParser).
- `:triples` liste, `:triple-count` compte.
- `:triple-query <subject-iri>` requete par sujet.

**Syntaxe supportee** : `@prefix`, triples `<s> <p> <o> .`, prefixes
(`ex:Alice`), litteraux, blank nodes, `;` (predicats multiples),
`,` (objets multiples), `a` (raccourci `rdf:type`), collections RDF
(`( i1 i2 )` sucrees en `rdf:first`/`rdf:rest`/`rdf:nil`).

**A tester / completer** :
- Reification (`<< s p o >>`)
- Annotations `{| ... |}`
- Litteraux multi-lignes (`"""..."""`)
- Requetes par predicat (`:triple-pred`) ou par objet.
- Verification que les iris completes sont bien resolues (avec `<...>`).

### Corrige : import qualified (alias) + patterns

**Corrige le 2026-10-08** (commits `098f90c` + `a3698a7`). Repro originale :

    # /tmp/q2.hvn
    data MyBool = MyTrue | MyFalse
    myNot MyTrue = MyFalse
    myNot MyFalse = MyTrue

    # /tmp/q3.hvn
    import "/tmp/q2.hvn" as Q
    (Q.myNot Q.MyTrue)       # -> error.ArityMismatch

**Cause** : quand l'import alias cree les clauses sous `Q.myNot`,
les **patterns** restent unqualified (`MyTrue`). L'appel passe
`Q.MyTrue`, donc `sym("MyTrue") != sym("Q.MyTrue")` dans le pattern
match -> aucun matche.

**Fonctionne** : import sans alias (`import 'lib/prelude.hvn'` puis
`(not True)` -> `False`).

**Fix applique** : helper `symMatchesPattern(store, a, b)` dans
`engine_expr.zig` (avant `evalMagic`). Compare la partie locale
apres le dernier `.` si un seul cote est qualifie.

**Limite connue** : `A.X` vs `B.X` (les deux qualifies, prefixes
differents) restent refuses — c'est ambigu.

**Impact** : les imports qualifies (`import ... as Q`) peuvent
maintenant utiliser du pattern matching sur constructeurs 0-arity
(`Q.myNot Q.MyTrue` fonctionne).

**Fix complementaire (a3698a7)** : deux bugs distincts corriges
en cascade :

1. **Constructeurs non aliaser sous M.Ctor en mode normal**.
   `evalDataDecl` n'enregistrait `M.ctor` qu'en `strict_module`.
   Resultat : `import "x.hvn" as D` puis `D.Cons2` -> `UnknownSymbol`.
   Fix : enregistrer aussi `M.Ctor` si `current_module != null`.

2. **Patterns imbriques pas tolerants a la qualification**.
   La branche `.apply` du pattern match comparait les tetes de ctor
   avec `exprStructuralEq` strict. Fix : helper `patternArgMatches`
   qui bascule sur `symMatchesPattern` si les deux sont des `sym`.

**Test** : `import "deep2b.hvn" as D` puis
`head3 (D.Cons2 42 D.Nil2)` -> `42`.

### Corrige : variables dans un pattern imbrique (depth >= 2)

**Corrige le 2026-10-08** (commit `matchPatternDeep`). Repro
originale :

    data Iri = IAlice | IKnows
    data Term = TIri Iri
    data Triple = MkTriple Term Term Term
    data Kb = Knil | Kcons Triple Kb

    isAlice (MkTriple (TIri IAlice) _ _) = 1        -- OK (wildcards)
    isAlice _ = 0

    extract (Kcons (MkTriple (TIri IAlice) p o) rest) = p    -- KO
    extract _ = 0

    (extract (Kcons (MkTriple (TIri IAlice) (TIri IKnows) (TIri IAlice)) Knil))

**Comportement** : `error.ArityMismatch`. La clause ne matche pas.

**Cause** : dans `engine_expr.zig`, la branche `.apply` du pattern
match utilise `patternArgMatches(pp, aa)` pour les sous-patterns. Si
les deux sont des `apply`, il tombe sur `exprStructuralEq` qui
compare **litteralement** les args. Or le pattern contient `p` et `o`
(variables), l'arg contient `IKnows` et `IBob` -> jamais egaux.

**Fix applique** : `matchPatternDeep`, methode recursive de
`Engine` qui bascule en pattern matching pour chaque sous-pattern
(binder, ctor 0-arity, lit, apply). Recoit `new_env` +
`bound_syms`/`bound_count` pour tracker les variables liees
(cleanup TCO).

La boucle outer du matching est reduite a 8 lignes.

**Test** :
    extract (Kcons (MkTriple (TIri IAlice) p o) rest) = p
    (extract (Kcons (MkTriple (TIri IAlice) (TIri IKnows) _) _))
    -> (TIri IKnows)

**Impact** : le code RDF/parsing peut ecrire des filtres directs
sans helpers a wildcards. `examples/pure/rdf.hvn` simplifie en
consequence.

### Bug : continuation multi-ligne (equation)

**Statut** : non resolu, documente 2026-10-08.

Repro :

    demoKb Demo =
        Kcons (MkTriple (TIri IAlice) (TIri IKnows) (TIri IBob))
        Knil

**Comportement** : `UnknownSymbol` puis `ArityMismatch`. Le
statement est coupe en deux apres le `=`.

**Cause** : il y a **3 splitters independants** de statements qui
ne gerent pas la continuation multi-ligne :
- `test_runner.zig::splitStatements` (charge `--run-test`, `--eval-file`)
- `import.zig::evalImport` (inline, boucle `splitScalar(u8, source, '\n')`)
- Le REPL (`interactive.zig::readLine` lit ligne par ligne)

**Tentatives de fix** :
- **Indentation seule** (ligne suivante plus indentee) : faux
  positifs sur les fichiers de test (`test "x": expr` suivi d'une
  ligne indentee = un nouveau statement).
- **Fin de ligne `=`** : gere le 1er saut mais pas les suivants
  (`demoKb Demo =\n    Kcons ...\n    Knil` a 2 continuations).
- **Indentation type Python** (stmt_indent vs next_indent) :
  complexe, a introduit des regressions dans `import.zig`.

**Workaround** : tout sur une ligne par equation. `examples/pure/rdf.hvn`
est ecrit ainsi.

**Vraie solution (chantier)** :
- Factoriser un seul splitteur dans un module commun
  (`src/core/split_stmt.zig`).
- Regle complete : continuation si
  - parens () non fermes, OU
  - braces {} non fermes, OU
  - la ligne precedente se termine par `=` (equation multi-ligne).
- PAS d'heuristique d'indentation : elle casse les tests.
- Tests : rejouer les 37 fichiers de `tests/` + `core/test_suite.hvn`
  + `examples/pure/`.

**Impact** : lisibilite des gros fichiers `.hvn` uniquement.

### Bug : non-linear pattern matching

**Statut** : non resolu, documente 2026-10-08.

Repro :

    findObjects _ _ Knil = Knil
    findObjects s p (Kcons (MkTriple s p o) rest) = Kcons o (findObjects s p rest)
    findObjects s p (Kcons _ rest) = findObjects s p rest

**Comportement** : `error.ArityMismatch`. La 2e clause ne matche pas.

**Cause** : `matchPatternDeep` traite chaque occurrence d'une variable
comme un **nouveau binding**, sans verifier si elle a deja ete liee
dans le meme pattern. Un pattern `(Kcons (MkTriple s p o) rest)` avec
deux occurrences de `s` (au niveau `MkTriple` et dans la recursion)
lie la 2e occurrence a une autre valeur.

**Tentative** : ajouter un check `new_env.get(sym)` avant le binding.
Probleme : `new_env` contient une **copie du `caller_env`** (fait ligne
`new_env.put(entry.key_ptr.*, entry.value_ptr.*)` au debut du dispatch).
Donc un pattern var qui a le meme nom qu'une variable du caller
matcherait cette variable -> 5+ fichiers de tests cassent.

**Vraie solution (chantier)** :
- Tracker les bindings **du pattern courant uniquement**, pas dans
  `new_env` global.
- Utiliser une structure separee (map pattern-local ou liste) qui
  survit aux recursions de `matchPatternDeep` mais est nettoyee a la
  fin du match.
- Interagir correctement avec TCO (chaque iteration reset les
  bindings).
- Ne PAS toucher `new_env` pour le tracking ; `new_env` reste le
  mecanisme de dispatch.

**Workaround** : eviter le non-linear matching. Exemple pour
`findObjects` :

    findObjects _ _ Knil = Knil
    findObjects s p (Kcons t rest) =
        consIfMatch (tripleMatches s p t) t (findObjects s p rest)
    findObjects s p (Kcons _ rest) = findObjects s p rest

Avec `tripleMatches` qui teste le triple (3 patterns a wildcards ou
variables simples).

**Impact** : requetes RDF naturelles impossibles. Mais contournable
avec des helpers.

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

