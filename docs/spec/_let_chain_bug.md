# Bug : `let` + récursion = ExecutionFailed (2026-10-21)

> Ce fichier **remplace** la version 2026-10-19 qui parlait de `convertLetIn`
> et d'« AST non-évaluée » — cette analyse est **obsolète** depuis les fixes
> P0 parser (378145b) et `+strings` (e84686f). Le vrai bug actuel est différent.

## Symptôme

    rec n =
      if n <= 0 then 0
      else
        let m = n - 1 in
        rec m
    (print (rec 3))
    -- ExecutionFailed

Tout `let` dans le corps d'une fonction qui **s'appelle elle-même** échoue.
Un `let` dans une fonction non-récursive marche (test 14 OK).

## Faits mesurés (5 discriminants, session 2026-10-21)

| Test | Résultat |
|---|---|
| `f x = x + 10` ; `g n = let x = n - 1 in f x` | **14 OK** |
| `h n = let y = g n in y + 1` (2 niveaux) | **13 OK** |
| `rec n = if n > 0 then rec (n - 1) else 0` | **0 OK** (récursion pure) |
| `rec n = if n > 0 then let m = n - 1 in rec m else 0` | **KO** (let + recursion) |
| `rec n = if n > 0 then let x = n-1 in n + rec x else 0` | **KO** |
| `rec n = if n > 0 then let n = n-1 in rec n else 0` | **KO** (shadow) |

## Ce qui N'est PAS la cause (éliminé)

- Collision de noms (`m` différent de `n`, KO quand même)
- Shadow du paramètre (test C KO identique)
- Le `+` autour de la recursion (test sans `+`, KO)
- Let-chain profond (2 lets imbriqués OK, test C)
- `env.delete` sauvage dans `.bind` (patch testé + rollback, KO)

## Vraie cause (à instrumenter)

`let x = ... in <recursive call>` — le `.bind` créé par le parser
interfère avec la frame récursive de `env`.

## Instrumentation (session fraîche)

**Important** : `platform.dbg` est **muet** sans `HEAVEN_DEBUG=1`.
Utiliser `std.debug.print` (natif seulement, wasm KO).

    // engine_expr.zig, case .bind (l.939)
    std.debug.print("[BIND] depth={d} payload={d}\n", .{depth, node.payload});
    // case .apply (résolution de fonction)
    std.debug.print("[APPLY] depth={d} op={s}\n", .{depth, op});

Puis `./zig-out/bin/heaven run /tmp/t1.hvn` (rec + let m différent).
Voir si `depth > 1000` (budget) ou `ArityMismatch` (apply).

## Impact

- Bloque : QTT runtime, loop MCP, `web_lookup` 6e tool, dispatch `if m then M.foo`
- Workaround : `precalcul+pick` (évalue toutes branches avant le if)
- **1 session `.zig`, cutoff 3 blocs**
