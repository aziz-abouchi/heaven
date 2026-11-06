# Ce qui existe déjà (testé empiriquement)

> **But** : arrêter de perdre du temps à "faire" ce qui est déjà fait.
> Chaque entrée = un test empirique daté. À consulter **avant** un chantier.

**Dernière mise à jour** : 2026-11-06 (session 12)

## Runtime / évaluation — testés avec `--run-test`

| Feature | Résultat | Date |
|---|---|---|
| `add x y = x + y` | ✅ | 2026-11-05 |
| `fn name(params) = expr` | ✅ | 2026-11-05 |
| Curryfication `(f 1 2)` | ✅ 5/6 (edge case `(((f a) b) c)`) | 2026-11-05 |
| Thunks top-level `xyz = 3; xyz == 3` | ✅ (fix `9a301c7`) | 2026-11-05 |
| `(if c t e)` S-expr | ✅ (patch `5646dd0`) | 2026-11-06 |
| `(if c then t else e)` | ✅ | 2026-11-06 |
| `let x 42 body` (3-args) | ✅ | 2026-11-06 |
| `let x = 42 in body` | ✅ | 2026-11-06 |

## QTT — ENFORCED (pas un chantier)

**Fait au parse** (`expr_parser.zig:774`), pas via LinearChecker sur elab.

| Cas | Résultat |
|---|---|
| `linear` 1 usage | ✅ |
| `linear` 0 usage | ❌ LinearViolation |
| `linear` 2 usages | ❌ LinearViolation |
| `erased` 0 usage | ✅ |
| `erased` 1 usage | ❌ LinearViolation |
| `many` 0 usage | ✅ |
| `many` 2 usages | ✅ |

Tests : `tests/qtt/let_quantities_{ok,viol}.hvn`.
Limitation : message brut (`error.LinearViolation`) au lieu de pédagogique.

## `heaven check` (tree-sitter) — INCOMPLET

**48 flags sur 148 tests `.hvn` = faux positifs.** Cause : `grammar.js` ne
couvre pas la syntaxe que `expr_parser.zig` accepte.

| Pattern | grammar | vrai parser |
|---|---|---|
| `fn name(params) = expr` | ✅ | ✅ |
| `test "name": expr` | ✅ | ✅ |
| `(if c t e)` | ✅ | ✅ |
| `prove name by { }` | ✅ | ✅ |
| `skill name` | ✅ | ✅ |
| Bitstrings `<<...>>` | ❌ (rollback ×2) | ✅ |
| `lambda v k ->` multi-params | ❌ (conflit) | ✅ |
| Scheduler `let+yield` | ❌ | ✅ |

**Ne PAS utiliser `heaven check` en gate CI sur `tests/*.hvn`.**

## QTT — ENFORCED (pas un chantier)

**Fait au parse** (`expr_parser.zig:774`), pas via LinearChecker sur elab.

| Cas | Résultat |
|---|---|
| `linear` 1 usage | ✅ |
| `linear` 0 usage | ❌ LinearViolation |
| `linear` 2 usages | ❌ LinearViolation |
| `erased` 0 usage | ✅ |
| `erased` 1 usage | ❌ LinearViolation |
| `many` 0 usage | ✅ |
| `many` 2 usages | ✅ |

Tests : `tests/qtt/let_quantities_{ok,viol}.hvn`.
Limitation : message brut (`error.LinearViolation`) au lieu de pédagogique.

## `heaven check` (tree-sitter) — INCOMPLET

**48 flags sur 148 tests `.hvn` = faux positifs.** Cause : `grammar.js` ne
couvre pas la syntaxe que `expr_parser.zig` accepte.

| Pattern | grammar | vrai parser |
|---|---|---|
| `fn name(params) = expr` | ✅ | ✅ |
| `test "name": expr` | ✅ | ✅ |
| `(if c t e)` | ✅ | ✅ |
| `prove name by { }` | ✅ | ✅ |
| `skill name` | ✅ | ✅ |
| Bitstrings `<<...>>` | ❌ (rollback ×2) | ✅ |
| `lambda v k ->` multi-params | ❌ (conflit) | ✅ |
| Scheduler `let+yield` | ❌ | ✅ |

**Ne PAS utiliser `heaven check` en gate CI sur `tests/*.hvn`.**

## Selfhost (état 2026-11-06)

| Fichier | Lignes | Rôle |
|---|---|---|
| `bin/heaven.hvn` | 15 | CLI stub (argv → exit code) |
| `lib/heaven_eval.hvn` | 96 | Évaluateur (17 prims, VRecClosure) |
| `lib/heaven_parse.hvn` | ? | Parser partiel |
| `tests/test_heaven_eval_prims.hvn` | ? | Tests primitives |

**Ce qui N'EXISTE PAS** : parser complet, type-checker, codegen, compilateur.
**Ce qui existe** : preuves de concept (briques), pas un compilateur.

## Build / CI

| Élément | État |
|---|---|
| `zig build` | ✅ (~15 s incrémental) |
| `zig build test` | ✅ (406 tests) |
| `check_all.sh` | ✅ PROJET SAIN (17 ✓) |
| `test_all_hvn.py` | ✅ 171 tests `.hvn` |
| `build.sh` | ✅ (fix `mkdir -p site/repl`) |
| `deploy.yml` | ✅ v2 publié sous `/v2/` |

**`time` recommandé** : `bash check_all.sh` (55s), `zig build` (15s).
