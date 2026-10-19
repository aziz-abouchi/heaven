<!-- HEAVEN:if-sexpr-bug -->
# Bug : if en S-expr imbriqué dans une branche (2026-10-19)

## Symptome

    f n = if (= n 0) then (if (= n 1) then 1 else 2) else 3

Echoue silencieusement (aucun test liste) ou retourne une valeur
fausse. Cause : `parseIfExpr` (keyword) appelle `parseExpr(0)` pour
la branche then. `parseExpr(0)` voit `(if ...)`, appelle
`parsePrimary` qui detecte `if` et rappelle `parseIfExpr`, qui
exige `then` — mais c'est la forme S-expr `(if c a b)`, pas keyword.

Resultat : InvalidSyntax propagee en silence, tests non executes.

## Perimetre

- `if c then a else b` (keyword, top-level) : OK.
- `(if c a b)` (S-expr, top-level) : OK.
- `if c then (if c2 a2 b2) else b` (S-expr dans then) : KO.
- `if c then a else (if c2 a2 b2)` (S-expr dans else) : probablement KO.
- `(if c then a else b)` (mixte) : KO (ArityMismatch, 5 args).

## Tentatives echouees

1. Ajouter `if` a `is_prefix_op` dans `parsePrimary` + cas special 3-args.
   Resultat : dangle 4/4 -> 2/4. Regression.
2. Retirer le mode S-expr de `parseIfExpr`.
   Resultat : idem, regression.

## Piste pour un vrai fix

Le parser a **trois** points d'entree pour `if` :
1. `parsePrimary` (S-expr via `(`)
2. `parseIfExpr` (keyword via `if`)
3. `def_body` (keyword, ajoute par bcecc94 dans heaven_parse.hvn)

Il faut **unifier** ces trois chemins ou au moins clarifier le contrat.
Option : `parsePrimary` sur `(` doit d'abord regarder si le premier
token est `if` **suivi de `then`** (keyword dans parens) ou non
(S-expr pur). Deux branches, deux comportements.

Effort : 1 session (recon serieuse + tests exhaustifs).

## Tests de regression a ajouter

    test "if_kw": (f 1) == ...  -- keyword top-level
    test "if_sexpr": (g 1) == ...  -- S-expr top-level
    test "if_then_sexpr": ...  -- S-expr dans then
    test "if_else_sexpr": ...  -- S-expr dans else
    test "if_nested_deep": ...  -- 3 niveaux

## Bloque

- JSON V1 : strings, arrays, objects (json_str_end, json_parse_str
  utilisent des if S-expr dans les branches).
- HTTP body parser.
- Metacircularite #6 (sous-if parenthese).

## Contournement actuel

Extraire les sous-ifs en helpers keyword top-level. Utilise dans
`stdlib/json_parse.hvn` (json_digit_or_stop, json_digit_cont).
Verbeux mais fonctionnel.


## RESOLU (2026-10-19, commit b63014a)

Le fix `parsePrimary` gère maintenant `(if ...)` en deux formes
(S-expr pur et keyword-in-parens) avec `parsePrimary` par arg
(pas `parseExpr`).

**Tests** : tests/test_if_sexpr.hvn (21 cas : keyword top,
S-expr top, S-expr dans then/else, keyword-in-parens, triple).
Non-régression : test_parser 22/22, test_eval 13/13,
test_meta_if 7/7, test_meta_data 5/5, test_json_parse 11/11,
test-files 0 fail. 5 commandes : OK/0/0/0.

**Débloqué** : JSON V1 (strings/arrays/objects), HTTP body,
métacircularité #6.

**Note** : un autre bug a été découvert en tentant JSON V1 —
`let x = (JArr JVNil) in (if (= x x) 1 0)` échoue alors que
`f (ACons 7 ANil)` marche. C'est probablement l'égalité `=` sur
constructeur à argument constructeur, OU le `let` avec
constructeur. Bug distinct, non tracé.
