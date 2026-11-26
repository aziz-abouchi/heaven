# Bug : Heaven.integrate sémantiquement faux (2026-11-09)

**Statut** : RÉSOLU (2026-11-26, commit `b615f69`).
**Impact** : `heaven_integrate` MCP retourne une formule fausse mais
plausible. Un utilisateur (ou un LLM) peut l'accepter comme preuve.

## Symptôme

    > heaven_integrate "x^2" "x"
    (x^2 * x) + C

Attendu : `(x^3 / 3) + C` (ou `x^3/3 + C`).

## Cause probable

`Heaven.integrate` (src/core/heaven_expr.zig:3261) fait
`derive` inversé naïf ou réutilise un pattern de multiplication
(`x^n * x`) au lieu de la règle puissance `x^n -> x^(n+1)/(n+1)`.

## À tracer

- src/core/heaven_expr.zig:3261 `integrate` (règle x^n)
- src/core/math.zig (si la règle est externalisée)

## Priorité

Moyenne-basse. Non bloquant pour le registre / MCP / UTCP. Session
dédiée (math symbolique). Contournable via `heaven_derive` + vérif
manuelle en attendant.


---

## Resolution (2026-11-26, commit `b615f69`)

`Heaven.integrate` corrige : `integrate("x^2", "x")` retourne
`x^3/3`. Le resultat est rendu par `integrateIdHeavenExpr` qui
strippe le suffixe ` + C` puis `parseExpression`.

`Heaven.solve("x^2 - 4", "x")` retourne les racines `2` et `-2`
(format infixe encore imparfait, commit dedie a prevoir).

Expose dans le shell et le REPL via :
- vtable : `integrateId` / `solveId` / `expandId` (`engine_expr.zig`)
- backend : `integrateIdHeavenExpr` / `solveIdHeavenExpr` / `expandIdHeavenExpr` (`heaven_expr.zig`)
- shell : `cmdExpand` / `cmdIntegrate` / `cmdSolve` (`commands.zig`)

Test manuel :
    echo 'integrate(x^2)' | heaven --eval-file /dev/stdin
    # -> (/ (^ x 3) 3)
