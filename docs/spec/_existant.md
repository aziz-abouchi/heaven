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


## IO — `read_file` cassé (2026-11-06, session 14)

### Bug confirmé
`read_file` retourne **vide** sur fichier de 500 octets (test `string_length > 0` échoue).
Cause : `raw_alloc 65536` + `io_read` + `string_of_bytes` — un des trois échoue
silencieusement.

**Symptôme** : parser freeze sur string vide (`lex_loop` + `parse_file` en boucle).

### Pourquoi pas de backpressure
`read_file` = buffer fixe + 1 appel bloquant + conversion tout-en-un. Pas de
chunks, pas de yield, pas de rétroaction. Backpressure structurellement impossible.
### Migration IO as effects (session 15+)
perform (ReadBytes fd n) -> Result Bytes IoError
perform (WriteBytes fd bytes) -> Result Unit IoError
Handler 3 modes : Sync local, Async (epoll/kqueue), Remote (distribué).
Pull : Stream a + perform Next. Push : Channel a borné + send/recv.
Plan : S15 ReadBytes (2h), S16 migrer read_file (2h), S17-18 Stream/Channel, S19+ distribué.
Discipline : timeout obligatoire sur read_file + parse.

## Selfparse — read_file fixé (2026-11-06, session 15)

### Fix
`read_file` remplacé par `(perform "ReadFile" path)` dans `tests/test_selfparse.hvn`.
`defaultIOHandler` (dans `src/core/io_handler.zig`) gère déjà `"ReadFile"` via
`readFileAlloc` (1 Mo). **Fonctionne.**

### Résultat
`tests/test_selfparse.hvn` : **6/6** (3 anciens + 3 data).
- `SELF-PARSE equation simple` : ✅
- `SELF-PARSE data simple` : ✅
- `SELF-PARSE data multi-ctor` : ✅
- `SELF-PARSE data args` : ✅

### Freeze résiduel (parser, pas IO)
`HP.parse_file (HP.lex (read_file "lib/heaven_parse.hvn"))` (209 l., 12 Ko) :
**freeze** après 10s de timeout. Test isolé : `timeout 3` sur 50 lignes freeze aussi.

**Cause probable** : le parser boucle sur une forme dans les 50 premières lignes.
À isoler par chunks (10, 20, 30, 40, 50) avec `timeout 3` par test.

### Session 16+
1. Isoler le chunk qui freeze (5 tests × timeout 3s = 30s max).
2. Identifier la forme (ligne N+1 du chunk).
3. Patch `heaven_parse.hvn` (probablement `data_ctors2` sur type imbriqué).
4. Test self-parse complet avec `timeout 10`.
5. Si OK : débloquer les 2 tests SKIPPED.

**Discipline** : `timeout` obligatoire, un chunk à la fois.

## Selfparse — freeze isolé au cumul 1-17 (2026-11-06, session 16)

### Isolation précise
| Test | Résultat |
|---|---|
| `head -14` | ✅ 3/3 |
| `head -15`, `head -16` | 2/3 (count ≠ 1, normal) |
| **`head -17`** | 🔴 **freeze** (rc=137) |
| Ligne 17 seule | ✅ 2/2 |
| Lignes 14+17 | ✅ 2/3 (pas freeze) |
| Lignes 14-17 | ✅ 2/3 |

**Le freeze nécessite le cumul de ~13-16 lignes + ligne 17.** Aucune isolation ne
freeze. C'est un **stack depth** (profondeur de récursion parser).

### Cause probable
- `lex_loop` (l.13) : **8 if imbriqués** sur une seule ligne (récursion profonde)
- `lex_is_space` (l.17) : **3 if imbriqués** de plus
- Combiné : 11 niveaux de récursion, + les 16 expressions précédentes en pile

### Plan session 17
1. Augmenter `@threadStackSize` du thread parser (5 min, gagne 10x)
2. Si insuffisant : réécrire `lex_loop` en tail-call (TCO supporté, ch. 5)
3. Si encore : limiter profondeur + compteur

**Discipline** : `timeout -s KILL` obligatoire, chunks de ≤ 17 lignes.

### Causes précises (session 17+)
1. **`parse_file` non-TCO** : `(ECons e (parse_file rest))` — récursion dans argument
2. **`expr_count` non-TCO** : `(+ 1 (expr_count rest))` — mais `expr_count_go` existe
3. **Stack par défaut Zig** : pas de `stack_size` dans `main.zig` (8-16 Ko)

