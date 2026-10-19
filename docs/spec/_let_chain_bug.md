# Bug : `let` chain et `let` en argument (2026-10-19)

## Symptome

`convertLetIn` (`heaven_expr.zig:1988`) ne gere que le `let`
**top-level** d'un corps de fonction. Tout `let` imbrique ou
chaîne est ignore, l'AST n'est pas evalue.

## Reproducteurs

| Code | Resultat |
|---|---|
| `let a = 1 in (print (int_to_string a))` | `"1"` ✅ |
| `let a = 1 in let b = 2 in body` | AST non-evalue ❌ |
| `(+ (let a = 1 in a) (let b = 2 in b))` | AST non-evalue ❌ |
| `fn f _ = (seq (print "A") (seq (let x = (print "B")) (print "C")))` | `UnboundVariable` ❌ |

## Ce qui marche (prouve)

- `fn f _ = (let x = v in body)` : un seul `let`, top-level
- `fn f _ = (seq e1 (seq e2 e3))` : `seq` chain
- `f arg1 arg2` : application simple, args sans `let`
- `(@net_listen (cap_acquire "net:N") N)` : magic one-liner

## Workaround : `fn` + `seq`, pas de let-chain

Chaque fonction fait une chose, les valeurs passent en parametres :

    fn respond cap cl _ = (seq (@net_write cap cl "HTTP/1.1 200 OK") (@net_close cap cl))
    fn accept cap sock _ = (respond cap (@net_accept cap sock) 0)
    fn setup _ = (seq (print "start") (accept (cap_acquire "net:N") (@net_listen ... N) 0))

Imbrication : `(seq (let x = v in x) (seq ...))` — attention,
`let` dans un arg de `seq` echoue (`UnboundVariable`). Extraire
en fonction separee.

## Pourquoi ça bloque E4b

`http_server.hvn` (root, non-tracke) et `core/http_server.hvn`
utilisent tous les deux des let-chains. Ils ne peuvent pas
marcher. Un serveur fonctionnel doit etre ecrit en `fn`/`seq`.

## Correctif (session dediee)

`convertLetIn` doit :
1. Rendre `let ... in` comme **expression d'un S-expr**
   (actuellement : seulement top-level).
2. Detecter et normaliser `let x = v in body` en
   `(let x v body)` **a l'interieur** d'un S-expr.

Probablement 2-3h + tests unitaires (`test_let_chain.hvn`).
Ne pas bricoler a chaud.

## Impact estimate

- Tout programme imperatif > 1 ligne (serveur, HTTP, etc.)
- Mais : les tests unitaires `.hvn` ne l'utilisent pas
  (`test "n": (helper 0) == val` — pas de chain)
- `lib/heaven_eval.hvn` (metacircularite) : a verifier

## Reference

- `src/core/heaven_expr.zig:1988` (`convertLetIn`),
  `:2082` (`parseBodySmart`, top-level seulement)
- `_let_wildcard_bug.md` (historique, refute : `let _` marche)

## AMENDEMENT 2026-10-19 (fix partiel)

**Fix committe** : `normalizeLetChain` (`heaven_expr.zig:763`),
appele dans la branche top-level de `heaven.eval`.

**Debloque** : `heaven run script.hvn` avec let-chain
(`"3"` sur chain 2, `"6"` sur chain 3).

**Ne debloque PAS** :
- `.hvn` helper `f _ = (let ... in let ... in body)` — passe par
  `parseBodySmart` -> `convertLetIn` (chemin distinct). Test
  `tests/test_let_chain.hvn` 0/4 -> non commite.
- `let` en argument de S-expr.

**Prochain pas** : couvrir `convertLetIn` (meme bug de reassemblage
sans recursion). Probablement 5-10 lignes dans
`heaven_expr.zig:2045-2065` (rest_conv deja recursif, mais
`body_norm` pas applique sur la valeur en cas de chain imbrique
dans la valeur). A diagnostiquer en session fraiche.

## DECOUVERTE 2026-10-19 (cutoff, 3e bug)

Deux fixes tentes pour let-chain helper, tous deux **sans effet** :
1. `normalizeLetChain` dans `heaven.eval` top-level -> marche
   pour `heaven run script.hvn`, pas pour `helper _ = (...)`.
2. `normalizeLetChain` dans `parseBodySmart` (branche `(`) ->
   rollback, `tests/test_let_chain.hvn` reste 0/4.

**Vrai blocage (discriminant)** :

    printf 'helper _ = 42\n(helper 0)\n' > /tmp/iso2.hvn
    heaven run /tmp/iso2.hvn   -- -> [eval error] error.ArityMismatch

`helper _ = 42` + `(helper 0)` echoue en `heaven run`. **Pas de let
implique.** Alors que `mk_obj _ = ...` + `(mk_obj 0)` marche en
`--run-test` (test_json_v1 12/12). Difference : `runEvalFile` +
`splitStatements` (`test_runner.zig:36,260`) vs `runTestFile`.

**Hypothese** : `splitStatements` ou l'eval statement-par-statement
perd le lien `def -> sym_arity`. Soit la definition est enregistree
avec arity 0 (car `_` skippe), soit `heaven.eval` ne persiste pas
`fn_arities` entre appels.

**Pas de fix ce soir** : 2 tentatives ratees, 3e bug decouvert.
Chantier B3 = 3 bugs separes (let-chain top-level, let-chain helper,
pattern `_` + `heaven run`). A attaquer en session fraiche, dans
cet ordre :
1. Discriminant `helper _ = 42` vs `helper x = 42` vs `helper 0 = 42`.
2. `heaven run` vs `--run-test` sur le meme fichier.
3. Fixer le split ou l'eval.

**E4b est bloque par ce 3e bug, pas par let-chain.** Un `http_server.hvn`
en 1 ligne top-level marche (test E4-triage plus tot : fd=4 sur
`@net_listen`, mais `@net_accept` n'a jamais ete atteint). A
re-tester avec le fix let-chain top-level (`66f0b32`).

## B3 #3 NON CONVERGENT (cutoff, 2026-10-19)

Trois tentatives de diagnostic, 0 convergence. Discriminants :

| Code | Resultat |
|---|---|
| `helper _ = 42` + `(helper 0)` | `ArityMismatch` |
| `helper x = 42` + `(helper 0)` | `ArityMismatch` |
| `helper _ = (let x 42 x)` + `(helper 0)` | `ArityMismatch` |
| `helper _ = (+ 1 2)` + `(helper 0)` | `ArityMismatch` |
| `import "stdlib/string.hvn"` puis idem | `ArityMismatch` |
| `--run-test` avec `test "call": (helper 0)` | `ArityMismatch` |
| **`mk_obj _ = (let b (raw_alloc 16) ...)` + `(mk_obj 0)` dans `test_json_v1.hvn`** | **PASS (12/12)** |

**Contradiction irrésolue** : `mk_obj` marche avec un corps `let` + appels,
`helper _ = (let x 42 x)` échoue. Même pattern `_`, même `let`, même
appel en `test`. Différence possible : `test_json_v1.hvn` contient
`import ... as JP` + `data ...` + plusieurs defs, qui active un chemin
différent dans `evalEquation`.

**Prochaine session = bisect.** Réduire `test_json_v1.hvn` jusqu'à
isoler ce qui fait marcher `mk_obj`. Pas de fix à l'aveugle.

**Impact** : E4b (serveur HTTP en .hvn) est bloqué. `core/http_server.hvn`
ne peut pas être écrit en top-level ni en `test "main":`.

