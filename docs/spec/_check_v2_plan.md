# Check v2 — détection des variables non définies (v0.1)

**Date** : 2026-11-09
**Statut** : v0.1 implémentée, tests de non-régression inclus.

## Contexte

Avant v2, `heaven check` ne détectait AUCUNE variable non définie.
Exemples silencieux (tous exit=0 avant) :

    x = y + 1       -- y unbound
    f n = m + 1     -- m unbound
    f x = y + 1     -- y unbound

## Approche v0.1

`scope_check.checkUnbound` walk le store exhaustivement :

1. Collecte les noms définis (.bind.payload, .lambda.payload,
   .function.payload, .letrec.payload).
2. Vérifie chaque .call/.apply dont le payload est un Sym.
3. Filtres anti-faux-positifs : @magic, _hole, digit-en-tête, '.' (nom
   qualifié), builtins (liste dupliquée de scope.addBuiltins).

Appelé depuis `runCheck` (src/commands/check.zig) après
`typer.checkAll()`.

## Limitation v0.1

Un paramètre local qui n'apparaît PAS comme .lambda/.function/.bind
dans le store sera signalé à tort. Non observé sur les cas testés
(add x y = x + y passe).

## Si régression

Le walker exhaustif peut générer des faux positifs. Dans ce cas :
- Bisect : commenter `scope_check.checkUnbound` et vérifier que
  le fichier passe avec l'ancien check.
- Si oui → le walker est trop strict, ajuster les filtres.
- Si non → le walker n'est pas en cause, autre chose a régressé.

## Tests

- 6 cas unitaires (4 doivent échouer, 2 doivent passer).
- Non-régression : add x y = x + y (0 erreur).
- Non-régression : tests/tool_registry/registry.hvn (24/24).
