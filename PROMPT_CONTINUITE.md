# Prompt de continuité - Heaven (nouvelle conversation)

Copie-colle ce bloc au début de la nouvelle conversation.

---

## Contexte projet

Heaven - langage de programmation expérimental (preuves, selfhost, OTP, HKT, HoTT), en Zig + Heaven pur.
- Repo : https://github.com/aziz-abouchi/heaven
- Répertoire : ~/Desktop/Dev/langage/boot
- Binaire : ./zig-out/bin/heaven (jamais dans le PATH)
- Livre : docs/book/src/ - specs : docs/spec/

## État au 2026-11-04 (19h30, dernier commit 90d58dd)

| Métrique | Valeur |
|---|---|
| Commits du jour | 62 (04/11) |
| Tags du jour | 6 (fix-clauses-32, g37-resolved, g38-resolved, g40-resolved, mir-stub-contract, propagator-v0) |
| Tests Heaven | 1446 |
| CI Zig (zig build test) | vert |
| check_all.sh | PROJET SAIN (14 OK, 0 FAIL, 3 WARN, ~1m30) |

## Ce qui a été livré le 2026-11-02

**Parser (5 pièges fermés)** : G.25, G.37, G.38, G.39, G.40 + [16]→[32] + contrat §6.

**Modules** :
- lib/heaven_propagator.hvn (V0, 14/14) : cell, cell_merge (max), propagate, cell_le
- lib/web/ontology.hvn : DI lookup_label_with http_fn
- tests/test_web_ontology_mocked.hvn (8/8), tests/test_web_ontology_offline.hvn (15/15)
- tests/test_kanren.hvn (18/18, cf. plus bas)

**Bigint** (7d8471b) : test_bigint_d20.hvn réactivé depuis _disabled/ - 2/2 (débloqué par rebuild + G.40).

**Kanren** (93bcfc0 + 5ec2e10 + e0465cf) : tests/test_kanren.hvn 6 → 18 tests (wildcards _ et N-args validés). Faux diagnostic #6 tombé : _ est un hole frais par arg (core/hole.zig:50, next_id += 1), pas un symbole partagé. kanrenQueryHeavenExpr (core/heaven_expr.zig:4488) ne fait aucun traitement spécial - inutile, unify(hole_frais, arg) réussit. features_smoke.hvn 44/44.

**Propagators V1.1 + V1.2** (bea2b3f + e71851b) : `cell_merge_with` générique + semilattices `min_int`/`or_bool` (V1.1, 21/21) + `union_list` (`nub (append a b)`) + `watch` (fold via `foldl`) (V1.2, 27/27). Import implicite `core/std/list.hvn`.

**Formalisation** (f3d837b + 747d4f3) : ch. 41 squelette (`docs/book/src/41-semantique-formelle.md`, 8 sections, style Pony/CompCert) + `_core_syntax.md` v0.1 — 3 couches (kernel CIC réel / runtime / HoTT cible), `[À VÉRIFIER]` : Σ, J, Prop imprédicatif.

**Prolog V1** (77da824) : wildcard `_` en query. `_` = hole frais -> variable Prolog `Q0`, `Q1`, ... via `hole_counter` local dans `prologQueryHeavenExpr` (car `rename_counter` est reset par `solve()`). 7 tests wildcard ajoutés (`tests/test_prolog.hvn` 8 -> 15).

**Prolog magic** (8ea2f05) : @prolog_fact / @prolog_query, MVP strict, 8/8 (tests/test_prolog.hvn).
- Vtable prolog_fact/prolog_query + dispatch engine_expr.zig (post-query).
- prologFactHeavenExpr / prologQueryHeavenExpr (heaven_expr.zig, patron kanrenQueryHeavenExpr).
- Args : .sym -> string, .lit (et .int) -> store.lits.items[aux].int via bufPrint. .hole rejete (InvalidInput).
- Module prolog dans build.zig (createModule + addImport differe matrix_lib) ; imports cross-module reconcilies (scut/network.zig, shell/init.zig).
- Piege cle : int args tagges .lit (payload=0, valeur dans store.lits.items[aux].int). Voir annexe G.

**Docs post-livraison** (869db1f + f11f22e) : _logic.md (kanren + prolog resolus), heaven.md §9 (Prolog magic), G-pieges.md G.41 (piege .lit), README/STATUS regen.

