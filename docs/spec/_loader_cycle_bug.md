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
