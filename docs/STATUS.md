# Heaven — Statut des fonctionnalités

Dernière mise à jour : 2026-10-20

Ce document est **genere** depuis `docs/status.json` par
`scripts/status_gen.py`. Ne pas editer a la main.

Légende :
- ✅ **stable** — implémenté, testé, comportement fiable
- ⚠️ **partiel** — implémenté, limitations connues
- 🚧 **roadmap** — non implémenté, spec existe (voir `ROADMAP.md`)
- ❌ **absent** — non implémenté, aucune spec

---

## Progrès récents
- **2026-10-21 (nuit)** : `lib/web/ontology.hvn` DBpedia Lookup live (13/13). `resolve_host` mapping IPv4 + `http_build_get_ua` fix. MCP 5 tools stables E2E. Diagnostic `let+recursion` (5 discriminants, pas collision/shadow). Livre restructuré 4 parties + version 0.5 + 66 illustrations (0 orpheline).
- **2026-10-20 (nuit)** : fix `evalCmp` bytes-strings (`target_os == "..."` avec parens). `lib/syscall/linux_x86_64.hvn` (getrandom/read/write/openat via `raw_syscall`, 100% .hvn). `lib/random.hvn` LCG + `rand_os_linux` (entropie OS, 8/8). MPST V0.5 projection binaire (10/10). Style infixe mpst `project_side`. P0 parser identifie : 2 S-expr colles `(print "a")(print "b")` = 2e ignore. Baseline native + wasm = 0.

- **2026-10-20 (soir)** : TLS OpenSSL FFI (@tls_connect/read/write/close), HTTPS live depuis .hvn (Wikidata 200 OK). DNS parametre (dns_resolve_a_com host server). stdlib/effects.hvn + resume alias (5/5). stdlib/ontology.hvn (14/14) + example Socrate. urlencode (9/9). Fossile #4 documente. Baseline Debug=0, TEST=0, RF=0, wasm x2=0.
- **2026-10-20 (suite)** : `stdlib/ontology.hvn` (RDF/KB en .hvn pur, 14/14 tests), example Socrate 10 triples. Mots reserves documentes (`query`, `count`, `fact` interceptes par kanren). Book ch. 11 §7 'En .hvn pur'. Closure §2 refute (test malforme). Baseline ReleaseFast = 0 fail.
- **2026-10-20 (matin)** : REPL web repare (VFS, cache-buster, site-url). http_server.hvn v1 (routing infixe, 4 routes 200 OK). Fantasy Land (10 classes McKenna) 13/13 en .hvn pur via HKT V1b. Optics (Lens/Prism/Iso) 12/12. Free monad (Lonsdorf) 6/6. MaybeT (Wilson) 6/6. Closure capture fix (bound_syms) 8/8. parsePostfix .str resolu. Baseline ReleaseFast = 0 fail.
- **2026-10-19 (cloture)** : fix `is_command` (helper*/stats*/... manges), fix `js_ollama_query` (REPL book), `http_server.hvn` v0 (serveur HTTP Heaven pur, `hi` sur 8080), `string_ends_with` + warning, HKT V1b pas 3 (`.sym` accepte). Contraintes parser identifiees (`string_eq` SIGSEGV en `if`). B2 et B3 entierement refutes. Baseline ReleaseFast = 0 fail.
- **2026-10-19 (fin de session)** : HKT V1b pas 1+2 livres (`@resolve_instance`, `@dispatch_instance`, 8 tests). E5 partiel (`bridge.zig` sans matrix/autofab). B3 : let-chain top-level FIXE (`normalizeLetChain`), helper KO, 3e bug decouvert (pattern `_` + `heaven run`). Tuto `no_let_chain.md`. Baseline inchangee : Debug=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail, wasm=0/0.
- **2026-10-19 (fin de session)** : HKT V1b pas 1+2 livres (`@resolve_instance`, `@dispatch_instance`, 8 tests). E5 partiel (`bridge.zig` sans matrix/autofab). B3 : let-chain top-level FIXE (`normalizeLetChain`), helper KO, 3e bug decouvert (pattern `_` + `heaven run`). Tuto `no_let_chain.md`. Baseline inchangee : Debug=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail, wasm=0/0.
- **2026-10-19** : HTTP fullstack E1-E3 livre. `telemetry_store.zig` (JSON telemetry depuis `expr.Store`), `serveTelemetry` delegue a `render`, `didSave` evalue via `Heaven.eval` (plus de stub `syncMatrixWithFile`). `WebBridge.heaven: *Heaven`, accesseur `Heaven.getStore()`. Commits `00e1475`, `584e5e2`. JSON objects H1/H2 clos (`f2ee36c`) : le bug venait de l'echappement `backslash-quote` litteral dans les tests, pas du parser. 3 crashes runner identifies Debug-only (`0e606ef`). Baseline 2026-10-19 : Debug build=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail, wasm32-freestanding=0, wasm32-wasi=0.
- **2026-10-13** : Fix parser `unit`/`Unit` : retires des ctors 0-arity enregistres. Debloque `core/http.hvn`, `core/http_server.hvn`, `serve.hvn` — la stack web Heaven-native est operationnelle (`curl localhost:8080` sert `src/vessel/public/`).
- **2026-10-12** : D8 3a-3 livre pour la partie one-shot. `handle_rec`, `yield`, `schedule` passent par un mecanisme unique (`pending_capture` + `SuspendRequested`). Magics `@prompt`/`@throw` exposes. 53 tests verts (effects_rec, prompt_depth, scheduler, nested, continuations).
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
| `@prompt` / `@throw` (continuations one-shot) | ✅ | `tests/test_continuations.hvn` (5 tests) | one-shot : token invalide apres usage |
| `handle_rec` (reprise, one-shot) | ✅ | `tests/test_effects_rec.hvn` + `_nested.hvn` (22 tests) | reentrant, discriminant par prompt |
| Multi-shot continuations | 🚧 | — | clonage env + store a concevoir |
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
| Networking (TCP/UDP) | ⚠️ | TCP client (N1), UDP socket (N2), bitstrings P3 (74/74). Test N1 5/5, HTTP 13/13, UDP 2/2. | DNS pur Heaven non complet (escape \x manquant). TLS/T1 a faire. Voir _selfhosting_roadmap.md. |

