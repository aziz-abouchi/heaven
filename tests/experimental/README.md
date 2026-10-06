# Tests expérimentaux / obsolètes

Ces tests **ne sont pas exécutés par le CI**. Ils sont conservés pour
référence mais ne reflètent pas l'état stable du langage.

## Contenu

- `comprehensions.hvn` — 1 test échoue sur `for_filter_map` (bug du
  désugrage `for` avec `filter` imbriqué, non résolu).
- `exp_util.hvn` — test d'`export` hors contexte d'import (comportement
  no-op, non tranché).
- `features_smoke.hvn` — 43/44 ; le seul échec est `features_kanren_query`
  (moteur kanren incomplet).
- `proof_and_semantic_tests.hvn` — utilise `entity`, mot-clé inexistant
  dans le langage actuel.
- `regression.hvn` — tests sur le formatage `let` imbriqué (l'évaluation
  marche, l'affichage non).
- `test_vec_dependent.hvn` — tests sur les `Vec` dépendants, en cours
  d'écriture.
- `unlower_spec.hvn` — utilise `spec`, mot-clé inexistant.

## Objectif

Faire passer ces tests un par un, puis les remonter dans `tests/`.
Chaque fichier qui passe et qui est stable doit sortir de
`experimental/`.

## Ne pas faire

- Ne pas ajouter de tests ici sans raison : préférer `tests/`.
- Ne pas laisser un fichier ici indéfiniment sans documentation.
