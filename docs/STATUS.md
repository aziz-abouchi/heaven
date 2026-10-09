# Heaven — Statut des fonctionnalités

Dernière mise à jour : 2026-10-09

Ce document est **genere** depuis `docs/status.json` par
`scripts/status_gen.py`. Ne pas editer a la main.

Légende :
- ✅ **stable** — implémenté, testé, comportement fiable
- ⚠️ **partiel** — implémenté, limitations connues
- 🚧 **roadmap** — non implémenté, spec existe (voir `ROADMAP.md`)
- ❌ **absent** — non implémenté, aucune spec

---

## Progrès récents

- **2026-10-05** : Stabilisation du pipeline syntax HIR pour les déclarations `data` génériques : Tree-sitter valide `data List<a> = Nil | Cons a (List<a>)`, tests `lower_test.zig` couvrent `Vec<n>` et `List<a>` récursif. Ajout du champ `DataDecl.params` dans l'AST HIR (initialisation du chemin children). Les paramètres génériques restent à propager dans l'elaboration et l'enregistrement runtime.
- **2026-10-02** : Unification arithmétique v2f complète (AC, succ, mul, identités, symbole `zero`) et testée sur types dépendants (`Vec (n+m)`). Commande REPL `:norm` opérationnelle.
- **2026-10-01** : Nettoyage massif du pipeline logique (~1500 lignes supprimées : term_bridge, typeo, evalo, legacy/).
- **2026-10-01** : Stabilisation du build WASM (475 Ko en ReleaseSmall) et création du stub wasm32_wasi.zig.

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
| `λx.body`, `\x.body` | ✅ | 2 tests Zig | — |
| `λx => body`, `λx -> body` | ✅ | commit 4e606c1 | — |
| `λ(x, y) => body` | ✅ | commit 4e606c1 | params entre parens |
| `λx y z. body` | ✅ | commit 4e606c1 | multi-params nus |
| `module X` | ⚠️ | `heaven_expr.zig::current_module` | v0 : theorem aliasé, fn/let à venir |
| `import "path" as Name` | ✅ | `heaven_expr.zig::evalImport` | fn/let/theorem aliasés sous `Name.x` |

## Types

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| HM inference (`lit`, `apply`, `sym`) | ✅ | `types.Infer` + 4 tests | — |
| Arrow `a -> b` interne | ✅ | `Store.apply(sym("->"), …)` | — |
| Types paramétrés (`Maybe a`) | ⚠️ | `evalDataDecl` | paramètre `a` ignoré à l'enregistrement |
| Types dépendants (`Vec (succ n)`, `Vec (n+m)`) | ✅ | `evalDataDecl` + v2f (`unify_proof` + `simplifyStep`) | unification arithmétique complète (AC, succ, mul, identités, zero) |

## Data & Pattern matching

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `data Name = C1 \| C2 args` | ✅ | `evalDataDecl` | — |
| `data Name a = ...` | ⚠️ | enregistré | `a` ignoré |
| `data Name (n : Nat) = ...` | ✅ | `type_registry.zig` + 5 tests v2c/v2d | 1 param typé max (v0) |
| Pattern matching multi-clause | ✅ | `evalEquation` | ordre linéaire d'essai |
| Wildcard `_` en pattern | ✅ | test `let_many` | — |
| Guards `\| x > 0` | ✅ | tests/guards.hvn (17/17) | ordre linéaire ; otherwise ; == normalisé |

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
| Unification vraie (`Vec (n + m)` modulo arithmétique) | ✅ | `unify_proof.zig` + `math.zig` (simplifyStep) | AC + succ + mul + identités + symbole zero + :norm REPL |

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
| Compréhensions `(for (x <- xs) [(when p)] e)` | ⚠️ | tests/comprehensions.hvn 10/12 | parseur de test λ : 2 échecs ; forme carrée = phase B |
| Récursion simple | ✅ | `fact`, `add` | pas de TCO |
| Récursion mutuelle | ✅ | `isEven`/`isOdd` | — |
| Curryfication | ✅ | `Store.lambda` currifie | — |
| `>>>` composition | ✅ | `evalMagic` | — |
| `map`/`filter`/`take` sur Stream | ✅ | `core/stream.hvn` | ordre supérieur réparé (f8e9535) : symbole ET lambda en argument |
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
| perf `prove by simplify` | ✅ | t_distrib 1416ms -> 66ms (a0a8485/9c90969) | convergence structurelle du pipeline -- comparaison d'Id jamais valide sur arbres ré-alloués |
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
| `send(X, msg)` | ✅ | test suite | acteur + handler ; séquentiel |
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

