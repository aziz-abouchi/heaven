# Prompt de continuité - Heaven (nouvelle conversation)

Copie-colle ce bloc au début de la nouvelle conversation.

---

## Contexte projet

Heaven - langage de programmation expérimental (preuves, selfhost, OTP, HKT, HoTT), en Zig + Heaven pur.
- Repo : https://github.com/aziz-abouchi/heaven
- Répertoire : ~/Desktop/Dev/langage/boot
- Binaire : ./zig-out/bin/heaven (jamais dans le PATH)
- Livre : docs/book/src/ - specs : docs/spec/

## État au 2026-11-02 (nuit, dernier commit e0465cf)

| Métrique | Valeur |
|---|---|
| Commits du jour | 29 |
| Tags du jour | 6 (fix-clauses-32, g37-resolved, g38-resolved, g40-resolved, mir-stub-contract, propagator-v0) |
| Tests Heaven | 1390 |
| CI Zig (zig build test) | vert |
| check_all.sh | PROJET SAIN (12 OK, 0 FAIL, 4 WARN préexistants) |

## Ce qui a été livré le 2026-11-02

**Parser (5 pièges fermés)** : G.25, G.37, G.38, G.39, G.40 + [16]→[32] + contrat §6.

**Modules** :
- lib/heaven_propagator.hvn (V0, 14/14) : cell, cell_merge (max), propagate, cell_le
- lib/web/ontology.hvn : DI lookup_label_with http_fn
- tests/test_web_ontology_mocked.hvn (8/8), tests/test_web_ontology_offline.hvn (15/15)
- tests/test_kanren.hvn (18/18, cf. plus bas)

**Bigint** (7d8471b) : test_bigint_d20.hvn réactivé depuis _disabled/ - 2/2 (débloqué par rebuild + G.40).

**Kanren** (93bcfc0 + 5ec2e10 + e0465cf) : tests/test_kanren.hvn 6 → 18 tests (wildcards _ et N-args validés). Faux diagnostic #6 tombé : _ est un hole frais par arg (core/hole.zig:50, next_id += 1), pas un symbole partagé. kanrenQueryHeavenExpr (core/heaven_expr.zig:4488) ne fait aucun traitement spécial - inutile, unify(hole_frais, arg) réussit. features_smoke.hvn 44/44.

**Docs** : _propagators.md, _inspirations.md, _logic.md (priorité Prolog magic + Propagators V1, kanren résolu), _syntax_gaps.md (kanren + features_parent résolus), _runtime_gaps.md, MIR_CONTRACT.md §6.

## Prochains chantiers (dans l'ordre)

1. **Prolog magic** (1 session) : exposer @prolog_fact / @prolog_query dans engine_expr.zig:1859 (même bloc que query, patron kanrenQueryHeavenExpr heaven_expr.zig:4488). src/runtime/prolog.zig a déjà solve, addFact, parseRule. Vtable à ajouter sur Engine.vtable (à côté de kanren_query, ligne 178).

2. **Propagators V1** (2-3 sessions) : unifier egraph + kanren + ontologies sous lib/heaven_propagator.hvn. Voir _propagators.md.

## Pièges à retenir (annexe G)

- G.28 : f = ... top-level crée un thunk. Utiliser f _ = ... ou (f 0).
- G.37 : parse_top sur token unique. Contourné.
- G.38 : let dans string intercepté. Contourné par containsKeywordAtRoot.
- G.40 : antislash-quote n'est pas un escape - utiliser @char_string 34.
- pair est paresseux : forcer avec (fst (force ...)) ou lambda.
- (= X Y) préfixe marche, mais X == Y infixe est plus sûr dans les cascades if.
- _ top-level = hole frais par arg (pas de wildcard dans unify, pas besoin).

## Méthode (discipline tenue le 2026-11-02)

**Reproduire avant de patcher.** Chaque fix confirmé par trace (debug.print + HEAVEN_TRACE=1) ou probe minimal. **6 faux diagnostics corrigés** :
- [32] (plafond clauses) pas le parser
- docgen.py (somme des Total:) pas les tests
- label_arr_pat correct, pas extract_first_label
- G.39 = [16], pas le host parser
- bdiv 1000 = bug bdivmod_step (pas fuel), puis fixé par rebuild
- kanren wildcard = jamais reproduit (query test_mortel _ _ → 2 solutions, features_smoke.hvn 44/44). Le diagnostic « 0 solution » était une prédiction non testée, pas une observation.

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

**Commencer par** : git status + git log --oneline -8 pour confirmer l'état, puis Prolog magic (chantier #1).

---

Bonne continuation.
