# Loader .hvn : cycles de définitions mutuelles (2026-10-26)

## Le vrai diagnostic de P2

Trois tentatives pour ajouter `parse_cmp` à `lib/parse/infix.hvn`
ont échoué avec le **même SEGV au chargement** (`test_parse_infix:139`) :
1. Cascade `if` 6 niveaux (is_cmp)
2. Table plate (cmp_ops + in_cmp)
3. Sans toucher `open_paren` (parse_infix → parse_cmp seulement)

**Ce n'est pas `parse_cmp` le problème.** Le code est syntaxiquement
valide, compile, et ne devrait pas boucler. C'est le **loader `.hvn`**
qui crashe quand `infix.hvn` contient une fonction récursive mutuelle.

## Le pattern qui crashe

`step_cmp` appelle `parse_add`, qui appelle `parse_mul`, qui appelle
`parse_atom`, qui appelle `open_paren` → `parse_add`. Et
`parse_infix` → `parse_cmp` → `parse_add`.

Ce n'est **pas** un cycle d'appels infini (`parse_add` ne remonte
jamais à `parse_cmp`). C'est un **cycle de définitions** : le loader
qui charge `infix.hvn` doit résoudre `parse_cmp` qui dépend de
`parse_add`, qui existe déjà, mais qui dépend transitivement de
`parse_mul`, `parse_atom`, `open_paren`... et `open_paren` dépend
de `parse_add`. Cycle statique, pas dynamique.

**Le loader Zig résout ce cycle en un seul fichier** (les définitions
sont dans la même portée). **Le loader `.hvn` non.**

## Preuve

Même fichier, deux parseurs :
- `NativeParser` (Zig, `parseUnary` → `parseIfExpr` → `parseExpr(0)`)
  → cycle `parse_atom → parse_if → parse_add → ... → parse_atom`
  cassé par prefix dispatch. **Marche.**
- `heaven_parse.hvn` (`infix.hvn` : `parse_infix → parse_cmp →
  parse_add → ... → open_paren → parse_add`) → même cycle
  structurel. **Crashe au chargement.**

La différence : le loader Zig gère les cycles inter-définitions,
le loader `.hvn` non.

## Ce qui a été testé et exclu

- `is_cmp` en cascade `if` (6 niveaux) : SEGV — pas la cause
- `cmp_ops` + `in_cmp` en table plate : SEGV — pas la cause
- `parse_cmp` sans toucher `open_paren` : SEGV — pas la cause
- `parse_cmp` avec `open_paren → parse_add` inchangé : SEGV — pas la cause

Le SEGV est **déterministe** et **indépendant du contenu** de
`parse_cmp`. C'est le loader qui casse.

## 3 options de fix

### A — Instrumenter le loader Zig (session dédiée)
`gdb -nx` + core dump sur `infix.hvn` avec `parse_cmp`. Voir
exactement quelle ligne du loader crashe (profondeur de récursion ?
taille de stack ? cycle de `resolve` non détecté ?). 3 blocs cutoff.

**Coût** : 1 session Zig. **Risque** : moyen (on ne connaît pas
la cause exacte). **Gain** : débloque E1.2, E1.4, P2 en même temps.

### B — Réécrire infix.hvn en style non-récursif
Flat token stream + parse en une passe. Élimine les cycles de
définitions mutuelles **par construction**. C'est ce que fait le
`NativeParser` Zig (Pratt) — une seule fonction `parseExpr` qui
délègue à `parseUnary`/`parsePrimary` en pile, pas en cycle.

**Coût** : 1-2 sessions `.hvn`. **Risque** : faible (pas de
loader à modifier). **Gain** : débloque P2 uniquement (E1.2/E1.4
seront réécrits aussi).

### C — Attendre E1 complet
Quand E1.2-E1.7 seront faits, `infix.hvn` sera réécrit en même
temps. Risque : E1.2 est bloqué par le **même** loader bug.

**Coût** : 0 maintenant, mais E1 bloqué. **Risque** : élevé
(E1.2 = même bug, on tourne en rond).

## Recommandation

**B d'abord** (réécrire `infix.hvn` non-récursif, 1-2 sessions),
**A si B échoue** (instrumenter le loader, session Zig dédiée).

Raison : B est **sous notre contrôle** (`.hvn`), A dépend du
loader Zig. B élimine le bug **par construction**, A le contourne.

## Impact sur la roadmap

- **E1.2** (`if`/`then`/`else` en `.hvn`) : bloqué par le même bug
- **E1.4** (`lambda` en `.hvn`) : bloqué par le même bug
- **P2** (`parse_cmp`) : bloqué par le même bug