**Docs** : _propagators.md, _inspirations.md, _logic.md (priorite Propagators V1, kanren + prolog resolus), _syntax_gaps.md (kanren + features_parent résolus), _runtime_gaps.md, MIR_CONTRACT.md §6.

## P0/P0.5 — FAIT 2026-11-04 (check_all couvre 170 tests .hvn)

**Livré** (session 2026-11-04, 8 commits) :
- `scripts/test_all_hvn.py` (parallèle, NPROC=4 + retry) : **166 tests .hvn, 28-50s** (vs 2m18 seq).
- `check_all.sh` intègre `test_all_hvn` — **couvre 166 tests .hvn** (vs 3 avant).
- **Perf check_all** : 5m42 → **1m25** (×4) — skip `zig build test` si `.zig` inchangé, retire section 6 redondante.
- D20 whitelisté (bug contextuel documenté). Fixtures `imports/` whitelistés (Zig fixtures).

**Whitelist actuelle** :
- `tests/test_bigint_d20.hvn` — D20 stack + ExecutionFailed silent (`_bigint_d20_stack.md`).
- `tests/imports/cyc_a.hvn`, `cyc_b.hvn` — cycle d'import (✗ attendu, test négatif).
- `tests/imports/exp_util.hvn` — export hors import = no-op (✗ attendu), **référencé par `heaven_expr.zig:5815`**.

**P0.5 — Chantiers avant intégration `check_all`** :
1. **Bigint D20** : fix `bdiv` itératif (`_bigint_d20_stack.md` choix B) ou whitelist permanente.
2. **Reclassement négatif propre** : bouger `cyc_a/b` + `exp_util` vers `tests/negative/imports/` ET adapter les tests Zig (`heaven_expr.zig:5316, :5815`) qui référencent ces chemins en dur. 1 session.
3. **Intégration `test_all_hvn.sh` dans `check_all.sh`** une fois 1+2 verts.

**Ne PAS** relancer `scripts/infix_migrate.py` sur `lib/heaven_eval.hvn` ou `lib/heaven_parse.hvn` sans réparer `needs_parens` (cf. leçon midi).

**Bug documenté non-fixé** : `+` sur bigint n'est pas supporté (`(to_int (+ (from_int 3) (from_int 4)))` ≠ 7). À vérifier : primitives bigint exposées (`badd`? ou rien?). Non-bloquant.

## État au 2026-11-05 (session nuit, dernier commit `dead111`)

| Métrique | Valeur |
|---|---|
| Commits de la session | 3 (`17-handlers`, `23-reseau`, `24-hab`) |
| Livre v2 | **28 chapitres, ~10 137 l.** |
| Partie I | 7/7 ✅ |
| Partie II | 9/9 ✅ |
| **Partie III** | **12/12 ✅** (17-handlers → 24-hab) |
| Commits non pushés | `dead111`, `188c678`, `4535611` |
| `build.sh` | WIP local (ajout `site/repl/heaven.wasm`), à ne pas committer avec du doc |

## Ce qui a été ajouté cette session (Partie III bouclée)

- `17-handlers.md` (234 l.) — `handle_rec`, `k` comme continuation, imbrication par pile `prompts`, abandon de `k` = `throw`
- `23-reseau.md` (328 l.) — trois couches HTTP (parser pur testé, servir natif `--http-serve`, cible honnête : DNS, HTTPS, WebSocket non prêts)
- `24-hab.md` (275 l.) — MVU + optiques + catamorphisme, 9 tests `tests/hab/`, distinction « logique testée » vs « pont JS non testé »

## Prochains chantiers (par ordre de priorité)

1. **P1c runtime** — **priorité #1**, non traité cette session :
   - `heaven check` est un **stub** (aucune vérif arité/scope/type)
   - **Curryfication** `(f a b)` manquante (retourne lambda partielle, pas le résultat)
   - **Thunks top-level** non déballables (`counter_comp = (H.mk_component ...)` échoue silencieusement)
   - Ces trois points sont documentés dans `docs/spec/_runtime_gaps.md` mais **pas listés dans les « prochains chantiers »** avant ce resync.

