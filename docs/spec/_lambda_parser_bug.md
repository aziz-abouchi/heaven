# Lambda -- incompatibilite parser/evaluateur (2026-10-24)

## Symptome
`(print ((lambda x x) 5))` affiche l expression brute.
`id_l _ = lambda x x` puis `((id_l 0) 5)` -> 5 (marche par accident).

## Cause racine (audit 6 blocs)
Parser et evaluateur ont deux representations incompatibles.

### Parser (`src/core/expr.zig:2087`)
`parseLambdaExpr` produit une chaine S-expr :
  allocPrint("(lambda {s} {s})", .{name, body})
Re-parse par le loader comme apply curryfie :
  apply(apply(sym lambda, sym x), sym body)

### Evaluateur (`src/core/heaven_expr.zig:3445`)
Reconnait le lambda comme apply a span de 3 elements :
  lam_args.len == 3  // [lambda, param, body]
Le re-parse du parser ne produit PAS cette structure (curryfie).

## Fix propre (session dediee)
Construire l AST via store.apply directement, pas allocPrint :
  const head = try self.store.sym("lambda");
  const param = try self.store.sym(name);
  return try self.store.apply(head, &.{param, body});
~10 lignes. Session .zig dediee.

## Contournement
Fonction nommee : inc x = x + 1 ; map inc xs

## Impact livre
22 occurrences lambda dans les .md. Documentees, non converties.
