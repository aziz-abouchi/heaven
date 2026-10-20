# Stdlib consolidation (2026-10-20)

## Inventaire mesure

| Catégorie | Fichiers | Action |
|---|---|---|
| **Piliers** (>=3 users) | json/parse, net/http_client, string, ontology, mpst | Ne pas toucher |
| **Utilisés** (1-2 users) | fs, http_body, option, net/{dns,dns_parse,http,ip,tcp,udp,urlencode,https}, effects, fantasy_land | Garder |
| **Test-only non importé** | optics, free | **Tests réinventent** (test_lens, test_free) |
| **Vraiment morts** (0 users, 0 test) | profunctor, transformers, json/build | `stdlib/legacy/` |
| **lib/ quasi-mort** | lib/list, lib/prelude (1 user: README vision) | `lib/legacy/` |
| **core/** entier | 0 users hors site/ | `core/legacy/` (session séparée) |

## Réinvention confirmée : 2 paires

### Lens
- `stdlib/optics.hvn` : `data Lens s a`, `MkLens`, `view`, `set`, `over`, `lens_compose`, `Prism`, `iso`
- `tests/test_lens.hvn` : `lens_snd`, `lens_pp_fst`, `set_via`, `mk`, **sans importer optics**
- Décision : étendre `optics.hvn` avec `lens_fst`, `lens_snd`, `lens_pp_fst` (helpers de base), puis réécrire `test_lens.hvn` pour importer. **1 session**.

### Free
- `stdlib/free.hvn` : `Free`, `free_pure`, `free_bind`, `free_fold`, `free_map`
- `tests/test_free.hvn` : stack machine spécialisée (`p1`-`p4`), `run`, `run_trace`, n'utilise pas `Free`
- Décision : réécrire `test_free.hvn` sur `Free` + handler `free_fold`. Si trop divergent, `stdlib/free.hvn` reste exemple et le test devient `tests/test_free_stack.hvn` (documenté comme cas d'usage). **1 session**.

## Comparaison vs meilleurs langages

| Axe | Haskell | Idris 2 | Rust | Erlang | Heaven |
|---|---|---|---|---|---|
| Modules séparés | oui | oui | oui | oui | oui |
| Réinvention dans tests | rare (QuickCheck) | rare | rare | rare | **fréquent** |
| HKT dispatch natif | oui (GHC) | oui | non | non | **oui (V1b 25/25)** |
| MPST dans stdlib | non (package) | non | non | non | **oui** |
| QTT enforced runtime | non | oui | non | non | **partiel** |
| Lens dans stdlib | non (package `lens`) | non | non | non | **oui (optics)** |

**Verdict** : Heaven a déjà le **contenu** supérieur (HKT, MPST, QTT parse, optics).
La faiblesse est **disciplinaire** : les tests contournent la stdlib. Le problème
est de convention, pas de capacité.

## Plan de consolidation (3 sessions)

### S1 : ménage (30 min)
- `mkdir -p stdlib/legacy lib/legacy`
- `git mv` : profunctor, transformers, json/build → `stdlib/legacy/`
- `git mv` : lib/list, lib/prelude → `lib/legacy/`
- Vérif : `--run-tests tests` reste vert

### S2 : réconcilier Lens (1 session)
- Étendre `optics.hvn` : `lens_fst`, `lens_snd`, `lens_pp_fst`
- Réécrire `test_lens.hvn` : `import "stdlib/optics.hvn" as O` + tests sur O
- Baseline : `--run-test test_lens.hvn` = 12/12

### S3 : réconcilier Free (1 session)
- Réécrire `test_free.hvn` sur `Free` + `free_fold`
- Si impossible (stack machine ≠ Free), documenter comme 2 cas distincts
- Baseline : `--run-test test_free.hvn` = 6/6

## Non-objectifs

- `core/` : 0 users live, chantier séparé (legacy ou revival)
- Unification `lib/` vs `stdlib/` : `lib/heaven_eval`/`heaven_parse` sont core runtime, garder
- Ajout de modules : après S1-S3, mesurer si l'API optics/free convient avant d'étendre


## Mise a jour S2 (2026-10-20)

`stdlib/optics.hvn` est un **faux doublon** : API `MkLens`/`lens_compose`
distincte de `core/std/lens.hvn` (`lens_fst`/`set_via`, charge auto).
`tests/test_lens.hvn` teste l'API core, pas optics. optics -> legacy.

Piege identifie : `core/std/*.hvn` est charge implicitement (uni_ingest
ou cache). Les fonctions `lens_fst`, `view`, `over`, `pair`, `fst`, `snd`
sont disponibles SANS `import`. Ce n'est pas documente.


## Mise a jour S3 (2026-10-20)

`stdlib/free.hvn` (Free/FPure/FFree tag-encoded) = faux doublon.
`tests/test_free.hvn` teste `core/std/free.hvn` (Push/Add/LogOp/run_stack,
auto-load), API distincte. stdlib/free -> legacy.

Constat general : `core/std/*.hvn` est charge implicitement pour les
tests (`--run-test`). Tous les "0 users" de stdlib/* sont en fait des
API alternatives mortes, jamais importees. Le canon est `core/std/`.