## Bibliothèque standard

| Élément | Statut | Note |
|---|---|---|
| `core/std/bool.hvn` | ✅ | not/and/or + ctor true/false |
| `core/std/list.hvn` | ✅ | map/filter/take/drop/foldl/foldr |
| `core/std/option.hvn` | ✅ | none/some + map/bind |
| `core/std/pair.hvn` | ✅ | pair/fst/snd + map |
| `core/std/result.hvn` | ✅ | ok/err + map/bind |
| `core/std/array.hvn` | ✅ | acces indexe + taille |
| `core/std/string.hvn` | ✅ | concat/split/length/eq |
| `core/std/hashmap.hvn` | ✅ | get/put/del (Int->Int, Str->Int) |
| `core/std/lens.hvn` | ✅ | view/set_via/over (one-shot) |
| `core/std/recursion.hvn` | ✅ | cata/ana/hylo/para |
| `core/std/free.hvn` | ✅ | Pure/Push/Add/Mul/LogOp + interpreteurs |
| `core/stream.hvn` | ✅ | Stream paresseux (delay/force) |
| `core/bootstrap.hvn` | ⚠️ | add/mul OK ; signatures theorem/prove sans corps |

**Note** : `module X` en tete reste no-op syntaxique. Les modules listes ci-dessus exposent des clauses reelles et sont couverts par la suite de tests. Le bootstrap (`core/bootstrap.hvn`) reste partiel par construction.

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
| `handle-rec` (reprise, one-shot) | ✅ | `test_effects_rec.hvn` + `test_effects_rec_nested.hvn` | discriminant par prompt |
| `@prompt` / `@throw` (continuations delimitees) | ✅ | `test_continuations.hvn` (5 tests) | one-shot |
| Scheduler préemptif | ⚠️ | test_scheduler 3/3, test_preemptive 12/12, test_preemptive_coop 4/4, test_preemptive_split 3/3 ; TaskState.preempted (A-3a) : reprise par redemarrage | reprise exacte exige captureCont (3a-3b). Bug (+ 1 2 3 4) dans lambda trace separement. |
| Distribution | 🚧 | — | C2 tranchée (Option D lazy copy) |

## Top priorités

