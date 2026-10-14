# Bug : (+ 1 2 3 4) dans une lambda

**Date** : 2026-10-14
**Statut** : identifie, non corrige. Independant de C3/A-3a.

## Symptome

| Contexte | Resultat |
|---|---|
| (+ 1 2 3 4) direct | 10 (via e-graph) |
| (task (lambda s -> (+ 1 2 3 4))) | 0 |

Le meme code donne 10 en top-level mais 0 dans une tache, meme
avec un budget enorme (schedule 100). Aucun rapport avec la
preemption : c'est un bug d'arité sur le magic +.

## Cause probable

Le chemin top-level beneficie d'une simplification e-graph qui
reassocie (+ 1 2 3 4) en (+ (+ (+ 1 2) 3) 4). Le chemin lambda
-> apply n'a pas cette simplification : evalMagic("+", [1,2,3,4])
est appele avec 4 args, ce que le magic binaire ne supporte pas
-- il retourne 0 silencieusement.

## Fix propose

- Option A : le magic + accepte une arite variable (fold).
- Option B : le parser reecrit (+ a b c d) en (+ (+ a b) c) d)
  pour tous les chemins (pas seulement e-graph).
- Option C : retourner une erreur au lieu de 0 (plus honnete).

Option B est la plus coherente (meme semantique partout).

## Contournement actuel

Dans les tests C3, utiliser + binaire imbrique :
    (+ (+ 1 2) (+ 3 4))

Voir tests/test_preemptive_split.hvn.