2. **Partie IV du livre** — ouverte mais **pas commencée**. Cibles suggérées :
   - `25-outils` ou `25-ecosysteme` (LSP, MCP, linter, formatter)
   - `26-selfhost` (miroir de `25-stdlib-net-http.md` v1)
   - `41-semantique-formelle` (squelette existant, 8 sections)
   - **Cadence : 1 ch./session**, pas 25. Le marathon du 4 nov ne doit pas se reproduire.

3. **MPST V2c** (1 session) — récursion `μX. … X`. V2b bloqué par `_concurrency.md` C1-C5.

4. **Formalisation C** (1-2 sessions) — `_core_typing.md` §1. Voir `_core_syntax.md` `[À VÉRIFIER]`.

## Décision recommandée

**P1c runtime avant Partie IV.** Raison : 28 chapitres décrivent maintenant un langage plus stable que le binaire. Si on ouvre Partie IV sans traiter P1c, l'écart augmente. Une session P1c (un des 3 chantiers), puis reprise du livre à 1 ch./session.

**Sous-décision à prendre en début de prochaine session** : lequel des trois chantiers P1c attaquer en premier ?
- **`heaven check`** : impact utilisateur le plus direct, effort moyen
- **Curryfication** : bug silencieux, effort faible mais risque de régression
- **Thunks top-level** : piège connu, workaround existe déjà

Recommandation : **`heaven check`** en premier — c'est celui qui débloque le plus d'expérience utilisateur pour le moins de risque de régression.

## Ne PAS (rappels)

- Ne pas enchaîner MPST V2b par inertie (V2a livré, V2b bloqué spec).
- Ne pas relancer `infix_migrate.py` sur `heaven_eval.hvn` / `heaven_parse.hvn` sans réparer `needs_parens` (leçon du 3 nov midi).
- Ne pas committer `build.sh` avec du doc (WIP séparé).
- Ne pas ouvrir 10 chapitres d'un coup — 1 ch./session maximum jusqu'à ce que P1c soit traité.


## P1c-sessions 1-3 (2026-11-05, 12h51–14h35) — `heaven check` opérationnel

### Fait (9 commits pushés, `7addadd` → `0a777d1`)
- `heaven check` : **syntax check fiable** (exit 1 sur diag, ERROR tree-sitter via `is_error` strict)
- `heaven check` : **arity check fonctionnel** (`add 1` détecté, message + exit 1)
- `buildEqDecl` : construit lambda+bind (avant : stub jetait la fonction)
- `typer.infer` : tolère tous les tags créés par le Bridge
- `msg_pool` dans Typer : plus de leak `allocPrint`
- Doc `_runtime_gaps.md` §check + §arity (marqué RÉSOLU)

### 4 causes racines successives identifiées et fixées
1. `bind` stocke val dans `span_a[0]`, pas `aux`
2. `interner.intern("x") == 0` (critère `payload==0` trop strict)
3. `add 1` sans parens n'est **pas** un `call` tree-sitter, c'est `app_expr`
4. `simple_expr` enveloppe l'identifiant — `buildCall` prenait le wrapper

### Découverte critique à propager
- `fn f(x, y) = ...` **n'est pas Heaven** : grammar refuse `fn`. Vraie syntaxe : `add x y = x + y`.
- **tree-sitter ≠ syntaxe Heaven** sur 3 points : `app_expr` (= call applicatif), `simple_expr` (wrapper), MISSING `;` cosmétiques. Toute nouvelle règle de grammar doit être testée sur un `.hvn` réel.
- `ast_bridge.zig` est un **chemin parallèle** à `engine_expr` — `heaven run` ne l'utilise pas. `heaven check` est le seul consommateur du Typer. Patcher le Typer **ne peut pas** régresser `run`.

### Reste (P1c incomplet)
- **Curryfication** : **FONCTIONNE** pour tous les cas réels (5/6).
  Edge case `(((f a) b) c)` échoue — voir `_runtime_gaps.md` §curry.
  Pas prioritaire (rare, workaround `(f a b c)` direct).
- **Thunks top-level** : workaround existe (`f _ = ...`), moins urgent
- **Test de non-régression `check`** : `tests/hvn-check/{clean,arity,syntax-error}.hvn` + intégration `check_all.sh` (30 min)
- **Tests `check` dans CI** : non fait

## Docs / book — 3 patches en attente (2026-11-05)

