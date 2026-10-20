# Heaven stdlib v2 — RFC (2026-10-20)

## Statut
Reconnaissance R1-R4 terminée. Stratégie : consolidation + QTT sémantique.
Estimation honnête : 5-7 sessions (pas 3-4 — voir table coût partie 3).

## Objectif
Stdlib exhaustive, structurellement supérieure à Idris/Haskell/Erlang/Rust/Deno,
en exploitant QTT + HKT + Lens + MPST + effets.

## État réel (vérifié R1-R4, 2026-10-20)

| Brique | État | Tests | Verdict |
|---|---|---|---|
| HKT V1a (class/instance) | OK | 2/2 | réutilisable |
| HKT V1b (dispatch 3 étapes) | OK | 4+11+10=25/25 | réutilisable |
| Lens/optics | OK | 12/12 | `stdlib/optics.hvn` canon |
| Effets (commit e445f5d) | OK | — | réutilisable |
| MPST | OK | 10+3 | réutilisable |
| QTT (`linear`/`erased`/`many`) | parsé, check parse non-branché sur `heaven run` | 3 (`countSymUses`) | brancher, 1 session |
| `examples/vision/` (plateforme) | esquisse 14-16L | 0 | à rapatrier |
| Arbre canonique | 3 copies (`core/`, `site/repl/`, `stdlib/`) | — | à unifier |

Note : le prompt de continuité 2026-10-19 est obsolète sur HKT V1b
(dit "refusé, 2 sessions") — les tests passent.

## Architecture cible
stdlib/
  core/      algebra.hvn  resource.hvn  effect.hvn  lens.hvn  protocol.hvn
  data/      list.hvn  map.hvn  set.hvn  text.hvn  json/{parse,build}.hvn
  io/        console.hvn  file.hvn  path.hvn  process.hvn  env.hvn  clock.hvn
  net/       ip.hvn  udp.hvn  tcp.hvn  dns.hvn  http.hvn  tls.hvn
  platform/  wasm_freestanding.hvn  wasi.hvn  native.hvn

## Comparaison vs stdlibs existantes

| Axe | Idris | Haskell | Erlang | Rust | Deno | Heaven |
|---|---|---|---|---|---|---|
| QTT linéaire | oui | non | non | partiel | non | à construire |
| HKT dispatch | non | oui | non | non | non | **V1b ok** |
| MPST protocoles | non | non | non | non | non | **ok** |
| Effets algébriques | non | partiel | non | non | non | **ok** |
| wasm + natif | non | non | non | partiel | oui | **V1b** |

Heaven est le seul à intégrer les 5 axes. Ce n'est pas un axe unique
qui gagne, c'est l'intégration.

## Risques identifiés

- R1. QTT sémantique = 2-3 sessions, pas un bloc. `examples/vision/`
  illustre la tentation : syntaxe `linear` acceptée, sémantique absente.
- R2. `core/` est mort pour le binaire (0 import depuis `tests/`). Le
  promouvoir créerait un 4ᵉ arbre. Laisser en legacy sauf `site/repl/`.
- R3. `tests/scratch/` (57 fichiers) pollue la suite globale.
- R4. `stdlib/` contient 2 `.bak` (dns.hvn.local.bak, string.hvn.d2.bak)
  et 2 implémentations de Lens (`optics.hvn` canon, `lens.hvn` v0).

## Phases d'exécution

| # | Contenu | Sessions | Nature | Précondition |
|---|---|---|---|---|
| 0 | Nettoyage (2 .bak, 57 scratch archivés) | 0.5 | shell | — |
| 1 | Ce RFC | 0.5 | doc | — |
| 2 | QTT : brancher `expr_parser.zig:742` ou `LinearChecker` (types.zig:145) sur `heaven run` | 1 | .zig | Phase 1 |
| 3 | Rapatriement `examples/vision/` → `stdlib/platform/` | 1-2 | .hvn + .zig FFI | HKT V1b ok (fait) |
| 4 | Stratification `stdlib/` (déplacer fichiers) | 1 | shell | Phase 3 |
| 5 | Doc `STDLIB.md` v2 + `STATUS.md` | 0.5 | doc | Phase 4 |

**Total : 5.5-7 sessions**, pas 3-4.

## Préconditions / dépendances

- Phase 2 (QTT) **débloque** `class Resource a` (avec `acquire : a` linéaire
  et `release : a -> ()`) qui est la base des instances `platform/*`.
  Sans QTT sémantique, `platform/*` ne peut pas garantir `free` exactement
  une fois.
- Phase 3 (plateforme) **profite** de HKT V1b déjà livré. Ne pas refaire
  le dispatch — l'utiliser tel quel.
- Phase 4 (stratification) **bloquée** tant que Phase 2/3 ne sont pas
  stabilisées : déplacer des fichiers pendant un chantier sémantique
  casse les imports des tests.

## Non-objectifs (explicite)

- Rank-2 explicit (`forall p f. ...`) — voir `docs/spec/_hkt_rank2_plan.md`.
  Non requis pour la v2.
- Cubical/HoTT — multi-années, hors scope.
- Stubs macOS/Windows réels — `examples/vision/platform/*` reste
  déclaratif tant que le SDK n'est pas câblé.

## Ordre recommandé pour la session en cours

1. Commit ce RFC + les fixes docs (voir `docs/STATUS.md` et
   `docs/STDLIB.md`, à mettre à jour avec l'état R1-R4).
2. Phase 0 : nettoyage.
3. Phase 2 : chantier QTT (session dédiée, ne pas commencer en fin
   de session).
