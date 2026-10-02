# Changelog du langage

## 2026-10-02

### rewriteViaPipeline : convergence structurelle (a0a8485)

La détection de point fixe comparait les Ids -- or le pipeline
ré-alloue de nouveaux Ids à chaque passage, arbres identiques
compris. Break jamais pris : 10 rounds par côté, 20 saturations
e-graph. Fix : structuralEql aux 4 points de convergence.
**t_distrib : 1416ms -> 66ms (21x)**. Saturations : 20 -> 1.

Historique des fonctionnalités du langage. Les entrées sont en ordre
antéchronologique.

## 2026-10-01 (soir)

### Gardes en forme alignee -- continuation de clause (`89ead1f`, fix `b26eb9f`)

- Une ligne top-level commencant par `|` continue la derniere
  equation : memes nom/patterns, nouvelle garde. Pur sucre sur
  les clauses gardees (867ec43).
- Fix bisectione : use-after-free dans setLastEqLhs (hook en tete
  d'evalEquation liberait le LHS pendant que la continuation le
  lisait -- corruption tas, assert double-mapping DebugAllocator).
  867ec43 sain / 89ead1f crash -> memorisation deplacee en fin de
  parcours. Lecon : 28/28 sur la feature ne detecte pas un UAF ;
  la suite complete (convention #6) l'a attrape.
- tests/guards.hvn : 28/28.

## 2026-10-01

### Fix RAPL persistant (scripts/setup-rapl.sh)

- Nouveau script `scripts/setup-rapl.sh` qui detecte la plateforme
  et propose la bonne methode pour rendre lisible
  `/sys/class/powercap/intel-rapl/*/energy_uj` sans sudo (depuis la
  CVE-2020-8694, le kernel restreint la lecture au root).
- Guix System : snippet `/etc/config.scm` a coller, puis
  `guix system reconfigure`.
- NixOS : snippet `configuration.nix`, puis `nixos-rebuild switch`.
- Distro classique (lance en root) : installe
  `/etc/udev/rules.d/99-rapl-readable.rules`.
- `docs/spec/_bench.md` : la section RAPL renvoie vers le script.
- Resout la piste #4 du PROMPT_CONTINUITE.

### Knowledge / RDF / RDFS - POC

- Ajout de `src/knowledge/` : ressources URI/blank/literal, triples,
  assertions, provenance et `KnowledgeStore`.
- `KnowledgeId` reste distinct de `Expr.Id`.
- Ajout d'un reasoner RDFS minimal pour la fermeture transitive de
  `rdfs:subClassOf`.
- La fermeture est non destructive et produit des assertions
  `inferred`.
- Decision architecturale : Knowledge n'est pas un second IR ; tout
  passage vers le calcul Heaven passe par un lowering explicite vers
  `Expr`.
- Le POC ne couvre pas encore Turtle, SPARQL, OWL ou les autres regles
  RDFS.


### Guards sur clauses - `f p | cond = body` (`867ec43`)

- `FunctionClause.guard (?Id)` + `setLastGuard` : aucune signature
  existante modifiee. Extraction `|` a profondeur 0 du LHS,
  evaluation dans l'env des captures, refus -> nettoyage bindings,
  clause suivante (ordre lineaire preserve). `otherwise` = alias
  vers `true`. tests/guards.hvn : 17/17.
- Six bugs de suture corriges au passage : tokenizer LHS decalle
  apres extraction (preuve : les `__curry` comptaient les clauses
  `| otherwise`), split `=` face a `==`/`!=`/`<=`/`>=`, s-expr
  `==` non evaluable par evalMagic (normalisation de tete),
  `std.mem.replace` in-place = corruption de tas (SIGSEGV
  differe, diagnostique au gdb - buffer separe desormais).
- Conventions : #17 `std.mem.replace` exige src != dest ;
  #18 ASCII seul dans commands/patches/commits.
- Tranchages comprehensions poses dans ROADMAP (5 decisions,
  `7be1b81`).

### Tail Call Optimization (QBE + WASM)

- **Self-tail-calls** detectes et transformes en boucle dans les
  deux backends (`mir_qbe.zig`, `mir_wat.zig`). Un bloc est TCO si
  sa derniere instruction est un `call_user` vers la fonction
  courante et que le terminator est soit `ret(dest)`, soit un
  `jump` vers un bloc join pur (`phi+ret`).
- **QBE** : phi nodes d'entree pour les parametres (SSA strict),
  copies via temporaires. `count_down 10000000` compile et tourne.
- **WASM** : `local.set` directs (locals mutables). `count_down
  10000000` tourne **sans** le flag `-W max-wasm-stack=67108864`,
  qui n'est plus requis.
- Non-regression verifiee : `fib(25) = 75025`,
  `arith = 333338333350000`, `loop = 1000000` sur les deux backends.
- Limite : seuls les self-tail-calls sont couverts. La recursion
  mutuelle et les trampolines multi-fonctions restent a faire.

### Fix import readkey (45021e9)

- `interactive.zig` importait `platform/readkey.zig` depuis
  `src/runtime/shell/`, chemin qui ne resout pas. Fix :
  `../../platform/readkey.zig`.

### Ontologie - separation catalogue / semantique (Phases 1-2)

- **Renommage** : `src/core/ontology.zig` -> `src/core/algo_catalog.zig`.
  Le fichier est un catalogue d'algorithmes avec metadonnees de
  complexite, pas une ontologie au sens OWL/DL. Le nom `ontology` est
  libere pour un niveau semantique distinct (`c651fa9`).
- **Nettoyage** du catalogue : import `expr` mort supprime, ownership
  de `Concept.name` documente, `errdefer` ajoute, 3 tests
  (subsomption transitive, choix contextuel, classes d'equivalence)
  (`8c44091`).
- **Creation** de `src/core/ontology.zig` : squelette minimal avec
  `TrustLevel` (asserted/derived/certified), `Provenance`
  (source/source_id/timestamp), `Concept`, `Relation` (5 kinds),
  API `addConcept`/`addRelation`/`isA`/`filterByTrust`, 3 tests.
  Non branche dans `build.zig` - testable isolement via
  `zig test src/core/ontology.zig`.
- **Documentation** : `docs/spec/_ontology.md` passe de 5 questions
  ouvertes a 5 decisions actees.
- **Phases 3 et 4** planifiees : emission SMT-LIB + oracle Z3/cvc5,
  puis alimentation des labels MPST depuis l'ontologie.

### Tests

3 tests Zig ajoutes, executes isolement via `zig test`.

## 2026-09-30

### Compilation native QBE (jalon M3)
- Migration QBE 2021 (miroir figé) vers **v1.2** (release
  officielle c9x.me). Le miroir `andrewchambers/qbe` est abandonné.
- `heaven compile-qbe <src.hvn> -o <bin>` : parse -> MIR ->
  `emitQbe` -> qbe -> cc -> binaire natif.
- `heaven bench-qbe <src> [N] [--loop M]` : wall / cpu / energy
  RAPL / temperature / RSS.
- Compilation des fonctions utilisateur récursives (fib, choose) :
  fix en 3 bugs chaînés (`parseSExpr` pour `<`, `lowerRec`
  uniforme, `precompileUserFns` en 2 passes).
- **Intégré dans** : STATUS, BACKENDS, `_bench.md`.

### Compilation WASM via wasmtime (jalon M2b)
- `heaven compile-wasm <src.hvn> -o <bin.wat>` : MIR -> `emitWat`,
  exécution via `wasmtime run --invoke main`.
- `heaven bench-wasm <src> [N] [--loop M]`.
- `emitWatLoop` pour amortir le bootstrap wasmtime (~5 ms).
- Flag `-W max-wasm-stack=67108864` requis pour la récursion
  profonde (TCO WASM pas encore implémenté).
- **Intégré dans** : STATUS, BACKENDS, `_bench.md`.

### Benchmarking — 3 backends symétriques
- `heaven bench-interp` (in-process), `bench-qbe`, `bench-wasm`.
- Métriques : wall, cpu (RUSAGE_CHILDREN), energy (RAPL),
  temperature (thermal_zone), RSS.
- `bench/run.sh` : compare les 3 backends.
- `bench/progs/{count_down,arith,loop,fib}.hvn`.
- **Intégré dans** : `docs/spec/_bench.md` (méthodologie et
  résultats).

### Résultats marquants
- `count_down 100000` : QBE **0.06 ms** vs interprète 3500 ms
  (~59 000×).
- `fib 25` = 75025 : QBE **1.15 ms** vs interprète 29 824 ms
  (~26 000×).
- WASM (wasmtime) : ~2× plus lent que QBE, plus portable.

## 2026-09-29

### Scoped effects — `bracket` / `local` / `catch`
- Trois magic symbols synchrones : gestion de ressources, shadowing
  local, rattrapage d'erreur.
- `bracket(setup, body, teardown)`, `local(name, val, body)`,
  `catch(body, default)`. Synchrone, pas de continuations.
- 5 tests dans `test_suite.hvn`.
- **Intégré dans** : `docs/spec/_effects.md`, STATUS.

### Concurrence — décisions C1-C5 tranchées
- C1 : hybride sémantique-unifiée (coopératif garanti, préemption
  best-effort native).
- C2 : Option D (lazy closure copy) pour la distribution.
- C3 : reduction budget + safepoints.
- C4 : structured concurrency (scopes).
- C5 : sous-scheduler logique dédié.
- **Intégré dans** : `docs/spec/_concurrency.md`.

### Prototypes concurrence
- Prototype 1 : `spawn`/`tell`/`recv` (3 tests).
- Prototype 2-lite : `spawn(fn, init)` + `run(pid)` (2 tests).
- Prototype 3 : différé, nécessite décision continuations
  (`_continuations.md`).

### Migration `Store.applyArgs`
- Helper `Store.applyArgs(node)` + 7 sites migrés.
- Guard informatif `[apply DUP]` dans `store.apply`.
- **Intégré dans** : `docs/spec/_store_invariants.md`.

## 2026-09-25

### Windows — console UTF-8 + tab-completion + raw mode
- `x86_64_windows.zig::initConsole()` : `SetConsoleOutputCP(65001)`
  + `ENABLE_VIRTUAL_TERMINAL_PROCESSING`. Corrige l'affichage
  des caractères accentués (`op├®...` → `opérationnel`) et les
  couleurs ANSI.
- `enableRawMode` / `disableRawMode` (Windows) : `SetConsoleMode`
  sans `LINE_INPUT` / `ECHO_INPUT` / `PROCESSED_INPUT`.
  Tab-completion et flèches historiques fonctionnent.
- Raw mode **encapsulé dans `src/platform`** : `ConsoleRawMode` +
  `enableRawMode`/`disableRawMode` dans `x86_64_windows.zig` et
  `x86_64_linux.zig`. `interactive.zig` n'a plus de `#if OS`
  pour le raw mode (règle : tout le spécifique OS vit dans
  `src/platform/`).



### Type-dep v2e — fix bug silencieux v2d + `holesToEvars`
- **Bug découvert** : `_` est parsé en `Tag.hole`, et
  `unify_proof.unify` ne lie que les `Tag.evar`. Résultat :
  `subst_v2d` restait **toujours vide** entre v2d et v2e
  (`body_used == body`, no-op silencieux non détecté par les
  tests v2d car le pattern matching engine liait les variables
  de pattern indépendamment).
- **Fix** : `Heaven.holesToEvars` remplace les holes par des
  evars frais avant `unify`. Message de succès expose
  `(subst: N)` quand N > 0.
- **Portée honnête** : le mécanisme tourne, mais aucun body
  réaliste n'est affecté aujourd'hui (le body est parsé
  depuis une string utilisateur, jamais d'evar dedans). v2e est
  préparatoire à **v2f** (unification vraie `Vec (n + m)`
  modulo arithmétique).
- 2 tests : `subst:` présent sur type paramétré, absent sur
  type non paramétré.
- **Intégré dans** : `03-syntax-in-functions.md`, STATUS.

### Logic — `fact` / `query` en langage (étape 1)
- `Heaven.kanren` : instance de `kanren_expr.Kanren` (Store-based,
  pas `logic/kanren.zig` qui est `Term`-based).
- `fact name arg1 arg2 ...` : assert un fait dans le KB kanren.
- `query name arg1 ...` : pattern matching simple, `_` = hole,
  retourne le nombre de solutions.
- Utilisables dans un `.hvn` (pas seulement au shell).
- **Limitation** : pas de règles (`rule`), pas de `?-` Prolog.
  Étapes 2-3 à venir.
- **Intégré dans** : STATUS.md, ce changelog.

### Architecture — RFC-0001 5/5 (complet)
- Extraction de `import.zig` : `ImportState`, `resolveImportPath`,
  `evalImport` (~270 lignes retirées de `heaven_expr.zig`).
- Cycle `HeavenError` brisé : `ImportError = error{OutOfMemory}`
  local, wrapper dans `heaven_expr.zig`.
- Pattern `heaven: anytype` (déjà utilisé pour `std_loader`).
- `heaven_expr.zig` : 4367 → 4101 lignes.
- Découpage RFC-0001 terminé : `io_handler`, `expr_parser`,
  `hole_runtime`, `unify_proof`, `std_loader`, `import`.
- **Intégré dans** : `10-under-the-hood.md` (enrichi),
  STATUS.md.

## 2026-09-24

### Type-dep v2d — unification d'indexes dépendants
- `Heaven.ctor_results` : ctor → forme canonique du résultat
  (`Nil → "Vec zero"`, `Cons → "Vec (succ _)"`), peuplé dans
  `evalDataDecl`.
- `evalEquation` : unification best-effort via `unify_proof.unify`
  entre `ctor_results[ctor]` et le domaine déclaré ; instanciation
  du RHS sous la substitution avant `registerClause`.
- Tests : `ctor_results` peuplé, acceptation `Cons`, rejet v2c
  (`Nil` vs step), no-op types non paramétrés, end-to-end
  `head (Cons 42 Nil) → 42`.
- **Note** : infrastructure en place ; aucun test actuel ne prouve
  que la substitution **change** un résultat (à valider en v2e avec
  `Vec (n + m)`).
- **Intégré dans** : `03-syntax-in-functions.md`, STATUS.

### Architecture — RFC-0001 4/5
- Nouveaux modules extraits de `heaven_expr.zig` :
  `unify_proof.zig` (API proof/tactics : Ctx, Subst, unify,
  instantiate, rewriteIn), `std_loader.zig` (chargement boot-time
  io.hvn + std/*.hvn).
- Pattern : `heaven: anytype` pour éviter le cycle
  `heaven_expr ↔ std_loader`.
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

## 2026-09-23

### Types dépendants (surface) — chantier #type-dep
- `data Vec (n : Nat) = Nil | Cons a (Vec n)` : parsing + registre.
- `sig head : (n : Nat) -> Vec (succ n) -> a` : vérification qu'une
  signature Π est bien formée (règle CIC).
- Vérification structurelle des patterns : arité ctor, kind, et
  compatibilité base/step (`head _ Nil` rejeté, `head _ (Cons x _)` OK).
- **Intégré dans** : `03-syntax-in-functions.md`, `A-syntaxe.md`.

### Modules et imports — chantier #module
- `module M` ouvre un namespace.
- `import "path.hvn" [as Name]` charge un fichier et l'alias sous `Name.x`.
- `import Name` cherche `core/std/<nom>.hvn` puis `core/<nom>.hvn`.
- `export foo` : contrôle des alias sous `Name.x`.
- Détection de cycles, `HEAVEN_PATH`.
- `strict on/off` : mode opt-in qui n'enregistre les définitions que
  sous `M.x`.
- **Intégré dans** : `11-modules.md`, `A-syntaxe.md`.

### Tactics — chantier #tactics v1 → v4
- `prove t by { simplify; induction x; rewrite IH }` : bloc composable.
- Tactiques : `simplify`, `reflexivity`, `assumption`, `auto`,
  `cases x`, `induction x`, `rewrite H`, `apply H`, `exact h`,
  `seq`, `try`, `repeat`.
- REPL interactif : `prove t by {` ouvre un prompt `>` avec affichage
  `Goal N/N`.
- Unification simple via `Tag.evar` (métavariables internes).
- **Intégré dans** : `08-proofs.md`, `A-syntaxe.md`, `C-glossaire.md`.

### Stdlib
- Chargés au boot (`core/std/*.hvn`) : `Bool`, `List`, `Option`,
  `Pair`, `Result`.
- **Intégré dans** : STATUS, `01-starting-out.md` (indirectement,
  les exemples marchent).

### Noyau
- `Tag.evar` — métavariables internes (distinctes de `Tag.hole`).
- `Store.pi` — fix d'un bug historique (`payload` = Sym, pas Id).
- Pattern matching : `_` traité comme wildcard (tag `.hole`).
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

### Architecture
- Découpage RFC-0001 en cours : `io_handler.zig`, `expr_parser.zig`,
  `hole_runtime.zig` extraits de `heaven_expr.zig` (197 → 166 Ko).
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

### Documentation
- `docs/COMMANDS.md` : carte langage vs shell.
- `docs/capabilities.md` : design capabilities (WASI / Cap'n Proto).
- `docs/ROADMAP.md` : #units, #codegen-targets, #egraph-viz.

## 2026-09-22 et avant

Voir `git log` pour l'historique détaillé. Les features suivantes
sont déjà intégrées dans les chapitres :

- Holes v1 (`_`, `:hole`, `:refine`) — `08-proofs.md`.
- IO par effets (`print`, `readFile`, `writeFile`, `readLine`) —
  `06-effects.md`, `09-real-world.md`.
- QTT (`let linear/erased/many x = ... in ...`) — mention dans le
  book, à enrichir.
