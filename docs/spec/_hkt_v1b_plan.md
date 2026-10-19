<!-- HEAVEN:hkt-v1b-plan -->
# HKT V1b — dispatch typeclass (plan 2026-10-19)

## État

V1a commité (`bde8adc`) : `class Name [param]` et `instance C T`
déclaratifs, stockés dans `engine.class_names` et
`engine.instance_pairs`. Magics `@class_count`/`@instance_count`.
**0 dispatch** : `fmap f xs` ne marche pas.

## Ce que V1b demande

1. **Inférence de type pour `f`** : `f a -> f b` — le tree-walker
   n'infère rien aujourd'hui. Soit brancher `elab.zig` (qui infère
   sur le kernel), soit faire du **matching structurel** :
   `f = List` -> `fmap_list`, `f = Maybe` -> `fmap_maybe`.
2. **Résolution d'instance** : `(C, T)` -> `op_T`. Nécessite la
   table `engine.instance_pairs` (faite en V1a) + une convention
   `op_T` dans l'env.
3. **Instances multiples** : `Int` Monoid+ vs Monoid*. Conflit à
   trancher (suffixe ? type wrapper ?).

## 2 approches

### A — Matching structurel (recommandé, 2 sessions)
Au call `fmap f xs`, si `f` est un `sym` connu (`List`, `Maybe`),
chercher `fmap_List` dans l'env. Pas d'inférence complète. Suffit
pour 90% des cas. V1c (contraintes `Functor f =>`) devient un
checker simple : `fmap` déclaré `Functor f => ...`, vérifier que
`f` a une instance `Functor`.

### B — Inférence via elab (3-4 sessions)
Brancher `elab.zig` sur `engine_expr`. Inférence de type réelle.
Plus riche mais risque de découvrir que `elab` ne fait pas
l'inférence nécessaire (il type-check, il n'infère pas).

## Reco : A. Effort 2 sessions. V1c devient 1 session après.

## Ce qui manque avant V1b
Rien de bloquant. V1a a la table. Mais la décision A vs B est
structurante (matching structurel = figé, inférence = générique).

## Statut 2026-10-19 (fin de session)

- **V1b pas 1** ✅ `@resolve_instance C T op` -> `op_T` ou "" (`62155ce`, 4 tests).
- **V1b pas 2** ✅ `@dispatch_instance C T op args...` -> `op_T(args...)`, type T en string (`1ba6aa4`, 4 tests).
- **V1b pas 3** ✅ arguments `.sym` acceptés (`fmap List f xs`), en plus de `.lit.str` (`4841c6b`, 3 tests).
- **V1c** 🚧 contraintes `Functor f =>` vérifiées. 1 bloc, après V1b pas 3.

Total : 11 tests verts (`test_hkt_v1b_step1.hvn`, `_step2.hvn`, `_step3.hvn`).