**`max_recursion_depth = 1000`** existe (`engine_expr.zig:428`) mais n'est **pas atteint** — le freeze est un stack overflow avant le check.

### Fix proposé (session 17)
1. `parse_file` en TCO (10 lignes, accumulateur `es_rev`)
2. `tests/test_selfparse.hvn` utilise `expr_count_big` (1 ligne)
3. Si insuffisant : `stack_size` dans `main.zig`
4. Test `timeout -s KILL 5` sur `head -17` puis full-file

### Session 17 — TCO `parse_file` ✅ (mais stack au-delà)
- `parse_file` en TCO (`parse_file_go` + `es_rev`) : **`head -17` passe** (commit `e8dd778`).
- `head -18` freeze encore (cumul 1-18).
- Isolation `l.18` seule : [à compléter selon sortie].
- Si cumul : stack overflow sur 15 fonctions mutuellement récursives
  (`parse_top`, `parse_head`, `parse_args`, `parse_arglist`, `parse_one`, ...).
  Fix = `stack_size` dans `main.zig` OU TCO sur toutes (2-3 sessions).

### Leçon
TCO sur `parse_file` corrige **1** des 16 fonctions mutuellement récursives.
Le parser complet nécessite TCO sur **toutes** ou une stack beaucoup plus grande.

### Isolation session 17 (final)
- `head -17` seul : **3 exprs** parsées (data Tok, data Toks, lex_is_space) ✅
- `head -17 + l.18` : **freeze** (rc=137)
- `l.18` seule : **passe** (2/2)
- `head -17` seul : passe
→ Interaction entre **deux defs avec if imbriqués** consécutifs.

### Cause probable (session 18)
`def_body_if` (l.145) ou `parse_if` (l.149+) : récursion cyclique quand deux
expressions contenant `if` se suivent. Le premier `if` consomme mal le `rest`
et laisse un token, le second `if` boucle dessus.

### Plan session 18 (30 min probable)
1. Isoler `l.17 + l.18` (safe, timeout 3)
2. Si freeze : réécrire `def_body_if`/`parse_if` en TCO ou fix du `rest`
3. Test self-parse complet avec `timeout -s KILL 10`
4. Si OK : débloquer les 2 tests SKIPPED, commit final

**État acquis** : TCO `parse_file` (`e8dd778`), `read_file` (`perform "ReadFile"`),
`data` multi-ctor (3 tests). Freeze restant = 1 interaction de defs avec if.

### Session 18 — isolation exhaustive (bug state-dependent)
Tests safe (timeout 2-3s KILL) :

| Test | Résultat |
|---|---|
| `data Tok` + 2 if imbriqués | ✅ 2 exprs |
| `data Tok` + 3 if imbriqués | ✅ 2 exprs |
| `3 if` en queue + `data` | ✅ 2 exprs |
| `3 if` en queue seul | ✅ 1 expr |
| `(= b N)` + 3 if | ✅ 2 exprs |
| mini (`data Tok` multi-ctor + 3 if) | ✅ 2 exprs |
| **`head -17`** | ✅ 3 exprs |
| **`head -17` + l.18** | 🔴 freeze |
| **`data Tok` + `lex_is_space`** | 🔴 freeze |
| **`data Toks` (récursif) + `lex_is_space`** | ✅ (head -17) |

**Conclusion** : le freeze est **state-dependent**, pas un pattern unique. Aucune isolation simple ne freeze. Le cumul déclenche un état qui boucle.

### Piste session 19 (1-2 sessions)
1. Instrumenter `parse_file_go2` : `debug.print` du nombre d'itérations + `ts.len` à chaque appel.
2. Si `ts.len` ne décroît pas → `rest` mal propagé sur un cas précis.
3. Si `ts.len` décroît mais `expr_count` grandit → boucle dans `parse_top`/`parse_one`.
4. Identifier la forme exacte qui ne progresse pas (probablement une interaction `def_body_if` + `parse_arglist`).
5. Fix probable : TCO `parse_arglist` ou `parse_one` (10-20 lignes).

### Acquis sessions 15-18
- `read_file` fixé (`perform "ReadFile"`, 6/6)
- `data` multi-ctor validé (3 tests)
- **TCO `parse_file`** (commit `e8dd778`) — `head -17` = 3 exprs
- `_existant.md` (~300 l.)
- Freeze isolé à "state-dependent" (pas un pattern unique)

