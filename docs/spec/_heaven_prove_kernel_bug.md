# Bug : Heaven.evalProve — faux positif "Usage:" et panic "Invalid free" (2026-11-09)

**Statut** : **corrigé 2026-11-10** (commit à venir).
**Impact** : `heaven_prove` MCP expose maintenant les deux modes —
kernel (`prove NAME by { tactics }`) et sémantique (`a == b`).

## Résolution 2026-11-10

Trois patches appliqués :

1. `src/core/commands/proofs.zig:260` : `return error.InvalidSyntax`
   au lieu de `allocator.dupe(u8, "Usage: prove …")`.
2. `src/core/heaven_expr.zig` `evalProve` : strip le préfixe `"prove "`
   avant de chercher le nom du théorème (le caller MCP passe la forme
   complète, le parser interne attend le nom seul).
3. `src/runtime/mcp_server.zig` `callTool` : réactive la branche
   kernel avant le fallback sémantique.

Note : le panic `Invalid free` (mentionné dans Symptôme 2 plus bas)
avait déjà été éliminé par `5d239bd` (dupe sur la string statique).
Le présent fix rétablit l'usage effectif du kernel.

Vérifié : `theorem t1 : x + 0 = x` + `prove t1 by { simplify }` via
MCP retourne `{"proved":true,"method":"kernel","certificate":"✓ [t1] proved (tactics)"}`.

## Historique (avant fix)

**Statut** : identifié, contourné dans mcp_server.zig (priorité 2).
**Impact** : `heaven_prove` MCP se limitait à l'égalité sémantique
`a == b`. Le kernel (`prove name by { … }`) était désactivé.

## Symptôme 1 — faux positif sur entrée invalide

`Heaven.evalProve("1+1")` retourne `Ok("Usage: prove [name] by <method> [on <var>]")`
au lieu d'une erreur. Le message d'aide est traité comme un certificat de
preuve, donc `heaven_prove` répond `{"proved":true,"method":"kernel",
"certificate":"Usage: …"}`.

Reproductible avec :

    (echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":
     {"name":"heaven_prove","arguments":{"statement":"1+1"}}}' \
     | ./zig-out/bin/heaven mcp) 2>&1

## Symptôme 2 — panic sur tactics block

`Heaven.evalProve("prove test by { simplify }")` provoque
`thread … panic: Invalid free`.

Hypothèse : dans `runTacticsBlock` (heaven_expr.zig, autour de 3160), le
`body` (sous-chaîne de `src`) est probablement libéré par erreur, alors
que `src` est en lecture seule côté caller. Ou bien un `defer free` sur
une string statique.

## Contournement actuel (mcp_server.zig)

`heaven_prove` n'appelle plus `evalProve`. Il ne gère que :

1. `a == b` → eval LHS, eval RHS, compare (`method: semantic`)
2. sinon → `{"proved":false,"error":"…"}`

Effet : `2+2 == 5` retourne correctement `proved:false`. Fini les faux
positifs.

## Ce qu'il faudra pour réactiver le kernel

1. Faire que `evalProve` retourne une **erreur** (pas `Ok`) sur entrée
   invalide — au minimum `error.InvalidSyntax`.
2. Fixer le `panic: Invalid free` dans `runTacticsBlock`. À tracer avec
   `gpa` + stack traces (le binaire actuel est strippé : `Unable to
   open debug info`).
3. Vérifier qu'un tactics block réussi retourne bien une string
   sémantiquement correcte (pas le message d'usage).

Priorité : basse-moyenne (le kernel est utilisé pour les théorèmes
formels, pas pour les assertions MCP routinières). Session dédiée.
