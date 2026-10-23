# Cascade if > 5-6 niveaux -- crash parser (2026-10-24)

## Symptome
Un motif de cascade if profonde (>5-6 niveaux imbriques) dans
une fonction .hvn provoque un SEGV ou panic au chargement ou a
l evaluation. Le code est syntaxiquement valide, mais le parser
ou l evaluateur natif depasse une profondeur.

## Cas observes
1. eval_sym avec 10 if imbriques (primitives + - * = <) :
   test_eval crashe a 134 (panic). Fix : table plate prim_ops + in_list.
2. is_cmp avec 6 if imbriques (== != < > <= >=) :
   SEGV au chargement de lib/parse/infix.hvn. Rollback.
3. lambda / parse_atom / parse_if : cycle de definitions,
   meme famille (profondeur de recursion parser).

## Patterns de fix

### 1. Table plate + lookup
Remplacer la cascade par une liste + une fonction de recherche :
  prim_ops _ = (cons "+" (cons "-" ... nil))
  in_list s (cons x rest) = if (= s x) then 1 else (in_list s rest)
  eval_sym s env = if (= (in_list s (prim_ops 0)) 1) then (VPrim s) else ...
Marche pour eval_sym (verifie, 16/16 tests).

### 2. Sous-fonctions (cascade divisee)
Decouper la cascade en sous-fonctions de 5 if max :
  prim_arith op x y = (if (= op "+") ... 5 if max)
  prim_cmp op x y = (if (= op "==") ... 5 if max)
  prim_fin op x y = (if arith?) then (prim_arith ...) else (prim_cmp ...)
Marche pour prim_fin (verifie).

### 3. Fonction de dispatch par listes
Pour un parseur (parse_cmp), le fix reste a trouver :
les deux patterns ci-dessus ne suffisent pas, SEGV persiste.
Piste : separer la collecte de tokens (flat) du parsing (recursif).

## Prevention

- Regle : max 5 if imbriques par fonction .hvn.
- Au-dela : table plate (pattern 1) ou sous-fonctions (pattern 2).
- Documenter le pattern dans les review checklist.

## References
- docs/spec/_lambda_parser_bug.md (cycle lambda)
- docs/spec/_emancipation_roadmap.md E1.2 (cycle parse_atom/parse_if)