**Un seul fix (B) débloque E1.2, E1.4 et P2.** C'est le meilleur
ratio de toute la roadmap E1.

## Voir aussi

- `_cascade_if_bug.md` : 3 tentatives P2 documentées
- `_lambda_parser_bug.md` : P1 résolu (Zig), let inline KO (évaluateur)
- `_emancipation_roadmap.md` : E1.2-E1.7
- `_import_resolution.md` : P3 (pre-pass Zig)

## Mise à jour 2026-10-26 : option B échoue aussi

Réécriture non-récursive de infix.hvn tentée (squelette + boucle Pratt) :
- Squelette (parse_expr = parse_atom, pas de boucle) : charge, parse 42.
- Boucle Pratt (parse_expr -> loop -> continue_loop -> parse_expr) :
  même le chargement crashe (silence sur les 4 tests).

Conclusion : le loader .hvn ne gère PAS les cycles de >= 4 fonctions
mutuellement récursives. Le test cycle 2 (f <-> g) passait, mais un
cycle de 4 casse. Ce n'est pas infix.hvn, c'est le loader.

Options B (réécrire infix.hvn) = MORTE. Le problème n'est pas la
structure du parser, c'est le loader qui ne supporte pas la récursion
mutuelle profonde.

Option A (session Zig, instrumenter le loader) devient OBLIGATOIRE.
Cutoff 3 blocs respecté (squelette OK, boucle Pratt KO, rollback).

## Mise à jour 2026-10-26 : E1.5 (parse_app) échoue aussi

### Ce qui a été testé
- Cycle de 5 fonctions **triviales** (f->g->h->i->j->f) : CHARGE OK
- Cycle de 5 fonctions **avec corps complexe** (parse_app avec
  HP.TCons, if, appels) : SILENCE au chargement (crash)

### Conclusion affinée
Le loader .hvn ne casse PAS sur le nombre de fonctions mutuellement
récursives (5 charge en trivial). Il casse sur la COMPLEXITÉ du corps
(pattern matching HP.TCons, if imbriqués, appels avec arguments).

C'est probablement la profondeur de récursion de `resolve` pendant
le chargement, ou un cycle non détecté dans les dépendances de
patterns (les clauses HP.TCons créent des dépendances transitives).

### Impact
E1.5 (parse_app) est bloqué par le même bug que E1.2, E1.3, E1.4,
E1.6, P2. Le fix loader est encore plus critique que prévu.

### Prochain bloc : loader .hvn (session Zig gdb)
Le test discriminant (cycle 5 trivial vs cycle 5 complexe) donne
une piste : instrumenter `resolve` dans le loader pour voir à
quelle profondeur il crashe sur infix.hvn avec parse_app.

## Clause fautive identifiee (2026-10-26, instrument flush)

Avec FLUSH instrumente, la derniere clause avant SEGV (EXIT=139) est :

  step_app f (HP.TCons tk rest) =
    if (is_atom_start (HP.TCons tk rest)) == 1
    then (continue_app f (parse_atom (HP.TCons tk rest)))
    else (IOk f (HP.TCons tk rest))

### Particularites de cette clause
1. HP.TCons tk rest apparait 3 fois dans le CORPS (construction, pas
   pattern match). Les clauses precedentes utilisent TCons en pattern
   (parse_atom (HP.TCons (HP.TIntTok n) rest) = ...).
2. (is_atom_start (HP.TCons tk rest)) == 1 : appel de fonction avec
   construction en argument, compare a 1.
3. (continue_app f (parse_atom (HP.TCons tk rest))) : appel imbrique
   3 niveaux.

### Hypotheses (a confirmer session Zig)
- Le loader ne sait pas CONSTRUIRE TCons dans le corps (seulement
  matcher en pattern). Test : une clause simple `f x = (HP.TCons x nil)`.
- Ou `== 1` sur un appel de fonction pose probleme (peu probable,
  test_parse_infix utilise `==` sur nombres).

### Test discriminant (prochain bloc)
  test_construct x = HP.TCons x HP.TNil
  (print "loaded")
Si ce fichier crashe : confirmation que TCons en construction KO.
Fix : soit le loader doit construire les ADT (plus profond), soit
step_app doit etre reecrit sans construction (utiliser un helper
pattern-matche).

### Impact
E1.5 (parse_app) est bloque par ce bug. Le fix loader doit gerer
la construction d'ADT dans le corps, pas seulement le pattern match.
C'est plus profond que prevu -- probablement dans evalEquation ou
le type-checker (P5).

## Mise à jour 2026-10-26 (tests discriminants) -- cas de bord

