# Audit syntaxe — S-expr vs infixe Heaven (2026-10-27)

## Règle cible (à valider)
- Infixe pour opérateurs : `a + b`, `a > b`, `if c then a else b`, `let x = e in body`
- Application parenthésée : `(f a b)`, `(@spawn thunk)`, `(cons x xs)`
- Interdit : `(+ a b)`, `(> a b)`, `(if c a b)`, `(let x e body)` en tête

## Forme lambda valide (unique)
`\x. body` — testé et validé.
- `lambda x : body`, `lambda x -> body`, `(fn x = x)` : **buggés** (parser)

## Bug parser identifié
`let x = e in body-op` : si `body-op` contient un opérateur SANS parenthèses
autour du corps, le scope fuit hors du `let`. Preuve :
- `(let y = ((\x. x) 5) in (y > 0)) == true` → **passe**
- `(let y = ((\x. x) 5) in y > 0)  == true` → **échoue**
Contournement actuel : `let many x = e in (body-op)` (forces + parens).

## Inventaire (S-expr dans .hvn)
- `core/io_stream.hvn` : 3
- `core/test_suite.hvn` : 49
- `core/stream.hvn` : 7
- `core/regression_pool_dangling.hvn` : 6
- `core/bigint.hvn` : 40
- `core/prelude.hvn` : 2
- `core/http.hvn` : 3
- `core/http_server.hvn` : 1
- `core/std/ord.hvn` : 5
- `core/std/array.hvn` : 10
- `core/std/quickcheck.hvn` : 4
- `core/std/base.hvn` : 1
- `core/std/hashmap.hvn` : 55
- `core/std/free.hvn` : 3
- `core/std/string.hvn` : 10
- `core/std/memory.hvn` : 6
- `core/std/list.hvn` : 4
- `lib/os/device.hvn` : 2
- `lib/os/vfs.hvn` : 1
- `lib/heaven_eval.hvn` : 8
- `lib/heaven_parse.hvn` : 34
- `stdlib/json/parse.hvn` : 30
- `stdlib/http_body.hvn` : 9
- `stdlib/mpst.hvn` : 2
- `stdlib/net/dns_parse.hvn` : 10
- `stdlib/net/http_client.hvn` : 14
- `stdlib/net/urlencode.hvn` : 7
- `stdlib/net/http.hvn` : 1
- `stdlib/string.hvn` : 11
- `stdlib/ontology.hvn` : 2
- `tests/test_eval.hvn` : 11
- `tests/test_hkt_v1b_step3.hvn` : 2
- `tests/test_quickcheck.hvn` : 4
- `tests/test_effects_rec.hvn` : 3
- `tests/scratch/test_ok.hvn` : 1
- `tests/scratch/test_1.hvn` : 1
- `tests/scratch/test_let_simple.hvn` : 1
- `tests/scratch/test_let_sans_paren.hvn` : 1
- `tests/test_free.hvn` : 1
- `tests/test_hashmap.hvn` : 6
- `tests/test_hkt_v1b_step2.hvn` : 2
- `tests/test_stream_lazy.hvn` : 3
- `tests/derive.hvn` : 4
- `tests/test_string.hvn` : 1
- `tests/test_pair.hvn` : 1
- `tests/features_smoke.hvn` : 14
- `tests/test_selfrecursion.hvn` : 9
- `tests/test_preemptive_coop.hvn` : 4
- `tests/test_scheduler.hvn` : 4
- `tests/test_heaven_eval_prims.hvn` : 4
- `tests/test_array.hvn` : 3
- `tests/verify_book.hvn` : 2
- `tests/experimental/comprehensions.hvn` : 2
- `tests/experimental/unlower_spec.hvn` : 2
- `tests/experimental/regression.hvn` : 2
- `tests/test_lens.hvn` : 1
- `tests/test_if_sexpr.hvn` : 6
- `tests/test_recursion.hvn` : 7
- `tests/test_data_eq.hvn` : 8
- `tests/test_abort_relaunch.hvn` : 8
- `tests/test_lexer.hvn` : 2
- `tests/verify_book2.hvn` : 1
- `tests/test_preemptive_split.hvn` : 5
- `tests/test_parser_literals.hvn` : 7
- `tests/test_effects.hvn` : 3
- `tests/test_io_stream.hvn` : 2
- `tests/test_option.hvn` : 1
- `tests/test_http.hvn` : 1
- `tests/test_prompt_depth.hvn` : 2
- `tests/test_list.hvn` : 2
- `tests/test_h1_qualified.hvn` : 4
- `tests/test_memory.hvn` : 1
- `tests/test_effects_rec_nested.hvn` : 6
- `tests/test_preemptive.hvn` : 7
- `tests/local/test_h1_import.hvn` : 2
- `tests/test_meta_if.hvn` : 6
- `tests/test_bigint.hvn` : 11
- `tests/test_base.hvn` : 1
- `tests/test_continuations.hvn` : 1

---

## Mise à jour 3.4b (2026-10-27 soir)

### Fix applique (commit 0471a6b)
`src/core/parse.zig:741` — corps de `let` route via `parseSExpr`
(avec fallback `parseLetExpr` pour `let` imbrique). Avant : seul
`parseLetExpr` ; tout corps non-`let` tombait dans `sym(body_str)`.

### Tests qui passent maintenant (4/8)
- `(let y = ((\x. x) 5) in (y > 0))`              == true  OK
- `(let a = 5 in let b = 6 in (a + b))`          == 11    OK
- `(let a = 5 in let b = 6 in a + b)`            == 11    OK
- `(let x = 5 in x > 0)`                         == true  OK

### Tests qui restent rouges (4/8) — causes DISTINCTES
1. `via_let_noparens` — `(let y = ((\x. x) 5) in y > 0)`
   Parse echoue a 0.13ms (pas d'eval). Corps non parenthese +
   RHS application : cas limite. Fix risque (distingue corps
   simple vs corps application). A traiter en 3.4b-ter.
2. `spawn_gt / spawn_eq_1 / spawn_task_runs` — corps `(tid > 0)`
   parenthese, parse OK, mais `let` bind `tid` comme thunk NON
   FORCE quand RHS = magic (@spawn). `via_let_parens` passe
   (RHS = application pure, evaluee eager). A traiter en 3.4b-bis.

### Decision d'ordre
3.4b-bis/ter reportes apres 3.4c. Raison : migration S-expr
mecanique, sans ambiguite, detectee par test_suite (98 tests).
Les fixes `let`+magic et corps non parenthese sont subtils
et risquent de faire boucler.

## Plan de migration S-expr -> infixe (3.4c)
Ordre de risque croissant (chacun test_suite en garde-fou) :
1. `core/std/array.hvn` (10 S-expr)
2. `core/std/memory.hvn` (6)
3. `core/std/free.hvn`, `core/std/string.hvn` (10)
4. `core/bigint.hvn` (40)
5. `lib/heaven_parse.hvn` (34)
6. `stdlib/json/parse.hvn` (30)
7. `core/test_suite.hvn` (49) — en DERNIER (c'est le garde-fou)

Regle : convertir UNIQUEMENT les operateurs purs (`(* a b)` ->
`a * b`, `(+ a b)` -> `a + b`). Les `if` S-expr restent tels
quels tant que le bug `if-multiligne-let-in` n'est pas fixe.
