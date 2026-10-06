# tests/experimental/

Fichiers `.hvn` qui dépendent de fonctionnalités **non encore
implémentées** ou qui documentent des comportements en cours de
stabilisation. Ils sont **exclus** de `heaven --run-tests tests/`
(qui ne parcourt que les fichiers du dossier racine, pas les
sous-dossiers).

Conservés comme spécimens — cas d'usage cibles qui serviront de
critères de validation quand les fonctionnalités seront là.

## Tests cibles (fonctionnalités à venir)

| Fichier | Dépend de | Statut |
|---|---|---|
| `01_types.hvn` | CIC (`Type(0)`, `refl Type`) non branché au shell | 🚧 |
| `02_recursion_tco.hvn` | `let rec`, TCO | 🚧 |
| `03_streams.hvn` | `Stream.cons`, `thunk` (paresse) | 🚧 |
| `cyc_a.hvn`, `cyc_b.hvn` | Détection de cycles d'import | 🚧 |

## Tests en cours de stabilisation (diagnostiqués 2026-10-06)

| Fichier | Échec | Statut |
|---|---|---|
| `comprehensions.hvn` | `for_filter_map` : `filter` imbriqué dans `for` | 🚧 |
| `exp_util.hvn` | `export public` hors import (no-op) | 🚧 |
| `features_smoke.hvn` | `features_kanren_query` (moteur kanren incomplet) | 43/44 |
| `proof_and_semantic_tests.hvn` | `entity` : mot-clé inexistant | 🚧 |
| `regression.hvn` | affichage `let` imbriqué (évaluation OK) | 🚧 |
| `test_vec_dependent.hvn` | `Vec` dépendants, en cours d'écriture | 🚧 |
| `unlower_spec.hvn` | `spec` : mot-clé inexistant | 🚧 |

## Objectif

Faire passer ces tests un par un, puis les **remonter dans
`tests/`**. Chaque fichier qui passe et qui est stable doit sortir
de `experimental/`.

## Ne pas faire

- Ne pas ajouter de tests ici sans raison : préférer `tests/`.
- Ne pas laisser un fichier ici indéfiniment sans documentation.
- Ne pas y mettre un fichier pour "cacher" un échec : c'est un
  répertoire de travail, pas une poubelle.

## Voir aussi

- `docs/spec/_syntax_gaps.md` — bugs ouverts documentés
- `docs/ROADMAP.md` — chantiers en cours
