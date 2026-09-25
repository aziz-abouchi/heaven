# Heaven — Statut des fonctionnalités

Dernière mise à jour : 2026-09-25

Ce document est la **source de vérité** sur ce qui marche. Toute
affirmation du book ou du README doit pointer vers une ligne de ce
tableau. Si vous trouvez une divergence, corrigez le book, pas ce
document (sauf erreur manifeste).

Légende :
- ✅ **stable** — implémenté, testé, comportement fiable
- ⚠️ **partiel** — implémenté, limitations connues
- 🚧 **roadmap** — non implémenté, spec existe (voir `ROADMAP.md`)
- ❌ **absent** — non implémenté, aucune spec

---

## Noyau (Core IR)

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| 6 primitives | ✅ | `expr.zig::Primitive` | — |
| `Node` (`payload/aux/span_a/span_b`) | ✅ | `expr.zig::Node` | — |
| `nodeHash` | ✅ | `expr.zig` + 3 tests | — |
| `structuralEql` | ✅ | `expr.zig` + 8 tests | — |
| `lowerRec` idempotent | ✅ | `expr.zig` test `lowering is idempotent` | `hole`/`evar` non-primitifs → refusés par `assertCoreExpr` |
| `Tag.evar` (métavariables internes) | ✅ | `expr.zig::mkEvar`, `isEvar` + 3 tests | utilisé par tactics v3.5 |
| Hash-consing EGraph | ✅ | `egraph.add` + tests | collision pas testée à grande échelle |

## Parsing

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| Infixe (`+ - * / % ^ == != < > <= >=`) | ✅ | `nativeToSExpr` + tests | — |
| S-expression `(f a b)` | ✅ | `parseSExpr` (quote-aware) | — |
| `λx.body`, `\x.body`, `(λx.body)` | ✅ | 2 tests Zig | **le `.`**, pas `λx -> body` |
| `λx -> body` (flèche) | ❌ | — | notation non supportée |
| `module X` | ⚠️ | `heaven_expr.zig::current_module` | v0 : theorem aliasé, fn/let à venir |
| `import "path" as Name` | ✅ | `heaven_expr.zig::evalImport` | fn/let/theorem aliasés sous `Name.x` |

## Types

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| HM inference (`lit`, `apply`, `sym`) | ✅ | `types.Infer` + 4 tests | — |
| Arrow `a -> b` interne | ✅ | `Store.apply(sym("->"), …)` | — |
||Affichage arrow | ✅ | `typeStr` | — |
| Types paramétrés (`Maybe a`) | ⚠️ | `evalDataDecl` | paramètre `a` ignoré à l'enregistrement |
| Types dépendants (`Vec (succ n)`) | ⚠️ | `evalDataDecl` + v2c (`checkCtorDomainKind`) | index au-delà de `succ _`/`zero` non unifiés (v2f) |

## Data & Pattern matching

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `data Name = C1 \| C2 args` | ✅ | `evalDataDecl` | — |
| `data Name a = ...` | ⚠️ | enregistré | `a` ignoré |
| `data Name (n : Nat) = ...` | ✅ | `type_registry.zig` + 5 tests v2c/v2d | 1 param typé max (v0) |
| Pattern matching multi-clause | ✅ | `evalEquation` | ordre linéaire d'essai |
| Wildcard `_` en pattern | ✅ | test `let_many` | — |
| Guards `\| x > 0` | ❌ | — | jamais implémenté |

### Type-dep v2 (indexes dépendants)

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `data Vec (n : Nat) = Nil \| Cons a (Vec n)` | ✅ | test `type-dep v0` | — |
| `sig f : (n : Nat) -> Vec (succ n) -> a` | ✅ | test `type-dep v2c` | — |
| Vérif. structurelle patterns (arité, kind) | ✅ | `evalEquation` v2a/v2b/v2c | — |
| Convention base/step (`Nil`↔zero, `Cons`↔succ) | ✅ | `ctorKind`/`domainKind` | — |
| `ctor_results` (ctor → forme résultat) | ✅ | `evalDataDecl` v2d | arity>0 → `(succ _)` uniquement |
| Unification `ctor_results[ctor]` ~ domaine | ✅ | `evalEquation` v2e (`unify_proof` + `holesToEvars`) | best-effort : échec ≠ rejet |
| Instanciation RHS sous `subst_v2d` | ✅ | `registerClause(body_used)` (v2e) | no-op avant v2e : `_` = `Tag.hole`, non lié |
| Unification vraie (`Vec (n + m)` modulo arithmétique) | 🚧 | — | v2f roadmap |