### 3 tests executés (tous CHARGEENT)
1. `test_construct x = HP.TCons x HP.TNil` : loaded OK
2. `f a = if (= a 1) then 0 else 1` : loaded OK
3. `data Foo = MkFoo Int ; test_construct2 x = MkFoo x` : loaded OK

### Conclusion affinee
Ce n'est PAS :
- TCons en construction dans le corps (test 1)
- if + == sur appel (test 2)
- ADT construction en general (test 3)

C'est la COMBINAISON specifique de step_app :
- 2 parametres dont un pattern imbrique (HP.TCons tk rest)
- 3 appels imbriques (continue_app -> parse_atom -> TCons)
- construction TCons entre parentheses en argument :
  (is_atom_start (HP.TCons tk rest))
- if ... then ... else avec les 2 branches qui contiennent
  la construction

C'est un cas de bord du loader, pas une cause simple isolable.

### Fix (session Zig gdb, 1 session)
1. gdb -nx + core dump sur infix.hvn avec step_app
2. bt pour voir la stack au SEGV (profondeur, fonction)
3. Identifier si c'est :
   - evalEquation (parsing du corps de clause)
   - evalBinary (== sur appel)
   - apply (3 niveaux imbriques)
4. Fix + test E1.5

### Le loader .hvn est le goulot #1 du projet
6 chantiers bloques : E1.2, E1.3, E1.4, E1.5, E1.6, P2 (parse_cmp).
Le fix vaut 1 session Zig gdb.

### Bilan session lundi (8 blocs loader, 0 fix)
- 8 hypotheses eliminees (clause step_app, TCons, if, ADT)
- 3 tests discriminants (tous passent, donc cas de bord)
- Doc precise pour session Zig
- ROLLBACK propre, 18/18 preserve, tree propre

## Mise à jour 2026-10-26 (session 2) -- 8 tests discriminants

### Tests executés (tous CHARGEENT, EXIT=0)
1. `test_construct x = HP.TCons x HP.TNil` OK
2. `f a = if (= a 1) then 0 else 1` OK
3. `data Foo = MkFoo Int ; test_construct2 x = MkFoo x` OK
4. `step_app f x = continue_app f x ; continue_app f x = f` (forward ref) OK
5. `step_app f (TCons tk rest) = if (is_atom (TCons tk rest)) == 1 then ...` OK
6. `full_min.hvn` (4 HP.TCons + 3 appels imbriques + data IRes) OK
7. `no_step.hvn` (parse_app + is_atom_start + continue_app + IRes) OK
8. `rec_app.hvn` (continue_app recursive) OK

### Conclusion
Le crash N'EST PAS reproductible en fichier minimal. Il necessite le
CONTEXTE COMPLET de infix.hvn avec parse_app :
- Toutes les clauses (parse_atom, open_paren, parse_mul, parse_add,
  is_atom_start, step_app, continue_app, parse_app, to_expr)
- Les imports (heaven_parse.hvn, HP.TCons, HP.Toks, HP.Expr, HP.ELitI)
- Le contexte du loader qui charge les 30+ clauses

### Hypothese restante
Le crash est peut-etre :
- Une interaction entre evalEquation et l'accumulation multi-lignes du
  loader (la clause step_app est sur 2 lignes, avec indentation)
- Une profondeur de recursion de eval qui depasse la limite quand
  combinee avec les autres clauses
- Un cycle de definitions non detecte (mais 5 triviales OK, 8 complexes
  isolees OK)
- Un etat partage entre clauses (env, interner)

### Prochain bloc (session Zig gdb, 1 session)
1. Lancer gdb sur `heaven --eval-file infix_with_parse_app.hvn`
2. Attendre le SEGV (arrive au chargement, ~1-2s)
3. `bt 20` pour voir la stack (fonction + profondeur)
4. Si c'est evalEquation : instrumenter evalEquation (quelle clause)
5. Si c'est evaluate : profondeur de recursion
6. Le test discriminant minimal ne suffit pas -- il faut le contexte
   complet, donc gdb est obligatoire (instrumentation print = noyer).

### Bilan (12 blocs loader, 0 fix)
- 14 hypotheses eliminees (clause step_app, TCons construction, if,
  ADT, forward ref, appels imbriques, combinaisons isolees)
- 8 tests discriminants (tous passent, sauf le fichier complet)
- Le bug est dans le CONTEXTE COMPLET, pas dans une clause isolee
- gdb + core dump sur infix.hvn complet est la seule voie

## Diagnostic DEFINITIF (2026-10-26, session 2, print conditionnel)

Print conditionnel ajoute dans `evaluate` (`if depth % 100 == 0`).
Test avec infix.hvn + parse_app : SEGV immediat, AUCUN [EVAL].