### Session 19 — compteur parse_file_go : freeze plus bas
Compteur max `n > 5000` dans `parse_file_go`.
**Full-file : rc=137. Le compteur n'a JAMAIS été atteint.**
→ Récursion dans `parse_top` / `parse_arglist`, pas `parse_file_go`.

### Session 20
Compteur max 1000 dans `parse_one` puis `parse_arglist`. Premier qui
déclenche = TCO à ajouter. Fix probable : accumulateur réverseur pour `Toks`.

### Session 20 — parse_arglist TCO + parse_one_go
- `parse_arglist` en TCO (compteur 200, `es_rev`)
- `parse_one_go` wrapper (compteur 100, jamais déclenché)
- **`head -18` passe (4 exprs)** vs freeze avant
- `t2` et `t3` (4 ifs + appel) passent maintenant

**Freeze restant** : `head -19` (ligne `lex_is_symchar`, 4 ifs + appel `lex_is_space`).
Isolation : `t3` (4 ifs + appel `(g b)`) passe, `l19` (4 ifs + appel `(lex_is_space b)`) freeze.
Différence : `lex_is_space` **est défini** dans le fichier réel (l.15), pas dans `l19` seul.
Bug probable : interaction `parse_arglist` + contexte data multi-définitions.

**Session 21** : instrumentation `parse_head` (compteur 100), identifier la forme qui boucle.

### Session 21 — freeze isolé à 4 `(= b N)` imbriqués
- `ta` (2 defs simples) : ✅ 2 exprs
- `tb` (1 def, 3 ifs avec `(= b N)`) : ✅ 1 expr
- `tc` (1 def, **4 ifs** avec `(= b N)`) : 🔴 freeze
- `t2` (4 ifs, 1er `b` symbol) : ✅ (testé session 20)

**Seuil précis** : 4 conditions `(= b N)` dans une chaîne d'ifs.
**Cause probable** : chaque `(= b N)` = 1 `parse_arglist` imbriqué avec compteur local (n=0).
Aucun compteur global → la limite 200 par instance ne fire jamais sur 4 niveaux imbriqués.
**Session 22** : instrumenter avec un compteur global (threading) ou `PErr "iter N"`.

### Session 21 suite — limite 2000 débloque tc
- `parse_arglist_go` limite **200 → 2000**.
- `tc` (4 ifs) : ✅ passe (1 expr).
- **Full-file (209 lignes) : freeze encore** (rc=137).
- `head -30` : freeze aussi.

**Cause probable** : `lex_loop` (l.26, **8 ifs en queue**) dépasse la limite
2000 par instance. Chaque `lex_loop` itère sur ~2000 caractères, × 8 niveaux = 16000.

**Session 22** : limite 2000 → 50000 pour `parse_arglist`. Si OK full-file, self-parse complet.

### Session 22 — limite 50000 ne débloque pas (freeze plus profond)
- Limite arglist 2000 → 50000 → **head -19 freeze toujours**.
- Le freeze n'est PAS dans `parse_arglist` (limite ne fire pas).
- Hypothèse : chemin `parse_one` → `parse_head` → `parse_args` non-TCO sans limite,
  qui boucle ou recurse infiniment sur une forme précise de `lex_is_symchar`.

**Session 23 — approche différente** :
1. **Instrumentation Zig** : ajouter un compteur global dans `engine_expr.zig` (limite 10^6 calls → error) — protège TOUTES les récursions.
2. **Dump AST** : `head -19` avec limite basse (100) → voir l'AST partiel → identifier la forme qui boucle.
3. **Vérifier `build_apply`** (l.90) : a-t-il un base case `ENil` ? Sinon `parse_args2` reçoit `ENil` → boucle.
4. **Revoir `def_body_if`/`parse_if`** : `lex_is_symchar` avec appel en condition est le seul cas qui freeze.

**Le pansement 50000 est retiré** (2000 = limite significative).

### Session 23 — AST de head-19 : print freeze
- `parse_file (lex (read_file "h19"))` : ✅ réussit (`print "parse_ok"`)
- `expr_at ast 0-5` : ✅ (liste ≥ 6 éléments)
- **`print e0`** : 🔴 freeze → `toStringInfix` boucle sur `e0`
- `expr_count_big` : 🔴 freeze (liste parcourue infiniment)

**Conclusion** : l'AST de `head -19` est **structurellement bouclé** (liste cyclique
ou `EData` avec ctors cyclique), pas un problème de profondeur.