### 1. `book.toml` v2 + `mdbook build`
- `docs/book/src-v2/SUMMARY.md` existe, `G-pieges.md` copié, 49 SVG présents.
- **Manque** : `docs/book-v2/book.toml` (ou `docs/book/book.toml` élargi) pour que `mdbook build` trouve `src-v2/`.
- Effort : 10 min. Priorité : 🟡 (index navigable sur GitHub, build à ajouter).

### 2. Renommage `16-effects` → `17-effects` + cascade
- Conflit : `16-effects.md` et `16-optiques.md` portent tous deux « Chapitre 16 ».
- Fix : `git mv 16-effects.md 17-effects.md` puis +1 sur tous les suivants (`17-handlers` → `18-handlers`, etc.). Impact : 12 fichiers à renommer, SUMMARY + liens internes à ajuster.
- Effort : 15 min. Priorité : 🟠 (cosmétique mais visible).

### 3. `heaven check` dans la spec
- `heaven.md` est la spec **du langage** (lexique, types, patterns) — pas de section CLI.
- Option A : ajouter `## 3.x CLI` dans `heaven.md`.
- Option B : créer `docs/spec/_cli.md` dédié (`heaven run`, `heaven check`, `heaven parse`, `heaven build`, etc.).
- Recommandation : **Option B** (CLI ≠ langage).
- Effort : 5 min. Priorité : 🟡.

## Style `.hvn` et livre (politique 2026-11-03)

**Code `.hvn`** : infixe par défaut. Politique existante : `docs/spec/_style_infix.md`.
- `if c then a else b` (pas `(if c a b)`) ; chaînage `else if` OK.
- `a + b`, `a < b`, `a == b` (pas `(+ a b)`, `(< a b)`, `(= a b)`).
- Appels de fonction : `f x y` ou `(f x y)` — les deux conformes.
- **Règle boy-scout** : fichier touché dans une session → migré dans le même commit.
- **16 fichiers** encore en S-expr (sur 152) — migration progressive, 3-4 par session.
  Liste : `grep -lE '^\s*\([a-z_]+ \(' tests/*.hvn lib/*.hvn core/std/*.hvn 2>/dev/null`

**Livre** — deux registres distincts :
- Ch. 0–40 : style **LYSE/LYAH** (conversationnel, exemples progressifs, anecdotes, figures). Public prioritaire : littéraires, philosophes, curieux.
- Ch. 41 (sémantique formelle) : **formel d'abord** (Pony/CompCert), narratif en encadré. Public prioritaire : mathématiciens.
- Ne pas mélanger les registres : si on écrit du formel, c'est ch. 41 ; si on raconte, c'est 0–40.


## Leçon 2026-11-03 (midi) — migration infixe trop risquée

**Statut** : `scripts/infix_migrate.py` est **conservé** mais la migration
de `lib/heaven_eval.hvn` et `lib/heaven_parse.hvn` a été **rollbackée**
(commits `541044f` et à venir). Les deux fichiers sont en S-expr d'origine.

**Ce qui casse** :
- `heaven_eval.hvn` : `prim_ops _ = (cons "+" ...)` → version infixe perd `"+"` de la liste.
- `heaven_parse.hvn` : `lex_loop` (10 if imbriqués) → migration casse `lex_loop` (10 if imbriqués en chaîne), 3 tests vides, eval import cassé.

**Règle** : **NE PAS** relancer `infix_migrate.py` sur ces 2 fichiers sans :
1. Diagnostiquer la cause précise sur un cas minimal (`lex "(== 1 1)"`).
2. Réécrire le script si le bug est dans le script.
3. `--run-test` sur le fichier ET tous les tests qui l'importent.

**Tests qui importent `heaven_eval.hvn`** (à lancer ensemble) :
`tests/test_diff_e.hvn`, `test_eval.hvn`, `test_heaven_eval_prims.hvn`, `test_meta_data.hvn`, `test_meta_if.hvn`, `test_parse_infix.hvn`.

**Bilan** : seule `lib/heaven_propagator.hvn` a été migrée avec succès (`5a2b81f`, 27/27 verts). Le script est utile mais doit être testé unitairement avant réutilisation.

## Résolutions récentes 2026-11-04 (18h30)

