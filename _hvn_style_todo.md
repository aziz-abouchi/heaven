# Style .hvn -- S-expr residuels (2026-10-20)

## Corrige cette session
- stdlib/mpst.hvn:78,80 (project_side) -- `(if (= ...))` -> `if ... == ... then`

## Pre-existant (pas de cette session, a corriger un jour)
- stdlib/mpst.hvn:35,38 (check) -- `(if (= l t) ...)`
- stdlib/ontology.hvn:22,37 -- `(+ 1 (kb_size rest))`, `(+ 1 (kb_count ...))`
- tests/test_array.hvn (13 tests) -- `(let a ...)`
- tests/test_continuations.hvn -- `(let ...)`, `(if ...)`, `(lambda k -> ...)`

## Regle
Les operateurs (`+ - * / % = != < > <= >=`) et keywords (`if let lambda`)
doivent etre en INFIXE. Les constructeurs (`cons`, `Some`, `Kcons`) ont des
parens obligatoires pour les PATTERNS, mais en EXPRESSION ils suivent la
regle normale : `cons x xs` (pas de parens).

## Non-objectif
- Magics 0-arg : `(target_os)`, `(@budget_left)` -- S-expr obligatoire.
- Tuples : `(a, b)` -- S-expr.
- Patterns constructeurs : `f (Kcons x xs) = ...` -- parens obligatoires.
