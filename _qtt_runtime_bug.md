# QTT runtime bug + leak pre-existant (2026-10-20)

## Bug 1 : let linear fausse l'eval runtime

`let linear x = v in body` est accepte au parse (`expr_parser.zig:735-760`,
`countSymUses` + check `uses == 1`), mais fausse l'eval runtime.

Reproduce :
  f _ = let linear buf = (raw_alloc 16) in let _f = (raw_free buf 16) in 42
  -- (f 0) -> ArityMismatch (au lieu de 42)

Sans `linear`, la meme fonction retourne 42 correctement.

## Bug 2 : leak pre-existant import.zig:228

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
