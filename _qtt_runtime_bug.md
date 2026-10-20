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


## Mise a jour 2026-10-20 (apres tentative patch parser, rollback)

Tentative de patch `qtt_val` multi-token (`expr_parser.zig:677`) :
- Le patch build OK, mais **regression** : `let linear n = 16 in 42`
  (val simple, body constant) echoue alors qu'il devait passer.
- **Rollback** effectue. Le bug est **plus profond** que qtt_val.

## Cause racine revue (hypothese)

`linear` fausse le **bind lui-meme**, pas juste val. `let linear n = 16
in 42` echoue : le body `42` n'est pas retourne. Test `(f 0) == 42` KO.

Le bug est dans `bindSymWithBody` (expr.zig:1679) ou dans l'eval
`.bind` (engine_expr.zig:939). Le parse-time check (`expr_parser.zig:742`)
valide `uses == 1` mais ne produit pas le bon core node.

## Fix propose (session dediee, ~2-3 blocs)

1. Lire `bindSymWithBody` complet (expr.zig:1679).
2. Lire l'eval `.bind` complet (engine_expr.zig:939).
3. Instrumenter : `let linear n = 16 in 42` doit produire
   `bind(sym(n), lit(16), lit(42))` et evaluer `42`.
   Si le bind produit `bind(sym(linear), sym(n), ...)` ou autre chose,
   c'est la source.
4. Fix probable : `qtt_name` mal assigne a `linear` au lieu de `n`.

## Test de confirmation

  f _ = let linear n = 16 in 42   -- doit retourner 42
  f _ = let linear n = 16 in n    -- doit retourner 16 (1 usage OK)

Actuellement : les deux echouent (ArityMismatch ou != attendu).


## Mise a jour 2026-10-20 (session B, 3 blocs, cutoff)

### Faits mesures
- `c _ = let n = 16 in 42` -> OK (42)
- `d _ = let n = 16 in n` -> OK (16)
- `a _ = let linear n = 16 in 42` -> KO (pas 42)
- `b _ = let linear n = 16 in n` -> KO (pas 16)

=> le probleme est QTT-specifique, pas let-chain general.

### Parser : correct
`expr_parser.zig:677-694` : `qtt_name = tokens.items[2]` (= "n", pas
"linear"), `qtt_val = "16"`, `qtt_body` parsed. Le parser fait ce qu'il
doit.

### Eval : KO
`(print (let linear n = 16 in n))` -> `ArityMismatch`. Alors que sans
`linear`, meme structure passe. Le node `.bind` cree par
`bindSymWithBody` est identique dans les deux cas (meme fonction). Donc
c'est l'appel qui differe : le `if (kw) |k|` du parser ajoute quelque
chose (un wrapper ? un `.apply` supplementaire ?) qui n'est pas visible
dans la zone 677-694.

### Piste precise (prochaine session)
1. Voir `expr_parser.zig` zone 690-710 (juste apres la branche QTT) :
   y a-t-il un `addNode` supplementaire, un `.apply` wrap, un check
   `error.LinearViolation` qui retourne un node au lieu de propager ?
2. Instrumenter avec `std.debug.print` dans le `if (kw) |k|` : logger
   `val_id`, `name_sym`, `body_id`, et le node retourne.
3. Comparer les 2 graphes (avec/sans linear) via `@egraph_snapshot`.

### Effort
1 session .zig dediee. Pas faisable en fin de session longue.


## Mise a jour 2026-10-20 (session B, 5 blocs, cutoff definitif)

### Faits mesures (2e passe)
    let linear n = 16 in n     -- KO (!= 16)
    let erased n = 16 in 42    -- KO (!= 42)
    let many   n = 16 in n + n -- KO (!= 32)
    let n = 16 in n            -- OK (16)
    let n = 16 in 42           -- OK (42)

=> QTT est casse pour TOUS les cas LEGAUX. Ce n'est pas une
   violation attendue (comme je le pensais en B-1) - c'est un bug.

### Parser : correct (verifie 3 fois)
- expr_parser.zig:677-694 : qtt_name = "n", qtt_val = "16", qtt_body
  = parsed body.
- expr_parser.zig:740-759 : bind(name_sym, val_id, b) retourne.
- Identique au path sans QTT (expr_parser.zig:710-735).

### Eval : deux comportements DIFFERENTS selon invocation
- `heaven run` : error.ArityMismatch
- `--run-test` : `!= <valeur attendue>` (valeur reelle inconnue)

=> Deux chemins de code distincts. Hypothese : heaven_expr.zig:938
   (eval) a SA PROPRE branche QTT ou son propre parser qui re-wrap le
   node. Le parser expr_parser.zig est peut-etre court-circuite ou le
   node est double-wrap.

### Piste ULTRA precise pour session fraiche
1. `grep -n "linear\|erased\|many" src/core/heaven_expr.zig` :
   voir si heaven_expr.zig a une branche QTT parallele.
2. Comparer les 2 graphes :
   - `let n = 16 in n` (parse OK)
   - `let linear n = 16 in n` (KO)
   via `@egraph_snapshot` ou dump `store.nodes`.
3. Si 2 bind nodes presents (double bind), c'est le wrap.

### Effort
1 session .zig. PRIORITE HAUTE - c'est la vision "memoire en Heaven".