| Élément | Statut | Note |
|---|---|---|
| `core/std/bool.hvn` | ⚠️ | clauses `not/and/or` OK ; `true`/`false` **sans corps** |
| `core/std/list.hvn` | ⚠️ | clauses OK ; `nil`/`cons` **sans corps** |
| `core/std/option.hvn` | ⚠️ | `none`/`some` **sans corps** |
| `core/std/pair.hvn` | ⚠️ | `pair` **sans corps** |
| `core/std/result.hvn` | ⚠️ | `ok`/`err` **sans corps** |
| `core/stream.hvn` | ✅ | clauses complètes, testées |
| `core/bootstrap.hvn` | ⚠️ | `add`/`mul` OK ; signatures `theorem`/`prove` **sans corps** |

**Note** : `module X` en tête est **inert** (no-op). Les `: Type` sans `=` sont des signatures non enregistrées. Le `std/` est en fait "signatures + quelques clauses".

## Ontologie (2026-10-01)

Voir `docs/spec/_ontology.md` pour les decisions actees.

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `algo_catalog.zig` (ex-`ontology.zig`) | ✅ | 3 tests `zig test` | composant a cote du Core, strings |
| `ontology.zig` (squelette Phase 2) | ⚠️ | 3 tests `zig test` | non branche dans `build.zig` |
| Trust levels (asserted/derived/certified) | ✅ | test `trust filtering` | - |
| Provenance (source, source_id, timestamp) | ✅ | present sur chaque Concept/Relation | - |
| Subsomption is-a | ✅ | test `isA reflexive and transitive` | parent unique, pas de DAG |
| Relations typees (5 kinds) | ⚠️ | enum defini, non teste | pas de verif de coherence |
| Projection vers `expr.Store` | ❌ | - | Phase 3 |
| Emission SMT-LIB | ❌ | - | Phase 3 |
| Integration MPST | ❌ | - | Phase 4 |
| Commandes REPL (`:onto`) | ❌ | - | Phase 3+ |

Phases : 1 faite (`c651fa9`), 2 ce commit, 3 et 4 planifiees.

## Knowledge / RDF / RDFS (2026-10-01)

La couche Knowledge est distincte de `Expr` et ne constitue pas un
second IR. Elle conserve ses propres identifiants (`KnowledgeId`) et
n'est reliée a `Expr` que par des lowerings explicites.

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| Ressources URI / blank / literal | ✅ | `src/knowledge/resource.zig` | RDF minimal |
| Triples | ✅ | `src/knowledge/triple.zig` | pas de quad/context |
| Assertions | ✅ | `src/knowledge/assertion.zig` | confidence low/medium/high |
| Provenance | ✅ | tests KnowledgeStore | sources enumerees |
| Status asserted/imported/derived/inferred/certified | ✅ | `assertion.zig` | enum ferme |
| KnowledgeStore | ✅ | `src/knowledge/store.zig` | stockage lineaire POC |
| Plusieurs provenances pour un meme triple | ✅ | test Store | pas de deduplication |
| RDFS `subClassOf` transitif | ✅ | `src/knowledge/rdfs.zig` | seul fragment RDFS implemente |
| Fermeture non destructive | ✅ | test RDFS | resultat separe du Store |
| Reflexivite implicite | ❌ | test RDFS | `A -> A` non ajoute |
| Turtle | 🚧 | — | parseur a venir |
| `rdf:type`, domain, range, subProperty | 🚧 | — | hors POC |
| OWL / SPARQL | 🚧 | — | hors POC |
| Lowering explicite Knowledge -> Expr | 🚧 | — | contrat a definir par cas d'usage |

