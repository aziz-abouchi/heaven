# Prompt de continuité - Heaven (nouvelle conversation)

Copie-colle ce bloc au début de la nouvelle conversation.

---

## Contexte projet

Heaven - langage de programmation expérimental (preuves, selfhost, OTP, HKT, HoTT), en Zig + Heaven pur.
- Repo : https://github.com/aziz-abouchi/heaven
- Répertoire : ~/Desktop/Dev/langage/boot
- Binaire : ./zig-out/bin/heaven (jamais dans le PATH)
- Livre : docs/book/src/ - specs : docs/spec/

## État au 2026-11-03 (matin, dernier commit c32b67a)

| Métrique | Valeur |
|---|---|
| Commits du jour | 35 |
| Tags du jour | 6 (fix-clauses-32, g37-resolved, g38-resolved, g40-resolved, mir-stub-contract, propagator-v0) |
| Tests Heaven | 1412 |
| CI Zig (zig build test) | vert |
| check_all.sh | PROJET SAIN (13 OK, 0 FAIL, 3 WARN préexistants) |

## Ce qui a été livré le 2026-11-02

**Parser (5 pièges fermés)** : G.25, G.37, G.38, G.39, G.40 + [16]→[32] + contrat §6.

**Modules** :
- lib/heaven_propagator.hvn (V0, 14/14) : cell, cell_merge (max), propagate, cell_le
- lib/web/ontology.hvn : DI lookup_label_with http_fn
- tests/test_web_ontology_mocked.hvn (8/8), tests/test_web_ontology_offline.hvn (15/15)
- tests/test_kanren.hvn (18/18, cf. plus bas)

**Bigint** (7d8471b) : test_bigint_d20.hvn réactivé depuis _disabled/ - 2/2 (débloqué par rebuild + G.40).

**Kanren** (93bcfc0 + 5ec2e10 + e0465cf) : tests/test_kanren.hvn 6 → 18 tests (wildcards _ et N-args validés). Faux diagnostic #6 tombé : _ est un hole frais par arg (core/hole.zig:50, next_id += 1), pas un symbole partagé. kanrenQueryHeavenExpr (core/heaven_expr.zig:4488) ne fait aucun traitement spécial - inutile, unify(hole_frais, arg) réussit. features_smoke.hvn 44/44.

**Propagators V1.1** (bea2b3f) : `cell_merge_with` générique + semilattices `min_int` / `or_bool`. 7 tests ajoutés (`tests/test_propagator.hvn` 14 → 21). Reportés V1.2 : `union_list`, `watch` (nécessitent `lib/legacy/list.hvn` ou `core/std/list.hvn` — existent).

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

## Prochains chantiers (dans l'ordre)

1. **Propagators V1.2** (1 session) : `union_list` semilattice + `watch` (fold). Source : `lib/legacy/list.hvn` ou `core/std/list.hvn` (à importer). Voir _propagators.md.

2. **Formalisation C** (1-2 sessions) : `_core_typing.md` — règles de typage §1 (Pi, univers, quotients, Eq/refl).

3. **Prolog V2** (optionnel) : unification multi-args avec var Prolog explicite + facts multi-args.

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
- `heaven_parse.hvn` : `lex_loop` (10 if imbriqués) → parse cassé, 3 tests vides, eval import cassé.

**Règle** : **NE PAS** relancer `infix_migrate.py` sur ces 2 fichiers sans :
1. Diagnostiquer la cause précise sur un cas minimal (`lex "(== 1 1)"`).
2. Réécrire le script si le bug est dans le script.
3. `--run-test` sur le fichier ET tous les tests qui l'importent.

**Tests qui importent `heaven_eval.hvn`** (à lancer ensemble) :
`tests/test_diff_e.hvn`, `test_eval.hvn`, `test_heaven_eval_prims.hvn`, `test_meta_data.hvn`, `test_meta_if.hvn`, `test_parse_infix.hvn`.

**Bilan** : seule `lib/heaven_propagator.hvn` a été migrée avec succès (`5a2b81f`, 27/27 verts). Le script est utile mais doit être testé unitairement avant réutilisation.

## Pièges à retenir (annexe G)

- G.28 : f = ... top-level crée un thunk. Utiliser f _ = ... ou (f 0).
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

**Commencer par** : git status + git log --oneline -8 pour confirmer l'état, puis Propagators V1 (chantier #1).

---

Bonne continuation.