- **HTTP fullstack E4** (1-2 sessions de conception). `core/http_server.hvn` : inventaire sockets `.hvn`, JSON-RPC encode/decode en `.hvn`, decision statiques Zig vs `.hvn`. Voir `_http_fullstack_plan.md`.
- **E5** : matrix/autofab -> `src/legacy/`. Apres E4.
- **effects-consolidation** (1-2 sessions). `perform`/`handle`/`yield`/`resume` coherents. Pre-requis MPST-V2 et A-3b-3.
- **hkt-v1b** (2 sessions, decision A vs B). Dispatch typeclass.
- **mpst-v2a** (2 sessions). Multipartite + projection.
- **metacircularite-patterns** (2-3 sessions). Manque #2 de `_metacircularite_chantier.md`.
- **quotients-expose** (2-3 sessions). Kernel pret, exposition `.hvn` reste.


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

### 2026-10-09 : Jalon 3 v0 — le moment D (lex + parse + eval en Heaven)

- **Stable** : lib/heaven_parse.hvn (fusion) + lib/heaven_eval.hvn — un .hvn lit, lex, parse et évalue un .hvn (fac 5 = 120, 13/13).
- VRecClosure (récursion), if paresseux (VIf1/VIf2), prims curryfiés, env liste persistante.
- Fossiles d'import du jour exhumés et contournés (voir _syntax_gaps) — condamnés par construction à la phase E.

### 2026-10-12 : L'affaire Debug + le collapse du lexer

- **Fausse alerte intégrale du matin** : binaire Debug (83 Mo, frames ×4) → 4 suites mortes pour rien. Règle 6 : ReleaseFast obligatoire. Fossile TCO de vendredi corrigé — le bounce gère les args calculés, la vraie cause était le cycle des émetteurs.
- **Fix** : lexer collapsé en lex_loop unique self-tail (bf22d08) — 13 lignes. Lexing 1600 tokens ✓, DIFF 22/22 à pile par défaut. Le fosile différentiel meurt, la phase E n'a plus d'obstacle.

## 2026-10-19 : E3 Vessel + H1/H2 clos

### HTTP fullstack E3 (Vessel)

- **E3a** (`0bdc6e9`) : `serveTelemetry -> telemetry_store.render`, `WebBridge.store: *expr.Store` plombe.
- **E3b** (`00e1475`) : `didSave -> Heaven.eval` (read + split + eval loop). `WebBridge.heaven: *Heaven`. `Heaven.getStore()` pub, `splitStatements` pub. `syncMatrixWithFile` (stub no-op) n'est plus appele par bridge.
- **E3c** (`584e5e2`) : dedup `heaven_expr`/`heaven_expr_mod`, retire `main_mod` orphelin.

### JSON objects (H1/H2 clos)

- `_json_object_bug.md` amend : le "bug" etait un artefact de construction de string dans les tests (`\"` reste litteral en Heaven, 2 octets). Discriminants test_disc2/3a/3b/5 : pattern OK, import qualifie OK, parser OK, lookup OK.
- Tests objects reels ajoutes dans `test_json_v1.hvn` (`mk_obj` via `poke_byte`, 2 tests). Total 12/12.

### Runner --run-tests

- 3 crashes Debug-only identifies (`test_parser`, `test_hashmap`, `test_bigint_d20`, SIGSEGV). ReleaseFast = 0 fail. Traces dans `_runner_crashes_2026-10.md`. Priorite basse.

### Baseline 2026-10-19

- `zig build` = 0, `zig build test` = 0, ReleaseFast `--run-tests` = 0 fail, `wasm32-freestanding` = 0, `wasm32-wasi` = 0.


## 2026-10-19 (fin) : HKT V1b, E5, B3 cutoff

### HKT V1b (matching structurel, option A)

- `@resolve_instance C T op` -> `op_T` ou "" (`62155ce`).
- `@dispatch_instance C T op args...` -> `op_T(args...)` (`1ba6aa4`). Type T passe en argument string.
- Tests : `test_hkt_v1b_step1.hvn` (4), `test_hkt_v1b_step2.hvn` (4).
- D-HKT1 tranchee : pas d'inference, matching explicite.

### E5 (partiel)

- `bridge.zig` : plus de `self.matrix`/`self.fab` ni imports. `startVesselServer(heaven, port, exiting)` (`0ece80f`).
- `main.zig` porte encore `Matrix.init`/`bob_loop`/`syncMatrixWithFile`. E5-bis = extraction `bob_loop` en `src/runtime/`.

