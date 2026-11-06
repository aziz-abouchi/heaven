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

## Selfhost — freeze découvert (2026-11-06, session 13)

### Freeze reproductible
`read_file "lib/heaven_parse.hvn"` (209 lignes) + `HP.parse_file (HP.lex ...)` **fige la machine** (distribution Guix complète). Test `/tmp/diag_self.hvn`.

### Tests courts (safe)
String hardcodée (`data Tok = TIntTok Int`, etc.) : **rc=0, pas de freeze**.
Mais `data Tok = TIntTok Int | TSymTok Str` échoue (0 expr parsée).

### Diagnostic
- `data X = A` : parse ✅
- `data X = A | B` : **échoue** (le `|` n'est pas géré par `parse_data` dans `heaven_parse.hvn`)
- Sur fichier réel : boucle infinie (probablement `parse_data` sur `|` → récursion sans progrès)

### État selfhost réel (mesuré)
| Élément | État |
|---|---|
| `bin/heaven.hvn` (15 l.) → `compile-qbe` → ELF | ✅ (2.3s, exit codes OK) |
| `lib/heaven_parse.hvn` (209 l.) | ✅ lexer + parse_one + parse_top, `data X = A` OK |
| `lib/heaven_eval.hvn` (96 l.) | ✅ 17 prims, VRecClosure, test 3/3 |
| `tests/test_selfparse.hvn` | 3/3 (1 test actif, 2 SKIPPED) |
| Self-parse complet de `heaven_parse.hvn` | ❌ **freeze** (forme `data \|`) |

### Prochaine session (14)
1. **`parse_data` dans `heaven_parse.hvn`** : ajouter `|` (CHOIX de constructeurs). ~30 min.
2. **Test avec string courte** (`data Tok = A | B`, PAS de `read_file`) — safe.
3. **Test full-file** : `timeout 10` OBLIGATOIRE.
4. **Si OK** : le self-parse complet doit marcher (2 tests SKIPPED débloqués).
5. **Si freeze encore** : cutoff, chantier reporté.

**Règle** : jamais `read_file "*.hvn"` sans `timeout`.

## Selfhost — diagnostic FINAL (2026-11-06, session 13)

### Le parser selfhosté fonctionne
- `data Tok = A` : ✅
- `data Tok = A | B` : ✅
- `data Tok = A Int | B Str` : ✅
- `parse_top (TSymTok "foo" ...)` : ✅

**`data` multi-ctor est parsé correctement par `heaven_parse.hvn`.**

### Le vrai bug : `read_file` ne fonctionne pas
Isolation (session 13) :

| Test | Résultat |
|---|---|
| `read_file "/tmp/s10.hvn"` (10 lignes, 500 o) + `string_length > 0` | ❌ **string vide** |
| parse 10 lignes hardcodées (via `tr '\n' ' '`) | `InvalidSyntax` (string mal formée) |
| parse 20 lignes + `read_file` | 🔴 **freeze (timeout)** |

**Cause probable** : `read_file` (dans `tests/test_selfparse.hvn`) utilise
`raw_alloc 65536` + `io_read` + `string_of_bytes`. Un des trois retourne
0 ou échoue silencieusement, produisant une string vide.

Le parser `heaven_parse.hvn` boucle ensuite sur la string vide (probablement
`lex_loop` sur longueur 0 + `parse_file` récursif infini).

### État réel selfhost (mesuré)
| Élément | État |
|---|---|
| `bin/heaven.hvn` → `compile-qbe` → ELF | ✅ |
| `lib/heaven_parse.hvn` (209 l., lexer + parser) | ✅ (data multi-ctor OK) |
| `lib/heaven_eval.hvn` (96 l., 17 prims) | ✅ |
| **`read_file` (raw_alloc + io_read + string_of_bytes)** | ❌ **string vide** |
| Self-parse complet (avec `read_file`) | ❌ **freeze** |

### Prochaine session (14)
1. **Diagnostiquer `read_file`** : `raw_alloc`, `io_read`, `string_of_bytes` — lequel échoue ?
2. **Test isolé** : `raw_alloc 100` → `string_length` = ? (doit être > 0)
3. **Test `io_read`** : lire un fichier de 10 octets, vérifier `n == 10`
4. **Si `read_file` OK** : self-parse complet (avec `timeout 10`)
5. **Si freeze encore** : cutoff selfhost, chantier reporté

**Règle** : `timeout` obligatoire sur tout test `read_file` + `parse`.

### Ce qui N'EST PAS le problème
- Le parser `data` multi-ctor → fonctionne
- Le lexer → fonctionne
- `parse_top` → fonctionne
- `expr_count`, `expr_eq`, `parse_file` → fonctionnent
