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


## Résolution 2026-10-26 : prefix dispatch

Patch appliqué dans src/core/expr.zig : if/let/lambda déplacés de
parsePrimary (.ident) vers parseUnary (haut). Casse le cycle
parse_atom -> parse_if -> parse_add -> ... -> parse_atom.

Résultats :
- lambda en def : 5 OK
- ((lambda x x) 5) : 5 OK (P1 résolu)
- if inline : 10 OK (bonus, if inline ne marchait pas avant)
- let inline : expression brute (KO, bug séparé)
- régression 18/18 verte

let inline reste cassé : parseLetExpr ne consomme probablement pas
'in' correctement quand let est dans des parenthèses. Doc séparée
à créer.

## Mise à jour 2026-10-26 (let inline)

3 cas : top-level def OK (6), parens KO (brut), def helper OK (6).

Diagnostic : parseLetExpr produit la bonne string, mais l'évaluateur
ne sait pas évaluer (let ...) en argument de print. Bug évaluateur,
pas parser. Le patch .lparen (dispatch let/lambda dans parsePrimary
case .lparen) ne résout rien -- rollback.

Le fix est dans heaven_expr.zig (évaluation des arguments de print
qui sont des let/lambda), pas dans expr.zig (parser).

Session dédiée : instrumenter heaven_expr.zig sur
(print (let x = 5 in x + 1)). Cutoff 3 blocs.

## État réel post-P1 (2026-10-26)

Testés 6 snippets du livre + 5 cas discriminants. Résultats :

### Débloqué par P1 (prefix dispatch)
- `if` S-expr `(if (< 1 2) 10 20)` → 10 ✅
- `if` infixe `(if 1 < 2 then 10 else 20)` → 10 ✅
- `map inc (cons 1 (cons 2 nil))` → (cons 2 (cons 3 nil)) ✅
- `f = lambda x x + 1` puis `(f 5)` → 6 ✅
- `f _ = let x = 5 in x + 1` puis `(f 0)` → 6 ✅

### Reste cassé (bug évaluateur, pas parser)
- `((lambda x x + 1) 5)` top-level → brut
- `apply_l (lambda x x + 1) 5` → brut
- `let x = 5 in x + 1` top-level → syntax error in let
- `(print (let x = 5 in x + 1))` → brut

Pattern : l'évaluateur ne traite pas les corps binaires de
lambda/let en position argument ou top-level direct. Il les traite
dans un binding (f = ...).

C'est UN SEUL bug dans heaven_expr.zig (évaluation des corps
binaires en position argument/top-level), pas plusieurs. Fix
estimé 10-20 lignes. Session dédiée, cutoff 3 blocs.

## Tentatives de fix évaluateur (2026-10-26) -- échec

2 hypothèses testées pour le bug "corps binaire en argument" :

### Hypothèse 1 : case 2b manquant dans interpForAssert
Ajout case `fnode.tag == .lambda and args.len == 1` avant case 3.
Résultat : ne fire pas. Le parser ne produit pas `apply(.lambda_node,
[arg])`, il produit une structure imbriquée différente.

### Hypothèse 2 : parseLambdaExpr body non parenthésé
Changement `(lambda {s} {s})` -> `(lambda {s} ({s}))`.
Résultat : ne change rien. Build OK, régression 18/18, mais T2
reste brut et let inline reste brut.

### Conclusion
Le bug n'est ni dans le case lambda de interpForAssert, ni dans
le format de la string de parseLambdaExpr. Il est dans la chaîne
d'évaluation des arguments (evaluateExpr / interpForAssert) qui
ne traite pas les corps binaires en position argument.

Prochaine étape : instrumenter avec std.debug.print dans
interpForAssert (3-4 prints) pour voir exactement quel chemin
est pris pour ((lambda x x + 1) 5). Session Zig dédiée, cutoff
3 blocs. NE PAS refaire 2 tentatives aveugles.

Rollback. Cutoff 3/3 respecté. 2 tentatives, 2 échecs, on arrête.

## Instrumentation 2026-10-26 (3 prints) -- bug dans l'engine

Trace T1 ((lambda x x) 5) :
  [I4A] entry id=5739 node.tag=apply fnode.tag=apply args_len=2
  [I4A] entry id=5736 node.tag=sym fnode.tag=sym args_len=0
  -> 5

Trace T2 ((lambda x x + 1) 5) :
  [I4A] entry id=5741 node.tag=apply fnode.tag=apply args_len=2
  (rien)
  -> brut

### Observations
1. fnode.tag == apply, PAS lambda. Hypothese case 2b etait fausse.
2. case 2 (apply(sym lambda, ...)) ne fire jamais.
3. case 3 (env-bound) ne fire jamais.
4. Les deux passent par le fallback engine (evaluateExpr ligne ~3490).

### Difference T1/T2
- T1 : engine evalue une sous-expression (sym) -> 5 OK
- T2 : engine n'evalue AUCUNE sous-expression -> brut

### Conclusion
Le bug n'est PAS dans interpForAssert (cases 2/3). Il est dans
le fallback engine (evaluateExpr) qui reussit sur body trivial (x)
et echoue sur body binaire (x + 1).

Prochaine session : instrumenter evaluateExpr (memes 3 prints),
voir ou x + 1 echoue. Cutoff 3 blocs.

NE PAS patcher interpForAssert. Le bug est dans evaluateExpr.

## Instrumentation parseLambdaExpr (2026-10-26) -- dispatch casse

Print [LAM] ajouté dans parseLambdaExpr (body_str + result).
Test T2 ((lambda x x + 1) 5) : le print n'apparait PAS.

### Conclusion
parseLambdaExpr n'est JAMAIS appele pour ((lambda x x + 1) 5).
Le dispatch lambda se perd avant parseLambdaExpr -- probablement
dans parsePrimary .lparen (traite lambda comme ident ordinaire)
ou parsePostfix (avale lambda comme argument).

### Ce qui a ete elimine (5 hypotheses)
1. case 2b manquant dans interpForAssert -- FAUX (fnode.tag=apply)
2. parseLambdaExpr body non parentheses -- FAUX (ne change rien)
3. bug dans interpForAssert cases 2/3 -- FAUX (ne firent jamais)
4. double-parens body -- FAUX (ne change rien)
5. bug dans parseLambdaExpr -- FAUX (jamais appele)

### Vrai point d'entree (prochain session)
Instrumenter parsePrimary .lparen (case next) et parsePostfix
(pourquoi lambda n'est pas traite comme primary). 3 prints,
cutoff 3 blocs. NE PAS toucher parseLambdaExpr ni interpForAssert.

### Etat
- T1 ((lambda x x) 5) -> 5 (marche par chance, chemin engine)
- T2 ((lambda x x + 1) 5) -> brut (parseLambdaExpr jamais appele)
- let inline -> brut (meme cause, parseLetExpr similaire ?)
- if inline -> 10 OK (dispatch if fonctionne)
- map + lambda simple -> OK (chemin different)

5 hypotheses eliminees, 1 vraie couche identifiee (dispatch parser).