- **Gap #2 stale** (`04de61c`) : `run` draine **toute** la mailbox (`while (true)`). Vérifié 5 msgs = 15. 4 tests régression (`tests/test_actor_multi_msg.hvn`).
- **wasmtime cassé** (`df8cc9f`) : `ld-linux` GC'd par Guix. **5 FAIL WASM = environnemental, pas Heaven**. `.wasm` se produit en manuel. Doc `_ci_checklist.md`.
- **`__pycache__`** ignoré (`.gitignore`, `0a17c59`).
- **P1b `core/std/*`** (`11c4cce`, `116e3f9`) : 7 fichiers migrés (list, base, eq, ord, option, pair, quickcheck). `array`/`string` rollback (G.43, `if` multi-lignes).
- **Livre v2 — 5 pilotes** (`41201e6`, `afa4f63`, `1dc0117`, + `4d8b9a5`, `e0950b8` du 04/11 matin) : pattern LYAH validé (piège + capot + 4 exercices) sur philosophie, types, syntaxe, récursion, HOF.
- **OUTLINE cohérent** (`b184228`) : `00c-apps` = annexe F (showcase), ch2 from-scratch (pas de redondance REPL).
- **Livre v2 — 25 chapitres, ~9300 l.** : Partie I (7/7), Partie II (9/9), Partie III (9/12). Mappings corrigés : `19-algebres`→ch9, `14-recursion-schemes`→ch14, `17-categories`→ch15, `15-optiques`→ch16, ch10 from-scratch, `23-validation`→split ch18/18b. Pattern validé 25×.

## Pièges à retenir (annexe G)

- G.28 (FAUX, corrige 2026-11-05) : `f = expr; f == 3` echoue. Les workarounds `f _ = ...` et `(f 0)` **NE MARCHENT PAS** non plus. Bug de lookup top-level pre-existant, latent (167 tests evitent le cas). Cf. `_runtime_gaps.md` §3. Ce qui marche : `(add 1 2)` direct, sans binding. A fixer session 5 (~2h).
- G.37 : parse_top sur token unique. Contourné.
- G.38 : let dans string intercepté. Contourné par containsKeywordAtRoot.
- G.40 : antislash-quote n'est pas un escape - utiliser @char_string 34.
- pair est paresseux : forcer avec (fst (force ...)) ou lambda.
- (= X Y) préfixe marche, mais X == Y infixe est plus sûr dans les cascades if.
- _ top-level = hole frais par arg (pas de wildcard dans unify, pas besoin).
- Int arg = .lit, pas .int - payload=0, valeur dans store.lits.items[aux].int. Vaut pour Prolog magic (et probablement ailleurs).

## Méthode (discipline tenue le 2026-11-02)

**Reproduire avant de patcher.** Chaque fix confirmé par trace (debug.print + HEAVEN_TRACE=1) ou probe minimal. **7 faux diagnostics corrigés** :
- [32] (plafond clauses) pas le parser
- docgen.py (somme des Total:) pas les tests
- label_arr_pat correct, pas extract_first_label
- G.39 = [16], pas le host parser
- bdiv 1000 = bug bdivmod_step (pas fuel), puis fixé par rebuild
- kanren wildcard = jamais reproduit (query test_mortel _ _ → 2 solutions, features_smoke.hvn 44/44). Le diagnostic « 0 solution » était une prédiction non testée, pas une observation.
- prolog int-query = 3 fausses pistes (payload, node.int, mauvais chemin lits[aux].int) avant que platform.debug.print ne donne tag=lit payload=0 aux=409.

**Committer par petits blocs verts**, avec tests, doc honnête (_runtime_gaps.md, _claims_vs_reality.md). Ne pas précipiter les features dans un contexte saturé.

## Commandes utiles

  cd ~/Desktop/Dev/langage/boot
  ./zig-out/bin/heaven --run-test tests/FILE.hvn
  ./zig-out/bin/heaven run FILE.hvn
  zig build test
  bash check_all.sh
  bash build.sh
  python3 scripts/docgen.py
  python3 scripts/status_gen.py

**Commencer par** : git status + git log --oneline -8, puis **Partie III reste** : `17-handlers` from scratch (45 min), `23-réseau` fusion (30 min), `24-hab` fusion (30 min) → Partie III bouclée (12/12).

---

Bonne continuation.