## Backends natifs et WASM (2026-09-30)

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| Compilation QBE (M3) | ✅ | `compile-qbe <src> -o <bin>` ; fib(25) = 75025 | sous-ensemble MIR (15 instr) ; TCO self-tail + mutuelle (fusion SCC 2+ membres) ; cross-compile `--target` (5 cibles) ; pas de strings/IO |
| Compilation WASM (M2a/M2b) | ✅ | `compile-wasm <src> -o <wat>` ; wasmtime run | sous-ensemble MIR ; TCO self-tail + mutuelle (fusion SCC + `return_call` natif) ; flag `-W max-wasm-stack` plus requis |
| Bench interprète | ✅ | `bench-interp <src> [N] [--loop M]` | in-process, pas de spawn |
| Bench QBE | ✅ | `bench-qbe` ; wall/cpu/energy/temp/RSS | RAPL root-only par défaut (CVE-2020-8694) |
| Bench WASM | ✅ | `bench-wasm` ; idem | bootstrap wasmtime ~5 ms amorti via `--loop` |
| Profiler plateforme | ✅ | `platform/profiler_*.zig` ; `getChildrenUsage`, `readEnergyUj`, `readTempMc` | Linux : RAPL + thermal_zone ; macOS/Windows : stubs |
| RAPL sans sudo | ✅ | `scripts/setup-rapl.sh` (Guix / NixOS / generique) | CVE-2020-8694 : lecture restreinte au root par defaut |

Métriques mesurées : wall, cpu (RUSAGE_CHILDREN pour bench,
RUSAGE_SELF pour interp), energy (RAPL package), temperature
(thermal_zone0), RSS pic.
Résultats de référence (`docs/spec/_bench.md`) :
- `count_down 100000` : QBE **0.06 ms** / WASM 0.11 ms /
  interprète 3500 ms.
- `fib 25` : QBE **1.15 ms** / interprète 29 824 ms.

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

## Concurrence et effets (2026-09-29)

| Élément | Statut | Preuve | Limitation |
|---|---|---|---|
| `spawn` / `tell` / `recv` (process) | ✅ | test_suite.hvn (3 tests) | prototype concurrence, mailbox FIFO, caller-driven |
| `run(pid)` (drain mailbox) | ✅ | test_suite.hvn (2 tests) | — |
| `bracket` / `local` / `catch` | ✅ | test_suite.hvn (5 tests) | syntaxe scoped, pas handle-rec |
| `handle-rec` (reprise) | 🚧 | — | nécessite continuations |
| Scheduler préemptif | 🚧 | — | C3 tranchée (budget + safepoints) |
| Distribution | 🚧 | — | C2 tranchée (Option D lazy copy) |

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
4. ~~**Type-dep v2d**~~ ✅ 2026-09-24 · ~~**v2e/v2f**~~ ✅ 2026-10-01 (unification arithmetique complete : AC + succ + mul + identites)
   (fix `holesToEvars` + exposition `subst_v2d`).
   ✅ v2f terminé — unification vraie (`Vec (n + m)` modulo arithmétique).
5. **Documenter QTT** dans le book.
6. Remplir les `std/*.hvn` restants (`kernel.hvn`, signatures sans corps).
7. ~~Sync auto `test_suite.hvn` (natif ↔ WASM).~~ [OK] (2026-10-01)

Chantiers identifiés le 2026-09-25 (pas encore planifiés) :

