# Bug : noms qualifiés dans les branches d'un if (2026-11-09)

Statut : corrigé (commit 55430bf)
Fichier : src/core/expr.zig, Lexer.next()
Voir : _style_infix.md, _h1_qualified_sym.md

## Symptôme

Toute expression `if cond then (Module.Membre ...) else ...` — en
infixe pur comme en S-expr keyword — produisait un résultat faux
sur les DEUX branches, y compris la branche littérale.

    find n = if (= n 0) then (R.Ok 1) else 2
      attendu : find 0 -> (R.Ok 1), find 5 -> 2
      avant   : symbole inconnu, symbole inconnu

## Cause racine

Le lexer de `nativeToSExpr` ne reconnaissait pas le point dans les
identifiants. `R.Ok` produisait un token `ident("R")` et une erreur
de syntaxe sur le point.

Cette erreur déclenchait le fallback de `parseSExpr`
(`src/core/expr_parser.zig`, ~ligne 12) qui délègue à
`parseExpression` sur la même chaîne, recursant jusqu'à
`parse_depth > 500`, puis retourne un symbole de la chaîne brute.
L'`if` entier devient un symbole inconnu.

## Fix

Dans `Lexer.next()`, boucler sur `.ident` après l'identifiant
initial. Voir commit `55430bf`.

Invariants préservés : `3.14` reste un token `num` ; `R.` (point
final) reste `InvalidSyntax` ; lambda ASCII `\x.body` non affecté ;
`A.B.C` produit un seul `ident("A.B.C")`.

## Non-régression

`tests/final.hvn` : 20/20 (`if` infixe sans qualification, `if`
S-expr pur, lambdas, workaround `ok`/`err`).

## Hors-scope

`(== a b)`, `(&& a b)`, `(|| a b)` en préfixe restent non supportés
(absents de la table `magics` de `src/core/engine_expr.zig`).
Non bloquant : la politique du langage est l'infixe systématique
(voir `_style_infix.md`).
