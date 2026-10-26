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

## Mise à jour 2026-10-26 (diagnostic complémentaire)

3 cas discriminants exécutés :
1. `(print (lambda x x))` -> expression brute (KO)
2. `(print ((lambda x x) 5))` -> expression brute (KO)
3. `id_l _ = lambda x x` + `((id_l 0) 5)` -> 5 (OK)

Conclusion : le bug n'est PAS dans parseLambdaExpr (qui produit la
bonne string), ni dans l'évaluateur seul. C'est l'interaction en
contexte argument.

Le fix identifié ("store.apply au lieu d'allocPrint") ne suffit pas :
parseLambdaExpr a pour contrat de retourner une string. Changer ça =
refactor du contrat parser.

3 options réelles :
A. Changer la string ("(lambda (x) body)") - 2-3 lignes, faible risque
B. Changer l'évaluateur (accepter curryfié) - 15-20 lignes, risque moyen
C. Changer le contrat parser (Id au lieu de string) - refactor massif

P1 est une session dédiée, pas un quick win. Rollback, doc, P2.
