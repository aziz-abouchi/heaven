# Bug : Heaven.integrate sémantiquement faux (2026-11-09)

**Statut** : identifié, non corrigé.
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