### Conclusion DEFINITIVE
Le crash n'est PAS dans `evaluate`. `evaluate` n'est jamais appele
avant le SEGV. Le crash est dans **`evalEquation`** (parsing et
compilation de la clause) ou dans le **parser tree-sitter**.

### Ce que ca elimine
- Stack overflow par recursion runtime (evaluate jamais appele)
- Cycle de definitions au runtime
- Bug dans perform/handle (pas dans evaluate)
- Toute modification de `evaluate` (callback expr_eval, etc.)

### Le vrai point d'entree
- `evalEquation` dans heaven_expr.zig (parse et eval d'une clause)
- Ou le parser natif (NativeParser) qui produit l'AST
- Ou tree-sitter si la clause est mal parsée

### Prochaine session (session Zig gdb, OBLIGATOIRE)
1. gdb -nx + core dump sur infix.hvn avec parse_app
2. `bt 20` pour voir la fonction exacte au SEGV
3. Si evalEquation : instrumenter le parsing de la clause
4. Si tree-sitter : verifier la grammar pour la ligne step_app

Le test discriminant minimal ne suffit pas, et `evaluate` n'est pas
le probleme. C'est AVANT evaluate.

### Bilan loader (13 blocs, 0 fix)
- 14 hypotheses eliminees (clause, TCons, if, ADT, forward ref)
- 8 tests discriminants (tous OK sauf contexte complet)
- Print conditionnel confirme : evaluate jamais appele
- **Le crash est dans evalEquation / parser, pas evaluate**
- gdb obligatoire pour la suite

### Ce qui a ete livre cette session
- 10 fixes reels (P1 if, P2 tparams, T2 lambda body multi-arg,
  arrow lexer, compound assignment, annotation type, 3 stubs TODO,
  formatJudgment, 4 dead patterns)
- 16 docs graves
- 18/18 baseline preservee, tree propre

## Localisation finale (2026-10-26, print evalEquation)

Avec print dans evalEquation : [EQ step_app] apparait (lhs='step_app
f (HP.TCons tk rest)', rhs=128 chars) puis SEGV immediat.

### Le crash est dans le corps de evalEquation sur step_app
Suspects identifies (lignes relatives dans evalEquation) :
- L.116 : `const id = try self.parseExpression(tok)` -- parse des
  tokens du LHS (avec HP.TCons imbrique)
- L.128 : `expr.nativeToSExpr(gs, self.allocator)` -- conversion
  du guard (le RHS contient `== 1` a profondeur 0)
- L.137/154/157 : `parseExpression(sexpr/out/gs)` -- parse du guard

### Hypotheses
1. `parseExpression` sur `step_app f (HP.TCons tk rest)` : le parser
   natif (nativeToSExpr / NativeParser) crashe sur le pattern
   HP.TCons imbrique 2 niveaux.
2. `nativeToSExpr` sur le RHS `if (is_atom_start (HP.TCons tk rest))
   == 1 then ... else ...` : le `==` a profondeur 0 (dans le then)
   est peut-etre mal splitte, ou le parser crashe sur l'imbrication.
3. `splitTopLevelEq` sur le RHS : le `== 1` est a profondeur 2
   (dans if (...)), donc splitTopLevelEq ne devrait pas le voir.
   Mais le `if` est infixe, le parser natif peut traiter mal.

### Prochaine session (gdb OBLIGATOIRE)
1. gdb -nx + core dump sur infix.hvn avec parse_app
2. `bt 20` au SEGV : quelle fonction de parseExpression/nativeToSExpr
3. Si nativeToSExpr : instrumenter le lexer (quel token)
4. Si splitTopLevelEq : verifier le toggle in_str sur `== 1`
5. Le fix est dans parseExpression ou nativeToSExpr (parser natif),
   pas dans le loader ni dans evaluate.

### Bilan loader (17 blocs, 0 fix)
- 16 hypotheses eliminees (clause step_app, TCons construction, if,
  ADT, forward ref, appels imbriques, evaluate, runtime)
- Crash dans evalEquation sur step_app, dans parseExpression ou
  nativeToSExpr (parsing des tokens/guard, pas eval)
- gdb + core dump est la seule voie (le parser crashe sur une forme
  qu'on n'a pas encore identifiee -- probablement HP.TCons imbrique
  dans un argument de ==, ou le if infixe avec == a profondeur 2)

### Ce qui a ete livre cette session
- 10 fixes reels (P1 if, P2 tparams, T2 lambda body multi-arg,
  arrow lexer, compound assignment, annotation type, 3 stubs TODO,
  formatJudgment, 4 dead patterns)
- 18 docs graves
- 18/18 baseline preservee, tree propre
- 16 hypotheses loader eliminees, diagnostic jusqu'a evalEquation
