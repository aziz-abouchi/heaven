# Heaven — Statut des fonctionnalités

Dernière mise à jour : 2026-09-22

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
| `lowerRec` idempotent | ✅ | `expr.zig` test `lowering is idempotent` | `hole` non-primitif → refusé par `assertCoreExpr` |
| Hash-consing EGraph | ✅ | `egraph.add` + tests | collision pas testée à grande échelle |

## Parsing

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| Infixe (`+ - * / % ^ == != < > <= >=`) | ✅ | `nativeToSExpr` + tests | — |
| S-expression `(f a b)` | ✅ | `parseSExpr` | — |
| `λx.body`, `\x.body`, `(λx.body)` | ✅ | 2 tests Zig | **le `.`**, pas `λx -> body` |
| `λx -> body` (flèche) | ❌ | — | notation non supportée |
| `module X` | ⚠️ | `commands.zig:186` + tree-sitter | **reconnu, no-op** |
| `import "path"` | ⚠️ | `elab.zig::elabImportDecl` | parse, ignore la cible |

## Types

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| HM inference (`lit`, `apply`, `sym`) | ✅ | `types.Infer` + 4 tests | — |
| Arrow `a -> b` interne | ✅ | `Store.apply(sym("->"), …)` | — |
||Affichage arrow | ✅ | `typeStr` | — |
| Types paramétrés (`Maybe a`) | ⚠️ | `evalDataDecl` | paramètre `a` ignoré à l'enregistrement |
| Types dépendants (`Vector n`) | ❌ | — | — |

## Data & Pattern matching

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `data Name = C1 \| C2 args` | ✅ | `evalDataDecl` | — |
| `data Name a = ...` | ⚠️ | enregistré | `a` ignoré |
| Pattern matching multi-clause | ✅ | `evalEquation` | ordre linéaire d'essai |
| Wildcard `_` en pattern | ✅ | test `let_many` | — |
| Guards `\| x > 0` | ❌ | — | jamais implémenté |

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
| Handler IO par défaut | 🚧 | — | voir `ROADMAP.md#io` |
| `readFile`, `writeFile` | ❌ | — | **documentés ch9, absents** |

## Preuves

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `theorem name : lhs = rhs` | ✅ | `evalTheorem` | seulement `lhs = rhs` |
| `prove by eval` | ✅ | `verifyByEval` | — |
| `prove by simplify` | ✅ | `verifyBySimplify` (fixpoint) | — |
| `prove by induction x` | ⚠️ | `verifyByInduction` | **pas testé** en suite standard |
| `prove by rewrite` | ⚠️ | `verifyByRewrite` | dépend de `canonEqStr` (stub) |
| Kernel CIC | ⚠️ | `kernel.zig` (~780 L) | structural OK, type-check limité |
| Types quotients | ❌ | — | — |
| Proof irrelevance | ❌ | — | — |
| Tactiques composables | 🚧 | — | voir `ROADMAP.md#tactics` |

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
| `:refine` | ❌ | — | — |
| **Syntaxe unifiée** | ❌ | 3 syntaxes (`_`, `?`, `_n`) | — |

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
| `zig build test` | ✅ | 111 tests |
| `zig build test-regression` | ✅ | 67 tests Heaven |
| Sync `test_suite.hvn` natif ↔ WASM | ⚠️ | manuelle via `cp` |
| Kernel CIC tests | ✅ | 7 tests dans `kernel.zig` |
| EGraph tests | ✅ | 8 tests |

---

## Top priorités

1. **IO par effets** (`readFile`, `writeFile`, `print`) — `ROADMAP.md#io`
2. **Holes interactifs unifiés** — `ROADMAP.md#holes`
3. **Tactiques composables** — `ROADMAP.md#tactics`
4. Fix `typeStr` arrow (`-> -> _t0`)
5. **Documenter QTT** dans le book
6. Remplir les `std/*.hvn` (corps manquants)
7. Sync auto `test_suite.hvn`