### B3 (let-chain) cutoff

- FIXE : `normalizeLetChain` top-level `heaven.eval` (`66f0b32`). `heaven run` avec let-chain OK.
- KO : helper `f _ = (let ... in let ... in body)` via `parseBodySmart`/`convertLetIn`. Rollback.
- NOUVEAU : `helper _ = 42` + `(helper 0)` en `heaven run` -> `ArityMismatch`. Probablement `splitStatements`/`runEvalFile`. **Bloque E4b**.
- Tuto `docs/tutorials/no_let_chain.md` (workaround `fn`/`seq`).

### Baseline

- Debug=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail, wasm32-freestanding=0, wasm32-wasi=0.


## 2026-10-19 (fin) : HKT V1b, E5, B3 cutoff

### HKT V1b (matching structurel, option A)

- `@resolve_instance C T op` -> `op_T` ou "" (`62155ce`).
- `@dispatch_instance C T op args...` -> `op_T(args...)` (`1ba6aa4`). Type T passe en argument string.
- Tests : `test_hkt_v1b_step1.hvn` (4), `test_hkt_v1b_step2.hvn` (4).
- D-HKT1 tranchee : pas d'inference, matching explicite.

### E5 (partiel)

- `bridge.zig` : plus de `self.matrix`/`self.fab` ni imports. `startVesselServer(heaven, port, exiting)` (`0ece80f`).
- `main.zig` porte encore `Matrix.init`/`bob_loop`/`syncMatrixWithFile`. E5-bis = extraction `bob_loop` en `src/runtime/`.

### B3 (let-chain) cutoff

- FIXE : `normalizeLetChain` top-level `heaven.eval` (`66f0b32`). `heaven run` avec let-chain OK.
- KO : helper `f _ = (let ... in let ... in body)` via `parseBodySmart`/`convertLetIn`. Rollback.
- NOUVEAU : `helper _ = 42` + `(helper 0)` en `heaven run` -> `ArityMismatch`. Probablement `splitStatements`/`runEvalFile`. **Bloque E4b**.
- Tuto `docs/tutorials/no_let_chain.md` (workaround `fn`/`seq`).

### Baseline

- Debug=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail, wasm32-freestanding=0, wasm32-wasi=0.


## 2026-10-20 : REPL, serveur pur, Fantasy Land, closure

### Book / REPL web

- `site-url="/heaven/"` : 404.html chemins absolus corrects.
- iframe REPL pointe vers `/repl/index.html` explicite.
- VFS : `/repl/core|stdlib|lib|tests/*.hvn` depuis vrai chemin. 0 fichier manquant.
- cache-buster : `extractHttpPath` strip `?` et `#`.

### Serveur HTTP en Heaven pur

- `http_server.hvn` v1 : routing infixe `if (string_ends_with p ".css") then ...`. 4 routes 200 OK.
- `go.sh` : `HEAVEN_NO_LEAK_CHECK=1` par defaut.
- `HEAVEN_NO_REPL=1` : mode serveur-only sans SIGTTOU.

### Stdlib (`.hvn` pur, HKT V1b)

- `fantasy_land.hvn` : 10 classes McKenna, 13/13.
- `optics.hvn` : Lens/Prism/Iso Kmett, 12/12.
- `free.hvn` : Free monad Lonsdorf, 6/6.
- `transformers.hvn` : MaybeT Wilson, 6/6.
- `profunctor.hvn` : partiel (dimap/lmap/rmap).

### Runtime

- Capture de closure : `bound_syms` dans `evalFunction`. 8/8, 4/4, 2/2, 3/3, 8/8.
- Cas residuel ctor pattern 2-arg + ctor body SIGSEGV, trace.
- parsePostfix `.str` : `if (fn arg "str")` marche.
- `string_ends_with` retourne Bool.

### Baseline

- ReleaseFast `--run-tests` = 0 fail. Debug = 0. wasm x2 = 0.

## 2026-10-21 (session 3)
- 4 commits: skip parser, scheduler run_n, doc MCP wip, kernel multi-taches
- Regle let-in-if documentee, SEGV runner localise, MCP loop 2 panics
- Baseline 10/10 fichiers .hvn verts
