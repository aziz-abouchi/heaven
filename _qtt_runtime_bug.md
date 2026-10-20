# QTT runtime bug + leak pre-existant (2026-10-20)

## Bug 1 : let linear fausse l'eval runtime

`let linear x = v in body` est accepte au parse (`expr_parser.zig:735-760`,
`countSymUses` + check `uses == 1`), mais fausse l'eval runtime.

Reproduce :
  f _ = let linear buf = (raw_alloc 16) in let _f = (raw_free buf 16) in 42
  -- (f 0) -> ArityMismatch (au lieu de 42)

Sans `linear`, la meme fonction retourne 42 correctement.

## Bug 2 : leak import (NON localise, investigation >4 blocs)



`--run-test` sur tout fichier avec `import` leve `MEMORY LEAK` depuis
`import.zig:228` (`allocator.dupe` du source jamais free). Independant
de l'exemple memoire : `test_ontology.hvn` et `test_ontology_derivation.hvn`
montrent le meme leak.

Workaround : `HEAVEN_NO_LEAK_CHECK=1` (cf. `_session_continuity.md`).
Fix : 1 bloc (ajouter `defer free`), session dediee.

## Effort Phase 2 QTT

- Verifier que `linear`/`erased`/`many` sont des modificateurs du binding.
- Brancher check runtime sur `heaven run`.
- Tests end-to-end `.hvn` : `linear ok/ko`, `erased ok/ko`, `many ok`.
- 1 session.

## Workaround

Pas de `linear` dans les exemples tant que Phase 2 n'est pas faite.
`examples/memory/alloc_demo.hvn` documente le pattern sans `linear`.


### Investigation (4 blocs, non conclusive)

- `Heaven.deinit` (heaven_expr.zig:450-560) est **complet** : il free
  `imported_files` (clés+valeurs), `loading_modules`, `type_aliases`,
  `hidden_names`, `ctor_arities`, `fn_arities`, `ctor_parents`,
  `fn_domains*`, `ctor_results`, `user_redefined_names`, `current_module`,
  `last_eq_lhs`. Rien d'évident.
- Les 5 leaks de 32 bytes espacés suggerent une ArrayList ou un HashMap
  dans `engine` (probablement `engine.fns` : chaque import ajoute des
  clauses via `getOrPut` avec `dupe(owned)` à import.zig:210).
- `engine.deinit` non inspecté — prochain chantier si on veut le finir.
- **Impact** : non bloquant, tests passent, `HEAVEN_NO_LEAK_CHECK=1` est
  déjà la norme (cf. `_session_continuity.md` règle 5).
- **Decision** : documenter, passer à TLS/QTT, revenir si nécéssaire.


## Cause identifiee (2026-10-20, 5 blocs de diagnostic)

`expr_parser.zig:677` : `qtt_val = tokens.items[4]` -- **un seul
token**. Si l'expression val est multi-token (`(raw_alloc 16)` ->
`(`, `raw_alloc`, `16`, `)`), `qtt_val = "("`. `parseExpression("(")`
retourne un Id invalide, `buf` n'est pas lie a `raw_alloc 16`, puis
`(raw_free buf 16)` declenche `ArityMismatch`.

Asymetrie confirmee : `body_buf` accumule tokens[6..] correctement,
mais `qtt_val` prend un seul token.

## Fix precis

Mirror du `body_buf` logic sur `qtt_val` (accumuler entre `=` et `in`).
~10 lignes dans `expr_parser.zig:677-695`. Session dediee (parser
sensible, baseline complete requise).

## Test de confirmation (si reprend en session dediee)

  f _ = let linear buf = 16 in buf        -- doit marcher (val 1 token)
  f _ = let linear buf = (raw_alloc 16) in buf  -- doit marcher apres fix

Actuellement : 1er OK, 2e ArityMismatch.
