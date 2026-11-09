# Style : notation infixe par defaut

**Date** : 2026-10-15
**Statut** : convention active.

## Regle

Dans tout code Heaven nouveau (specs, book, stdlib, core,
roadmap), **l'infixe est la forme par defaut**.

## Formes infixes preferes

| Prefere (infixe) | Toleere (prefixe) |
|---|---|
| `a + b` | `(+ a b)` |
| `a - b` | `(- a b)` |
| `a * b` | `(* a b)` |
| `a / b` | `(/ a b)` |
| `a == b` | `(= a b)` |
| `a != b` | `(!= a b)` |
| `a < b` | `(< a b)` |
| `a > b` | `(> a b)` |
| `a <= b` | `(<= a b)` |
| `a >= b` | `(>= a b)` |
| `let x = 1 in body` | `(let x 1 body)` |
| `if p then a else b` | `(if p a b)` |

## Formes qui restent prefixe

Les appels de fonction multi-argument gardent la forme prefixe,
pour eviter l'ambiguite :

    f x y           -- OK
    (f x y)         -- aussi OK
    string_concat a b

Les magics aussi :

    @net_listen cap port
    @budget_left

## Exceptions

- Les pattern-matching en clause de fonction : `f (cons x xs) = ...`
  (le constructeur en position d'argument est prefixe).
- Les tuples : `(a, b)` — la virgule separe.
- Les records : `{ x: 1, y: 2 }`.

## Formes strictement proscrites (2026-11-09)

Certaines formes prefixe ne sont pas acceptees par l'evaluateur et
produisent error.UnknownSymbol :

- (== a b)  -> utiliser a == b ou (= a b)
- (&& a b)  -> utiliser a && b ou (and a b)
- (|| a b)  -> utiliser a || b ou (or a b)

## Branches de if et noms qualifies (2026-11-09)

Une branche then ou else peut contenir un nom qualifie Module.membre.
Le lexer de nativeToSExpr accepte les points interieurs (R.Ok, M.f,
A.B.C) depuis le commit 55430bf.

Forme valide :

    find n = if (n == 0) then (R.Ok 1) else (R.Err "no")

## Application immediate

- **Book chapitres 19-23** : a reviser (utiliser infixe partout).
- **Specs recentes** : a reviser.
- **Core/stdlib** : garder prefixe (compat, tests existants).
- **Nouveau code** : infixe.

## Reference

Exemples de tests qui marchent en infixe : `tests/test_parser_literals.hvn`.
