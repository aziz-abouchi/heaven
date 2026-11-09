# Bug : reference qualifiee a une valeur de module ne se resout pas (2026-11-09)

**Statut** : identifie, non corrige.
**Impact** : contourne dans lib/tool_registry.hvn (registry_builtin
expose comme fonction zero-arg).
**Contournement** : exposer les valeurs de module comme fonctions
zero-arg (registry_builtin _ = ... au lieu de registry_builtin = ...).

## Symptome

`TR.registry_count TR.registry_builtin` ne renvoie ni 0, ni 1, ni 2,
ni 3, ni true, ni false, ni "". En revanche,
`TR.registry_count (TR.TLCons (TR.Tool ...) TR.TLNil)` (valeur
construite inline) marche, et `TR.registry_has "check"` (appel de
fonction qualifie) marche aussi.

## Cause racine

- `TR.registry_count` : reference qualifiee a une **fonction** -> OK.
- `TR.registry_has`   : reference qualifiee a une **fonction** -> OK.
- `TR.registry_builtin` : reference qualifiee a une **valeur**
  (binding top-level sans argument) -> KO.

L'evaluateur ne resout pas cross-module les valeurs top-level. La
valeur retournee n'est pas la structure TLCons attendue, donc
registry_count ne matche ni TLNil ni TLCons et retourne un resultat
non-standard (ni int, ni bool, ni string).

## Contournement

Exposer la valeur comme fonction zero-arg :

    -- AVANT (KO cross-module)
    registry_builtin = (TLCons ...)

    -- APRES (OK cross-module)
    registry_builtin _ = (TLCons ...)

    -- usage cross-module :
    (TR.registry_count (TR.registry_builtin 0))

Coherent avec lib/mcp/ qui expose toutes ses "constantes" comme
fonctions zero-arg (q _ = ..., init_result _ = ..., tools_list_inner _ = ...).

## Priorite

Moyenne. Un fix propre demanderait de tracer la resolution des
Symboles qualifies dans heaven_expr.zig (evalSym ou similaire) et
d'etendre la reecriture aux valeurs de module, pas seulement aux
fonctions. Non bloquant pour le registre, MCP, UTCP.
