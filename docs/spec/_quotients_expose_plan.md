<!-- HEAVEN:quotients-expose -->
# Quotients — exposer en Heaven pur (plan)

## État réel (2026-10-19)

**Noyau kernel : ✅ fonctionnel.**
- `ast.zig` : `quot`, `class`, `lift` (3 nœuds).
- `conversion.zig` : ι-réduction `lift(f)(class(x)) → f(x)`.
- `typechecker.zig` : `infer(Quot(A,R))` conserve l'univers de `A`.
- `test_quotient.zig` : 2/2 verts.

**Pont Heaven → kernel : ⚠️ quasi-absent.**
- `kernel_bridge.zig` expose `exprToTerm`, `declareFreeSymbols`
  (traduction Store Id → ast.Term basique).
- **Pas** de `elabQuot`/`elabClass`/`elabLift`.
- `heaven_expr.zig` n'appelle **jamais** `kernel_bridge`.

**Parser Heaven : ⚠️ rien.**
- Aucun `"Quot"`, `"class"`, `"lift"` dans `parse.zig`/
  `expr_parser.zig`.

## Pourquoi ce n'est pas 1 session

Exposer `Quot(A,R)` en `.hvn` demande :

1. **Étendre `kernel_bridge.zig`** : `elabQuot(store, pool, quot_id)`,
   `elabClass`, `elabLift`. Traduction des nœuds Store vers
   `ast.Term` avec les pointeurs corrects. ~80 l.
2. **Brancher `heaven_expr.zig`** sur `kernel_bridge` : le tree-walker
   n'a aucune notion de type-checking kernel. Il faut ajouter une
   voie "élaborer vers kernel" en parallèle de l'évaluation. ~100 l.
3. **Parser** : `Quot`, `class`, `lift` dans `expr_parser.zig`. ~40 l.
4. **Tests `.hvn`** : 5-10 cas (Quot conserve l'univers, ι-réduction,
   lift identité). ~30 l.

Effort réel : **2-3 sessions**.

## Décision

`quotients-expose` = chantier 2-3 sessions, pas un bloc de fin.
Tracé ici. À faire **après** :
- `kernel-tests` (câbler les 4 tests kernel, 1 session) — prérequis
  pour ne pas casser en CI.
- Décision architecturale : le tree-walker doit-il type-checker
  via kernel, ou le kernel reste-t-il un outil séparé (proofs) ?

## Alternative court terme

`Quot` utilisable côté **Heaven pur sans kernel** : définir une
approximation (paires normalisées par relation) en `stdlib/`. Pas
de la vraie théorie des types quotients, mais utilisable pour des
cas concrets (Set, multiset). 1 session. À trancher.
