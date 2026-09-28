# Store — invariant span_a[0] = func

Pour tout .apply, span_a = [func_id, arg0, arg1, ...] où
func_id == node.payload. Toute itération sur les arguments
doit skip [0].

store.apply(func, args) re-préfixe lui-même le func :
passer [arg0, arg1], pas [func, arg0, arg1].

## Sites corrigés (audit 2026-09-28)

| Fichier | Fonction | Bug |
|---|---|---|
| core/proof_core.zig | substituteVar | func itéré + snapshot pool |
| core/commands/cas.zig | simplifyRec | len==2 jamais matché |
| core/proof_helpers.zig | copyIdBetweenStores | func dupliqué |
| core/egraph_rewriter.zig | validTree | func validé 2x |
| core/simplify_engine.zig | nodeCountCost | func compté 2x |
| codegen/expr_latex.zig | emitExpr | head émis 2x |
| core/diff.zig | printTree | func imprimé 2x |
| core/kernel_bridge.zig | test | apply(plus, [plus, ...]) |

## Sites OK (vérifiés)

- proof_core.zig:112 — branche bind/lambda/relation
- egraph_rewriter.zig:393 — branche relation
- format.zig:113 — branche source_file/block
- elab.zig:1251 — branche lambda/bind

## Legacy (non touché)

src/legacy/codegen/forge_latex.zig:204, 213

## Helper proposé

    pub fn applyArgs(store: *const Store, node: Node) []const Id {
        const all = node.span_a.slice(store.pool.items);
        return if (all.len > 0 and all[0] == node.payload) all[1..] else all;
    }

188 sites utilisent span_a.slice. Migration progressive.

## Effet

5 bugs réels corrigés en une session (même classe). Un helper ou
une assertion dans store.apply éviterait la récidive.