8. ~~**Spec formelle du langage** (pour LLMs) — `docs/spec/heaven.md`.~~ [OK] (2026-10-01)
   EBNF + sémantique des formes acceptées + erreurs canoniques.
   Descriptif d'abord (WYSIWYG), section « écarts connus ».
   5-7 sessions. Format : 1 fichier agrégé + `grammar.ebnf`
   + `errors.md`. Validation : tester qu'un LLM génère du
   code qui compile avec la spec seule en contexte.
9. **Uniformiser `src/platform`** — `native.zig` +
   `x86_64_linux.zig` + `x86_64_windows.zig` (~90 % identiques).
   Cible : 1 fichier commun + dispatch OS aux points critiques.
   1-2 sessions.
10. **Fusion kernel CIC** — `src/core/kernel.zig` (853 l.,
    TermPool) vs `src/kernel/*` (1727 l., AST). Cible :
    `src/kernel/` source de vérité, `core/kernel.zig` thin
    wrapper puis suppression. 2-3 sessions. Risque élevé
    (`proof_core`, `wasm.zig`, `cli/repl`, `frontend/parser`).
11. ~~**`readKey` → `platform`**~~ ✅ (2026-10-01) — sorti
    `readKeyUnix`, les `VK_*` et `INPUT_RECORD` de
    `interactive.zig` vers `platform.readKey()`. Cohérence
    avec la règle platform. 1 session.

### 2026-10-08 : Pipeline de Lowering (D21)

- **Stable** : Pont Tree-sitter -> Expr.Store via `lowerExprToStore`.
- **Nœuds gérés** : `identifier`, `int`, `binary`, `call`/`app_expr`, `pattern`.
- **Helper** : `lowerExprSource` encapsule le parsing pour usage externe.
- **Roadmap** : Extension à `let` et `lambda`, puis dépréciation de `UniversalIngestor` (Matrix/BobId).

### 2026-10-09 : HashMap Int→Int — durcissement (Jalon 2)

- **Stable** : map_new/get/put/has, resize auto (0.75), map_free — 23/23 tests, batterie intacte.
- **Fix** : cles negatives (map_hash normalise), clamp cap >= 1, resize libere l'ancien buffer.
- **Note** : moins unaire `(- 5)` non supporte (evalMagic) — workaround `(- 0 5)`, gap releve pour _syntax_gaps.md.

## 2026-10-09 : Chantier D21 (Lowering) COMPLÉTÉ pour let

**Statut** : ✅ Terminé  
**Impact** : Le pont Tree-sitter → Expr.Store gère désormais les expressions `let ... in`

**Changements** :
- Ajout de la gestion du nœud `var_decl` dans `lowerExprToStore`
- Contournement du quirk Tree-sitter où `1 in` est parsé comme `app_expr`
- Ajout de la gestion de `simple_expr` pour descendre dans l'AST
- `lowerExprSource` détecte `var_decl + body` et construit `bindSymWithBody`
- Tests `'x + 1'` et `'let x = 1 in x'` validés et nettoyés

**Prochaines étapes** :
- Étendre à `lambda` pour compléter le chantier D21
- Migrer progressivement les anciens chemins de parsing (Matrix/BobId)

### 2026-10-09 : HashMap v1 Str→Int (Jalon 2)

- **Stable** : smap_new/put/get/has/del/free — chaining, 39/39 (23 Int + 16 Str).
- **Hash** : fnv1a borné, xor dérivé de band/bor — les magics bitstrings servent la stdlib.
- **del sans tombstones** (unlink). UTF-8 validé : string_length compte des octets.

### 2026-10-09 : HashMap — map_del Int (tombstones)

- **Stable** : map_del carte Int→Int — tombstones (flag 2), chaîne de sondage préservée, réutilisation au put, purge au rehash.
- **50/50** — les deux cartes (Int et Str) ont le CRUD complet.
