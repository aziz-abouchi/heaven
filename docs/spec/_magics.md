# Magics d'algebre symbolique : expand / integrate / solve

**Date** : 2026-11-26
**Statut** : LIVRE (commit `b615f69`)

## Motivation

Heaven expose trois operations d'algebre symbolique dans le shell et
le REPL. Elles prennent une expression, la passent au backend
`Heaven.*`, et rendent un AST re-parse, affiche en infixe par
`store.formatInfix`.

## Signatures

| Magic | Arity | Entree | Sortie (AST) | Exemple |
|---|---|---|---|---|
| `expand(<expr>)` | 1 | AST polynomiale | AST developpee | `expand((x+1)^2)` -> `(+ (+ (^ x 2) (* 2 x)) 1)` |
| `integrate(<expr>)` | 1 | AST en `x` | primitive, suffixe `+ C` strippe | `integrate(x^2)` -> `(/ (^ x 3) 3)` |
| `solve(<expr>)` | 1 | AST polynomiale en `x` | racines (eq/disjonction) | `solve(x^2 - 4)` -> `2` et `-2` |

Variable `x` hardcodee (`var_name = "x"` dans `evalMagic`).

## Grammaire

    magic-expr  ::= "(" magic-name SP expr ")"
    magic-name  ::= "expand" | "integrate" | "solve"

L'argument doit etre une expression parsable. Dans `evalMagic`,
l'argument est d'abord evalue en `Id`, puis stringifie via
`expr.toString` avant d'etre passe a la vtable.

## Erreurs

- `ArityMismatch` — nombre d'arguments != 1.
- `TypeError` — echec de `parseExpression` ou du backend
  (`Heaven.integrate/solve/expand`).
- `OutOfMemory` — propagation standard.

## Implementation (3 couches)

1. **vtable** (`src/core/engine_expr.zig`) — champs `integrateId` /
   `solveId` / `expandId` ; stubs `testIntegrate` / `testSolve` /
   `testExpand` pour `testHeavenVTable`.
2. **backend** (`src/core/heaven_expr.zig`) — `integrateIdHeavenExpr` /
   `solveIdHeavenExpr` / `expandIdHeavenExpr` : wrappent
   `Heaven.integrate/solve/expand`, strippent le suffixe `" + C"`
   (integrate), `parseExpression` du resultat.
3. **shell** (`src/runtime/shell/commands.zig`) — `cmdExpand` /
   `cmdIntegrate` / `cmdSolve` : appellent le backend, re-parsent,
   formatent en infixe.

## Test manuel

    echo 'expand((x+1)^2)' | heaven --eval-file /dev/stdin
    # -> (+ (+ (^ x 2) (* 2 x)) 1)

    echo 'integrate(x^2)' | heaven --eval-file /dev/stdin
    # -> (/ (^ x 3) 3)

    echo 'solve(x^2 - 4)' | heaven --eval-file /dev/stdin
    # -> (= (= x (2 ou x)) -2)   [format a corriger]

## Non-objectifs (v1)

- Derivee : deja exposee via `deriveId` (magic `derive`).
- Polynomes multivaries : seul `x` supporte.
- Format `solve` : correction cosmetique prevue dans un commit dedie.

## References

- `_integrate_bug.md` — bug historique, resolu par `b615f69`.
- `_algebras.md` — contexte algebrique.
- README section "Magic operations".