**Note v2e (2026-09-25)** : un bug a été découvert en testant v2e —
`_` est parsé en `Tag.hole`, et `unify_proof.unify` ne lie que les
`Tag.evar`. Conséquence : `subst_v2d` restait **toujours vide** entre
v2d et v2e (`body_used == body`, no-op silencieux non détecté par les
tests v2d car le pattern matching engine liait les variables de pattern
indépendamment). Fix v2e : `Heaven.holesToEvars` remplace les holes par
des evars frais avant `unify`. Le message de succès expose
désormais `(subst: N)` quand N > 0. **v2e reste préparatoire** :
aucun body réaliste n'est affecté aujourd'hui (le body est parsé
depuis une string utilisateur, jamais d'evar dedans).


## Récursion & ordre supérieur

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| Récursion simple | ✅ | `fact`, `add` | pas de TCO |
| Récursion mutuelle | ✅ | `isEven`/`isOdd` | — |
| Curryfication | ✅ | `Store.lambda` currifie | — |
| `>>>` composition | ✅ | `evalMagic` | — |
| `map`/`filter`/`take` sur Stream | ✅ | `core/stream.hvn` | évaluation **stricte** |
| Paresse des streams | 🚧 | — | — |

## QTT

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `let linear/erased/many x = … in …` | ✅ | `countSymUses` + tests | — |
| Shadowing correct | ✅ | test `let_bind_shadowing_*` | — |
| `LinearViolation` | ✅ | 4 tests | — |
| **Documentation QTT** | ❌ | — | **absent du book** |

## Effets algébriques

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `perform "Op" v` | ✅ | `engine_expr` | one-shot |
| `handle e h` | ✅ | test `effect_handle` | one-shot |
| `green` profiler | ✅ | 2 tests | — |
| Multi-shot continuations | 🚧 | — | — |
| Handler IO par défaut | ✅ | `defaultIOHandler` (heaven_expr.zig) | — |
| `readFile`, `writeFile`, `readLine` | ✅ | `core/io.hvn` + handler | — |

## IO

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `print` (REPL) | ✅ | démo manuelle | — |
| `readFile` / `writeFile` / `readLine` | ✅ | démo manuelle | — |
| `:io on/off/status` | ✅ | REPL | — |
| Test automatisé IO | ✅ | `test "io_print"` | — |

## Preuves

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `theorem name : lhs = rhs` | ✅ | `evalTheorem` | seulement `lhs = rhs` |
| `prove by eval` | ✅ | `verifyByEval` | — |
| `prove by simplify` | ✅ | `verifyBySimplify` (fixpoint) | — |
| `prove by induction x` | ⚠️ | `verifyByInduction` | **pas testé** en suite standard |
| `prove by rewrite` | ⚠️ | `verifyByRewrite` | dépend de `canonEqStr` (stub) |
| `prove t by { ... }` (tactics) | ✅ | `runTacticsBlock` | simplify/refl/exact/induction/rewrite/apply/seq/try/repeat |
| Kernel CIC | ⚠️ | `kernel.zig` (~780 L) | structural OK, type-check limité |
| Types quotients | ❌ | — | — |
| Proof irrelevance | ❌ | — | — |
| Skills (`:skill`) | ✅ | `skill.zig` + `ProofSession` | refactor v2 : `body: []const u8` unifié |

## Holes

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `Tag.hole` | ✅ | `expr.zig:138`, `Store.hole` | — |
| `_` → `hole(0)` (elab) | ⚠️ | `elab.zig:104` | **même id 0 pour tous les trous** |
| `?` → hole (cmdHole) | ⚠️ | `commands.zig:686` | syntaxe arithmétique seulement |
| `Subst.bind/walk` | ✅ | `kanren_expr.zig` + 2 tests | — |
| Test `hole resolves type hole` | ✅ | `commands_full_test.zig:300` | résolution arithmétique simple |
| Hole filler (Matrix) | ✅ | `inference/neural/synthesis.zig` | couche Matrix, pas Core |
| But + contexte affichés | ❌ | — | — |
| `:refine` | ✅ | `commands.zig::cmdRefine` | — |
| **Syntaxe unifiée** | ⚠️ | `_` (expressions), `?` (cmdHole) | 2 syntaxes coexistent (compat) |

## Acteurs

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `fn handler(state, msg) = …` | ✅ | test suite | — |
| `let X = 0 with handler` | ✅ | test suite | — |
| `send(X, msg)` | ✅ | test suite | séquentiel |
| `state(X)` | ✅ | test suite | — |
| Parallélisme réel | 🚧 | — | pas de scheduler |

## Runtime & IO

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| REPL natif | ✅ | `main.zig` | — |
| Commandes vs équations | ✅ | `run.zig::hasTopLevelEqual`, `isCallToKnownFn` | les noms courts (`c`, `f`, `io`) restent utilisables |
| REPL web WASM | ✅ | `vessel/public/` | — |
| Serveur HTTP Vessel | ⚠️ | `vessel/` | `/api/*` non implémenté |
| WebRTC | ⚠️ | `webrtc.zig` + stub | stub en prod |
| TCC linké | ⚠️ | `vendor/tcc` | présent, non utilisé |
| ABI C (`extern fn`) | ❌ | — | **documenté ch9, absent** |

## Bibliothèque standard

| Module | Statut | Note |
|---|---|---|
| `core/std/bool.hvn` | ⚠️ | clauses `not/and/or` OK ; `true`/`false` **sans corps** |
| `core/std/list.hvn` | ⚠️ | clauses OK ; `nil`/`cons` **sans corps** |
| `core/std/option.hvn` | ⚠️ | `none`/`some` **sans corps** |
| `core/std/pair.hvn` | ⚠️ | `pair` **sans corps** |
| `core/std/result.hvn` | ⚠️ | `ok`/`err` **sans corps** |
| `core/stream.hvn` | ✅ | clauses complètes, testées |
| `core/bootstrap.hvn` | ⚠️ | `add`/`mul` OK ; signatures `theorem`/`prove` **sans corps** |

**Note** : `module X` en tête est **inert** (no-op). Les `: Type` sans `=` sont des signatures non enregistrées. Le `std/` est en fait "signatures + quelques clauses".

## Infrastructure

| Élément | Statut | Note |
|---|---|---|
| `zig build test` | ✅ | 162 tests |
| `zig build test-regression` | ✅ | 77 tests Heaven |
| `zig build test-files` | ✅ | `heaven --run-tests tests/` |
| `heaven --run-test <file>` | ✅ | runner multi-lignes (parens + braces) |
| `heaven --run-tests <dir>` | ✅ | itère sur les `*.hvn` d'un dossier |
| Sync `test_suite.hvn` natif ↔ WASM | ⚠️ | manuelle via `cp` |
| Kernel CIC tests | ✅ | 7 tests dans `kernel.zig` |
| EGraph tests | ✅ | 8 tests |

---

## Top priorités

1. **Découper `heaven_expr.zig`** (RFC-0001) — extraire IO, imports, data, holes,
   tactics. Le monolithe freine toute évolution (WASM, tests, onboarding,
   éventuel merge avec astra-core).
   → **✅ 5/5 complet** (2026-09-25) : `io_handler.zig`,
   `expr_parser.zig`, `hole_runtime.zig`, `unify_proof.zig`,
   `std_loader.zig`, `import.zig`. Monolithe 4367 → 4101 lignes.
2. **Unifier le pipeline logique** — `kanren_expr` + `logic/*` + `prolog`
   derrière une API `assertFact` / `query` + 2-3 commandes REPL.
   → **Étape 1** ✅ 2026-09-25 : `fact` + `query` en langage
   (kanren_expr, Store-based). Étapes 2-3 : `rule` (SLD simple),
   `?-` (Prolog) + raccord shell.
3. **README aligné sur STATUS** (✅ fait).
4. ~~**Type-dep v2d**~~ ✅ 2026-09-24 · ~~**v2e**~~ ✅ 2026-09-25
   (fix `holesToEvars` + exposition `subst_v2d`).
   → suite : **v2f** — unification vraie (`Vec (n + m)` modulo arithmétique).
5. **Documenter QTT** dans le book.
6. Remplir les `std/*.hvn` restants (`kernel.hvn`, signatures sans corps).
7. Sync auto `test_suite.hvn` (natif ↔ WASM).
