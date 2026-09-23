# tests/

Tests exécutables via `heaven --run-tests tests/` (parcourt uniquement les
`.hvn` du dossier, pas les sous-dossiers).

## Convention

- **Un `.hvn` = un fichier test**, évalué ligne par ligne par le runner.
- Les lignes vides, `#`, `--`, `//`, `;;` sont ignorées.
- Un test qui échoue retourne un `✗` ; exit code 1 si au moins un échoue.

## Dossiers annexes

- `experimental/` — fichiers `.hvn` dépendant de features non implémentées.
  Exclus de la passe automatique. Voir son `README.md`.
- `hvn_pl/`, `legacy_c/` — legacy, non exécutés par `--run-tests`.
- `run_tests.sh`, `run_transform_tests.sh` — scripts shell historiques.
- `type_checker_test.zig` — test Zig (non `.hvn`).

## Ajouter un test

1. Créer `tests/mon_test.hvn` avec un contenu comme :

theorem mon_thm : x + 0 = x
prove mon_thm by { simplify }

2. Lancer `zig build test-files` (ou `./zig-out/bin/heaven --run-tests tests/`).