**Session 24 — investigation structure** :
1. `expr_at ast 50` / `500` : si passe → AST > 500 éléments pour 5 lignes (bug parser)
2. Instrumenter `es_rev` : vérifier que `[e4, e3, e2, e1, e0]` → `[e0, e1, e2, e3, e4]` sans cycle
3. Instrumenter `parse_arglist_go` : vérifier que `rest` progresse (ne pointe pas
   vers un ancêtre)
4. Candidat n°1 : `parse_one_go` sur `(lex_is_space b)` — l'appel de fonction
   dans la condition produit un `rest` qui inclut le `)` non consommé, puis boucle.

**Test discriminant** : `expr_at ast 500` → si freeze, cycle ; si passe, parser
produit trop d'exprs.

### Session 23 — print EBind OK, print e0 freeze
- `print (EBind "test" ...)` : ✅ affiche correctement
- `print e0` (où e0 = EData "Tok" [...] de l'AST head-19) : 🔴 freeze
- `expr_at 0-5`, `expr_at 500` : ✅
- Test EData isolé (vide, 1 ctor, 2 ctors) : [résultats selon sortie]

**Conclusion** : soit `toStringInfix` boucle sur `EData` (host), soit `e0` est
structurellement cyclique (parser `data_ctors`).

**Session 24** : selon résultat des 3 tests EData, fix `heaven_expr.zig` (host)
ou `heaven_parse.hvn` (data_ctors).

### Session 23 — EData isolé passe, e0 freeze
- `EData` vide/1 ctor/2 ctors : ✅ affichés
- `EBind/ELambda/ESym` : ✅ affichés
- `print e0` (vrai EData "Tok" de l'AST) : 🔴 freeze
- `EApply` isolé, `EData + EApply`, `EData 4 ctors mix` : [résultats selon sortie]

**Conclusion** : soit `toStringInfix` host bug sur `EApply`/`EData` complexe,
soit `e0` a un cycle interne (parser `data_ctors`).

**Session 24** :
1. Selon test : fix `toStringInfix` (host, `heaven_expr.zig`) ou `data_ctors` (parser).
2. Instrumenter `data_ctors` : `debug.print` du nom de chaque ctor construit.
3. Comparer avec `EData` isolé (qui marche) — différence = cycle.

**Acquis sessions 15-23** : read_file fixé, TCO parse_file + parse_arglist,
parse_one_go, 4 limites (100/200/2000/50000) testées, AST head-19 isolé au e0.

### Session 23 fin — e0.ctors : test discriminant
- `EData` isolé (vide, 1, 4 ctors mix avec EApply) : ✅ affichés
- `print e0` (vrai AST head-19) : 🔴 freeze
- `count_ctors e0` : [résultat selon sortie]

**Conclusion session 24** :
- Si `ctors` fini → `toStringInfix` host bug sur `e0` (heaven_expr.zig)
- Si `ctors` cyclique → `data_ctors` parser bug (heaven_parse.hvn:121)
- Si `ctors` > 500 → `data_ctors` accumule trop (même fix)

**Acquis sessions 15-23 (~12h)** :
- read_file fixé (`perform "ReadFile"`)
- TCO parse_file, TCO parse_arglist, parse_one_go
- data multi-ctor validé (3 tests)
- AST head-19 isolé : e0 freeze
- Limites 100/200/2000/50000 testées (pansement retiré)
- 4 faux diagnostics levés (QTT, curry, thunks, read_file)

### Session 23 fin — count_ctors e0 freeze
- EData isolé (vide, 1, 4 ctors mix EApply) : ✅ affichés
- print e0 : 🔴 freeze
- count_ctors e0 (expr_count_big sur ctors) : 🔴 freeze
- expr_at ast 500 : ✅ (donc ast ≥ 501 éléments)

**Conclusion** : ctors de e0 = cyclique OU ast entier = 500+ exprs (parser produit trop).

**Session 24 — instrumenter `data_ctors` (l.121)** :
`debug.print` du nom de chaque ctor construit. Si boucle, identifier la forme.
Candidat : `data_ctors2` sur ctor non-upper qui re-émet le token → boucle avec
le token déjà consommé. Vérifier `(TCons t rest)` (l.122) : `t` est-il le token
avant ou après `tok_tail` ?

### Session 24 — expr_at 500 == HORS_LIMITE ?
- `true` : ast < 500 éléments → `e0.ctors` cyclique → fix `data_ctors` (l.121)
- `false` : ast > 500 éléments pour 5 lignes → fix `parse_top` (consommation)

**Le fix est à 30 min dans les deux cas.** Session 24 teste puis patch.

### Session 23 cutoff — AST cyclique confirmé
- `expr_at 500` passe seul, mais `expr_eq` dessus freeze → AST cyclique
- `count_ctors e0` freeze → ctors cycliques
- `print e0` freeze
- `parse_file` réussit (parse_ok)
- `parse_top` isolé : [résultat selon sortie]

**Conclusion** : le parser produit un AST **structurellement cyclique**.
Candidat : `data_ctors` sur `Int`/`Str` (uppercase, traités comme ctor au lieu de type arg).
Test session 24 : `parse_top` isolé (si n > 1, data_scan bug).

**Acquis sessions 15-23 (~13h)** :
- read_file fixé (`perform "ReadFile"`)
- TCO parse_file, TCO parse_arglist, parse_one_go
- data multi-ctor validé (3 tests)
- AST cyclique isolé (pas profondeur, pas limite)
- 4 faux diagnostics levés (QTT, curry, thunks, read_file)

### Session 23 cutoff — paradoxe parse_file vs parse_top
parse_file (lex h19) : OK (print parse_ok). parse_top isolé : freeze.
Hypothèses session 24 : parse_file retourne prématurément, OU bug parse_file_go2,
OU expr_count_go bug (pourtant TCO). Test : expr_count_big ast.

### Session 24 — data_ctors pas coupable (rollback)
Réécriture `data_ctors` avec `skip_ctor_args` : head-19 freeze **toujours**. Rollback.
**Conclusion** : data multi-ctor OK (déjà 3/3), ce n'est pas le coupable.
**Vrai coupable** : `lex_is_symchar` (4 ifs + appel `lex_is_space` 3 ifs = 7 ifs).

### Session 25 — zone grise localisée
- expr_count_big OK jusqu'à 5000 (évaluateur sain)
- data multi-ctor OK (2 bugs cosmetiques : inversé, args comme ctors)
- 2 defs avec 2 ifs : InvalidSyntax (pas freeze)
- 2 defs avec 3-4 ifs : freeze
- parse_top isolé sur h19 : freeze

**Transition entre 2 ifs (syntax error) et 3-4 ifs (freeze).**
**Fix session 26 : TCO parse_if (15 lignes).**

### Session 25 — parse_if pas coupable pour (if c a b)
- parse_if traite uniquement if c then a else b (infixe)
- (if c a b) S-expr passe par parse_one → parse_head → parse_arglist
- TCO parse_if ne résoudra pas le freeze S-expr

**Conclusion selfhost (sessions 15-25, ~15h)** :
- read_file fixé (6/6)
- TCO parse_file, parse_arglist, parse_one_go
- head -18 passe, head -19 freeze (zone grise 2-4 ifs)
- AST h19 produit mais inutilisable (print freeze)

**Selfhost complet = 6-9 sessions supplémentaires** (architecture mutuellement
récursive du parser). PAS un fix chirurgical.

**Décision : cutoff selfhost. Bascule sur IO effects (vision async/distributed).**

### Session 30 — Channel a : data [a] non supporté
- `data Channel a = Channel Int Int [a]` : `channel_mk` = UnboundVariable
- Cause : type `[a]` (liste paramétrée) dans data paramétré non supporté
- Code conservé (`tests/io/channel.hvn.skip`), retiré des PATTERNS
- **Alternative session 31** : `Channel` via `Stream Int` (type fixe), ou acteurs mailbox

**Acquis sessions 26-29** : Result (4), io (7), Stream (6), stream_fns (10) = 27 tests CI.

## Modules std (sessions 26-32)

| Module | Contenu | Tests |
|---|---|---|
| `lib/std/result.hvn` | `Result a = Ok a \| Err Str` + is_ok, unwrap | 4 |
| `lib/std/io.hvn` | count_lines, first_line (via `perform "ReadFile"`) | 7 |
| `lib/std/stream.hvn` | `Stream a = SNil \| SCons a` + map/filter/take | 16 |
| `lib/std/channel.hvn` | `Channel = Channel Int Int L` (type L local) | 14 |

**Total : 41 tests CI-verrouillés.**

**Bugs documentés (sessions 30-32)** :
- `data C = C [Int]` : UnboundVariable (type liste littéral)
- `[1,2,3]` top-level : UnboundVariable (array literal)
- `(cons 1 ...)` top-level : UnboundVariable
- Contournement : type local `L = LNil | LCons Int L`
