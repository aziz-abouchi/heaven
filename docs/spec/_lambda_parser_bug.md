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

## 6 hypotheses eliminees, couche finale : heaven.eval

Print [LPAREN] dans parsePrimary .lparen. Test T2 :
7 prints, TOUS du prelude (arena_used, arena_cap, <=, +, if,
pair, pair). AUCUN pour ((lambda x x + 1) 5).

### Conclusion
L'expression n'entre PAS dans parsePrimary .lparen. Le print est
dispatché AVANT -- probablement heaven.eval a un case "print"
special qui n'appelle pas NativeParser pour l'argument.

### 6 hypotheses eliminees (2 blocs instrumentation)
1. case 2b manquant interpForAssert -- FAUX (fnode.tag=apply)
2. parseLambdaExpr body non parentheses -- FAUX (ne change rien)
3. interpForAssert cases 2/3 -- FAUX (ne firent jamais)
4. double-parens body -- FAUX (ne change rien)
5. bug dans parseLambdaExpr -- FAUX (jamais appele)
6. bug dans parsePrimary .lparen -- FAUX (lambda n'y arrive pas)

### Vraie couche : heaven.eval dispatch
Le prochain fix doit instrumenter heaven.eval (la fonction top-level)
pour voir comment "(print X)" est traite. Si elle a un case "print"
qui ne parse pas X via NativeParser, c'est la qu'il faut ajouter
le dispatch lambda/let.

### Etat (post-P1)
- if inline -> 10 OK (dispatch if marche)
- map + lambda simple -> OK
- lambda en binding -> OK
- ((lambda x x) 5) -> 5 (engine par chance)
- ((lambda x x + 1) 5) -> brut (dispatch)
- let inline -> brut (meme cause probable)

### NE PAS refaire
- NE PAS patcher parseLambdaExpr
- NE PAS patcher interpForAssert
- NE PAS patcher parsePrimary .lparen
- Instrumenter heaven.eval EN PREMIER, 3 prints, cutoff 3 blocs.

## Diagnostic précis final (2026-10-26)

grep '"print"' dans heaven_expr.zig = VIDE. print n'est pas un case
string. T1 et T2 sont des expressions NUES (pas (print ...)),
retournées par eval.

Trace instrumentée (interpForAssert + fix2b) :
- T1 ((lambda x x) 5) :
    node=apply fnode=apply args=2
    fix2b: payload.tag=sym span.len=3  -> 5 OK
- T2 ((lambda x x + 1) 5) :
    node=apply fnode=apply args=2
    fix2b: payload.tag=sym span.len=5  -> brut

### Cause
interpForAssert case 2b (heaven_expr.zig:3329-3345) :
  const lam_args = self.store.spanSliceConst(fnode.span_a);
  if (lam_args.len == 3) { ... }  // [lambda, param, body]

Attend span.len == 3. T1 matche (3). T2 a span.len == 5 (body
aplati : [param, body_head, body_arg1, op, lit] ou similaire),
donc case 2b ne fire pas. Fallback -> evaluateExpr -> id brut.

### Le fix (session dédiée)
Dans interpForAssert case 2b : accepter lam_args.len >= 3 et
reconstruire le body depuis lam_args[2..]. ~5-10 lignes.
NE PAS toucher parseLambdaExpr, parsePrimary, evaluateExpr.

### 7 hypothèses éliminées (2 blocs instrumentation)
1. case 2b manquant -- FAUX (fnode.tag=apply)
2. body non parenthésé -- FAUX
3. interpForAssert cases 2/3 morts -- FAUX
4. double-parens -- FAUX
5. parseLambdaExpr -- FAUX (jamais appelé)
6. parsePrimary .lparen -- FAUX (lambda n'y arrive pas)
7. print case -- FAUX (n'existe pas)

### Vraie couche : interpForAssert case 2b, condition lam_args.len == 3
### Fix estimé : 5-10 lignes dans heaven_expr.zig:3341

## Tentative fix case 2b (2026-10-26) -- build casse

Ajout case 2b bis pour lam_args.len == 5 (body aplati) :
  [lambda, param, a1, op, a2] -> apply(op, [a1, a2])
Build 0 la 1re fois (non curryfie), mais T2 toujours brut
(interpForAssert echec silencieux, catch id).
2e tentative (curryfie + catch |e|) : BUILD FAIL (type mismatch).

### Ce que le DUMP a prouve
T1 : [lambda, x, x]         -> 5 OK (case 3 fire)
T2 : [lambda, x, x, +, 1]   -> brut (case 3 ne fire pas, len=5)

Le parser APLATIT le body en span. T1 a un body trivial (sym),
T2 a un body infixe aplati en 5 elements.

### Prochaine session (PRECIS)
1. Le build casse a cause de catch |e| return id -- corriger le type
   (interpForAssert retourne HeavenError!Id, catch doit retourner Id
   pas error). Probablement : `catch { return id; }` sans binding e.
2. Si le case 2b curryfie marche, T2 -> 6 et let inline -> 6.
3. Si interpForAssert(body) echoue sur UnboundVariable(x), c'est
   que l'env n'est pas propage -- chercher pourquoi.

### NE PAS
- NE PAS toucher parseLambdaExpr, parsePrimary, evaluateExpr
- Le fix est UNIQUEMENT dans interpForAssert case 2b (heaven_expr.zig)
- Corriger le build AVANT de retester T2 (binaire actuel = ancien)

### 8 hypotheses eliminees au total
Toutes les autres couches sont innocentes. Le bug est dans
interpForAssert case 2b, structure [lambda, param, a1, op, a2].
Fix = 8-12 lignes, build correct, cutoff 3 blocs session dediee.

## Tentative finale case 2b (2026-10-26) -- cutoff respecte

Patch case 2b bis (lam_args.len == 5) : logique correcte
([lambda, param, a1, op, a2] -> apply(apply(op, a1), a2)).
BUILD FAIL sur un simple shadowing :

  src/core/heaven_expr.zig:3468:35: error: local constant 'inner'
  shadows local constant from outer scope

### Fix connu (1 ligne, aucune logique a changer)
Renommer `inner` en `inner_body` (ou tout nom non utilise dans
la fonction interpForAssert). C'est UNIQUEMENT du nommage Zig.

### Prochain bloc (30 secondes)
1. Reappliquer le patch case 2b bis avec `inner_body` au lieu
   de `inner`.
2. zig build (doit passer).
3. Test T2 : ((lambda x x + 1) 5) -> 6 attendu.
4. Test T1 (controle) : 5.
5. Regression 18/18.
6. Si tout vert : commit fix. Si T2 KO : rollback, doc.

### Etat final session lundi
- 1 fix reel (P1 : if repare, lambda binding, map)
- 11 docs graves (decisions, security, backend, vision, loader,
  lambda, zig_debt, + registres)
- 8 hypotheses eliminees par instrumentation
- 2 fixes cibles prets :
  A. case 2b bis : 1 ligne shadowing (inner -> inner_body)
  B. loader .hvn cycles >= 4 : session Zig gdb
- Baseline 18/18 preservee, tree propre.

Cutoff 1 bloc respecte. Pas de 2e tentative malgre l'erreur triviale.
La discipline tient.

## 9e hypothese (case 2b bis) -- build OK, T2 KO

Patch case 2b bis avec noms distincts (param_node5, body_inner,
body_full) : BUILD=0, regression 18/18 verte, mais T2 toujours brut.
let inline toujours brut.

### Conclusion
Soit le case 2b bis ne fire pas (lam_args.len != 5 apres le
renommage ?), soit il fire mais interpForAssert(body_full)
echoue silencieusement (catch id).

### 9 hypotheses eliminees sur ce bug
1. case 2b manquant
2. parseLambdaExpr body non parentheses
3. interpForAssert cases 2/3 morts
4. double-parens body
5. bug dans parseLambdaExpr (jamais appele)
6. bug dans parsePrimary .lparen (lambda n'y arrive pas)
7. print case (n'existe pas)
8. case 2b bis 1re version (shadowing)
9. case 2b bis 2e version (build OK, T2 KO)

### Le vrai probleme (a accepter)
Le bug lambda body binaire est PLUS PROFOND que le case 2b.
Il faut soit :
- Instrumenter le case 2b bis (2-3 prints : fire ?, body_full.tag ?,
  interpForAssert result ?), 1 bloc read-only.
- OU accepter que le fix est structurel : extraire interpForAssert
  dans un fichier separe (P1 _zig_debt.md), avec tests unitaires.

### Prochain bloc (session fraiche)
Option A (rapide) : 3 prints dans case 2b bis, cutoff 3 blocs.
Option B (structurel) : extraction interpForAssert -> interp.zig,
puis tests unitaires sur les 5 cas lam_args.len.

Option B est le vrai fix -- 5498 lignes dans heaven_expr.zig
cachent le comportement. Option A donne la reponse en 1 bloc
mais probablement pour trouver une 10e cause.

### Etat final
- 1 fix reel (P1 : if repare, lambda binding, map)
- 11 docs
- 9 hypotheses eliminees
- Baseline 18/18, tree propre.

## 10e tentative (instrumentation case 2b) -- erreur methodo

Patch avec print [C2B] ajoute via s.replace(old, new, 1).
Resultat : aucun print [C2B] pour T2.

### Cause de l'echec du patch
Le pattern `if (lam_args.len == 3)` existe dans DEUX endroits :
- Fix 2a (fnode.tag == .lambda)
- Fix 2b (fnode.tag == .apply + sym lambda)

s.replace(old, new, 1) a remplace la PREMIERE occurrence
(Fix 2a), pas Fix 2b. Pour T2, fnode.tag=apply, donc Fix 2a
ne fire pas, print n'apparait pas.

### Erreur methodologique
Le patch a vise le mauvais endroit. C'est EXACTEMENT ce que le
cutoff 3 blocs doit arreter. Pas de 11e tentative.

### 10 hypotheses eliminees
1-9 : voir sections precedentes
10 : print dans mauvais case (erreur methodo, pas bug)

### Le vrai fix (session fraiche, Option B)
Extraire interpForAssert dans interp.zig (P1 _zig_debt.md).
Une fois isole (500 lignes), les 5 cas lam_args.len sont testables
unitairement. Le bug sera visible en 1 bloc. 5498 lignes dans
heaven_expr.zig cachent le comportement -- c'est le vrai probleme.

### Etat final (definitif)
- 1 fix reel (P1 : if repare, lambda binding, map)
- 11 docs
- 10 hypotheses eliminees (dont 1 erreur methodo)
- Baseline 18/18, tree propre.

### Decision
Arret. Le bug lambda body binaire est STRUCTUREL, pas local.
3 sessions de tentatives locales ont echoue. La reponse est
l'extraction (Option B), pas un 11e patch.

Cutoff absolu. Cloture.

## Tentatives case 5 (2026-10-26) -- 13 tentatives, pivot

### Ce qui marche
- Fix 2b ATTEINT avec marker unique (pas erreur metho cette fois)
- Trace : [F2B] enter fix2b + [F2B] lam_args.len=5
- Substitution x -> args[0] : ((+ 5) 1) au lieu de ((lambda x x+1) 5)

### Ce qui ne marche pas
- interpForAssert(bf5) retourne ((+ 5) 1) SANS reduire
- evaluateExpr(bf5) echoue (brut)
- Le body apply(apply(sym_+, [5]), [1]) n'est pas evalue a 6

### Cause probable
Le body curried apply(apply(sym_+, [5]), [1]) n'est pas reconnu
par l'engine. Soit il faut multi-arg apply(sym_+, [5, 1]),
soit in_interp bloque l'appel recursif, soit le body doit etre
construit en string et passe a evalSExpr (heaven_eval.hvn).

### 13 hypotheses eliminees au total
Voir sections precedentes. Le bug est structurel : 5498 lignes
cachent le flow. Le vrai fix est l'extraction (P1 _zig_debt.md).

### Pivot : cleanup stubs + jumbos
L'utilisateur demande nettoyage stubs et reduction jumbos.
On arrete le bug lambda. Focus sur ce qui est demande.

## Fix PARTIEL 2026-10-26 : T2 top-level OK

### Fix livre (commit 0dbdab8)
interpForAssert case 2b bis (lam_args.len == 5) : reconstruire le
body en MULTI-ARG apply(sym_+, [args[0], 1]) -- pas curryfie.
Multi-arg reduit a 6, curryfie reste partiel.

### Ce qui marche maintenant
- ((lambda x x + 1) 5) top-level -> 6 OK
- map (lambda x x + 1) [1,2] -> [2,3] OK
- f = lambda x x + 1 ; (f 5) -> 6 OK
- ((lambda x x) 5) -> 5 (case 3, regression preservee)

### Ce qui reste casse (2 bugs distincts)
1. (print ((lambda x x) 5)) -> brut
   print est traite comme apply(sym_print, [X]). L'argument X
   est evalue via evaluateExpr (engine), qui echoue sur lambda.
   Fix = interpForAssert case apply pour sym_print : evaluer
   l'argument via interpForAssert (pas evaluateExpr).
   ~5-10 lignes, case apply (pas case 2b).

2. (lambda x -> x + 1) -> InvalidSyntax
   Le parser ne gere pas la fleche `->`. parseLambdaExpr attend
   `lambda x body`, pas `lambda x -> body`.
   Fix = parsePrimary case lambda : accepter `->` optionnel apres
   le param. ~5 lignes.

### Livre
Les 22 occurrences lambda du livre utilisent `lambda x -> body`
(ch6, ch19, ch20, ch25). Elles restent KO jusqu'au fix `->`.
Les occurrences sans fleche fonctionnent.

### Prochaine session (2 blocs, pas 15)
1. interpForAssert case apply : print avec argument non-trivial.
2. parsePrimary case lambda : accepter `->` optionnel.
Chacun est localise (case apply, case lambda). Pas de tunnel.

## Diagnostic print (2026-10-26) -- bug eval, pas patch

io_handler.zig:23 handler Print :
  const s = expr.toStringInfix(store, a, store.allocator);
  platform.debug.print("{s}\n", .{s});

Le handler convertit l'argument en STRING INFIXE (toStringInfix)
au lieu de l'EVALUER. Pour ((lambda x x) 5), toStringInfix retourne
((lambda x x) 5), pas 5.

Le fix n'est pas dans io_handler.zig (signature : store, label, arg
-- pas de env/engine). Il faut soit :
A. perform evalue l'argument avant d'appeler le handler (engine_expr)
B. print x = perform "Print" (eval x) -- mais eval n'est pas expose
C. interpForAssert case apply pour perform/print

C'est ENCORE un bug d'eval profond (16e hypothèse sur cette famille).
La session a livre 5 fixes reels. Ce 6e n'est pas un patch de 5 min.

### Prochaine session
1. Lire perform dans engine_expr.zig (comment il evalue ses args)
2. Si perform evalue deja : le handler recoit l'AST (bug toStringInfix)
3. Si perform n'evalue pas : fix perform (evaluer arg avant handler)
4. Sinon : cas apply interpForAssert pour perform/print

### Fix `->` livre (commit 366d609)
lambda x -> body fonctionne. Les 22 occurrences du livre qui
utilisent `->` marchent pour map/filter/binding. C'est le gain
reel de la session sur lambda.
