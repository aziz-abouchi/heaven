# Bug : QTT bindings — 3 bugs de pipeline (2026-11-10)

**Statut** : identifié, non corrigé.
**Fichiers** : `src/core/expr_parser.zig`, `src/core/expr.zig`,
`src/compiler/ast_bridge.zig`.
**Découvert par** : diagnostic Session 46 (soir).
**Contredit** : `29-memoire.md` qui promet
`let linear x = 42 in x + 1` → `6` sans condition.

## Symptôme

Le QTT bindings (`let linear/erased/many x = v in body`) ne marche
que dans **un seul cas** : dans un bloc `test "..."` avec body
en **préfixe S-expr**.

| Forme | Résultat | Attendu |
|---|---|---|
| `test "x": (let linear x = 5 in (+ x 1)) == 6` | ✓ passe | 6 |
| `let linear x = 5 in x + 1` (top-level) | `syntax error in let` | 6 |
| `(let linear x = 5 in x + 1)` | `(linear := x)` | 6 |
| `main _ = let linear x = 5 in x + 1` | `ArityMismatch` | 6 |

`features_smoke.hvn` (44/44) passe parce que toutes ses
assertions QTT utilisent le **premier** format uniquement.

## Cause probable (3 chemins distincts, 3 bugs)

### Chemin 1 — top-level direct

`nativeToSExpr.parseLetExpr` (`src/core/expr.zig`, ~ligne 2100)
attend `let <name> = <val> in <body>`. Il ne connaît pas
`linear/erased/many` comme mots-clés QTT. `linear` est lu comme
`<name>`, `x` devient un token parasite → `syntax error in let`.

### Chemin 2 — S-expr parenthésée

`parseSExpr` (`src/core/expr_parser.zig:679-760`) reconnaît `let`
et tente de distinguer les cas. Mais le résultat est
`(linear := x)` — un `bind(linear, x)` au lieu de
`bindQTT(linear, x, 5, x+1)`. La branche QTT
(`let-linear x v b`) n'est **pas atteinte** ; la tokenization a
probablement mangé `=` ou `in`.

### Chemin 3 — dans une def

`buildEqDecl` (`src/compiler/ast_bridge.zig`) parse le body.
La sous-expression `let linear …` n'est pas reconnue par
`buildExpr` → `ArityMismatch`.

## Doc mensongère — `29-memoire.md`

Le piège d'entrée du ch.29 dit :

> **La vérification des multiplicités est faite** (au parse,
> testée 7/7). ... Un `let linear x = 42 in (x + x)` est
> `LinearViolation`. **Ne sont pas couverts** : le REPL erased
> et les multiplicités sur `fn`/paramètres.

La doc **omet** que le top-level, l'infixe, et les defs ne
marchent pas non plus. Elle présente QTT bindings comme presque
complet, en réalité **seule la forme `(let linear x = v in body)`
dans un test passe**. À corriger ou à fixer.

## Tests existants (ne pas casser au fix)

- `tests/features_smoke.hvn` : 3 tests QTT (formes S-expr préfixe)
- `tests/test_qtt.hvn` : 7 tests (à vérifier au moment du fix)
- `tests/test_qtt_*.hvn` : autres

**Tout fix QTT bindings doit préserver ces tests.**

## Fix plan (Session 47)

3 sous-blocs indépendants, du plus simple au plus profond :

### Sous-bloc 1 — top-level direct (5-10 lignes)

`parseLetExpr` : détecter `linear/erased/many` en tête de `let`
et produire `(let-linear x val body)` (S-expr). Le reste du
pipeline sait déjà traiter cette forme (elle passe dans
`features_smoke`).

### Sous-bloc 2 — S-expr parenthésée (10-15 lignes)

Tracer pourquoi `(let linear x = 5 in x + 1)` produit
`(linear := x)`. Diagnostic : `HEAVEN_PARSE_DEBUG=1` sur la
forme exacte, dump des tokens, voir où `=` ou `in` est perdu.

### Sous-bloc 3 — dans une def (15-30 lignes)

`buildEqDecl` : détecter `let` en début de body et déléguer à
`parseLet` / `parseQTTLet` avant le traitement normal.

## Décision QTT fn (préalable à son implémentation)

`_runtime_gaps.md:1502` documente 3 options (session 40) :

| Option | Syntaxe |
|---|---|
| A | `fn f [linear x]` ou `fn f (linear! x)` |
| B | `fn f(x) linear` (postfix) |
| C | Ne rien faire (`linear(x)` = ctor) |

**Recommandation : Option A avec `linear!`** —
`fn f (linear! x)`. Le `!` n'est utilisé nulle part dans un
pattern, donc zéro ambiguïté. `[linear x]` entre en conflit
potentiel avec les patterns liste (`[a, b, c]`).

## Priorités (mises à jour)

`_runtime_gaps.md:1526` dit « **Non prioritaire** : UTCP/MCP a
un impact supérieur ». **Cette évaluation est périmée depuis
Session 46** :

- MCP a atteint son plateau honnête (16/16 listables+callables,
  12 stables, test différentiel en CI).
- QTT est le différenciateur unique de Heaven :

| Langage | QTT | EGraph | Dependent | Tactic kernel |
|---|---|---|---|---|
| Rust | ✗ | ✗ | ✗ | ✗ |
| Idris 2 | ✓ | ✗ | ✓ | partiel |
| Lean 4 | ✗ | ✗ | ✓ | ✓ |
| **Heaven** | ✓ (let) | ✓ | ✓ | ✓ |

Aucun langage mainstream ne combine les 4. Heaven le fait, mais
QTT est limité aux `let` S-expr dans `test` blocks. **C'est une
promesse rhétorique tant que les 3 bugs ne sont pas fixés.**

**Self-hosting** : prématuré tant que QTT bindings et QTT fn ne
sont pas fonctionnels. Ordre logique :
QTT bindings → QTT fn → kernel tactics (enrichir) → self-hosting.

## Voir aussi

- `_runtime_gaps.md:1502` (décision QTT fn)
- `29-memoire.md` (doc livre — à corriger ou valider par fix)
- `tests/features_smoke.hvn` (tests existants)
- `_tool_audit_2026-11-09.md` (état MCP)
