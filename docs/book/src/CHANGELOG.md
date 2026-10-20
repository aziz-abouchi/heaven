# Changements récents


## 2026-10-20 (matin) -- REPL, VFS, serveur HTTP pur, Fantasy Land, closure fix

### Book / REPL web

- **site-url="/heaven/"** : 404.html avec chemins absolus corrects
- **iframe REPL** pointe vers `/repl/index.html` explicite
- **VFS** : `/repl/core|stdlib|lib|tests/*.hvn` servis depuis leur vrai
  chemin (pas depuis `public/`). 0 fichier manquant au chargement.
- **cache-buster** : `extractHttpPath` strip `?` et `#` (`/repl/heaven.wasm?t=123` marche)

### Serveur HTTP en Heaven pur

- **`http_server.hvn` v1** : routing infixe (`if (string_ends_with p ".css") then ...`),
  4 routes statiques (`/`, `/common.css`, `/repl.html`, `/heaven.wasm`) — 200 OK.
- **`go.sh`** : `HEAVEN_NO_LEAK_CHECK=1` par défaut (threads démons).
- **`HEAVEN_NO_REPL=1`** : mode serveur-only sans SIGTTOU.

### Parser

- **`parsePostfix .str`** : `if (fn arg "str") then` marche (P0 résolu).
- **`string_ends_with`** retourne Bool (pas Int 0/1).

### Stdlib (`.hvn` pur, HKT V1b)

- **`fantasy_land.hvn`** : 10 classes Fantasy Land (McKenna) — Setoid, Ord,
  Semigroup, Monoid, Functor, Apply, Applicative, Chain, Monad, Foldable.
  13/13 tests.
- **`optics.hvn`** : Lens/Prism/Iso (Kmett simplifié) — 12/12.
- **`free.hvn`** : Free monad tag-encoded (Lonsdorf) — 6/6.
- **`transformers.hvn`** : MaybeT (Wilson) — 6/6.
- **`profunctor.hvn`** : partiel (dimap/lmap/rmap/pcompose).

### Runtime (Zig)

- **Capture de closure** : `mk_adder n _ = (lambda x -> (+ x n))` capture `n=3`.
  Fix `bound_syms` dans `evalFunction`. 8/8, 4/4, 2/2, 3/3, 8/8 sur 5 tests.
  Cas résiduel (ctor pattern 2-arg + ctor body) SIGSEGV, tracé.

### Baseline

ReleaseFast `--run-tests` = 0 fail. Debug = 0. wasm×2 = 0.


## 2026-10-19 (cloture) -- is_command, js_ollama_query, http_server.hvn v0

### Fix parser / evaluateur

- **`is_command`** (commit `51bf59a`) : les prefixes `help`, `stats`,
  `theorems`, `rules` (minuscule, sans espace) etaient traites comme
  commandes REPL. `helper _ = 42` silencieusement skippe. Toute une
  classe de noms de fonction mangee. Fix : match exact ou prefixe
  avec espace.
- **`js_ollama_query`** (commit `d8a33e8`) : le wasm freestanding
  importait `env.f` (nom de l'identifiant Zig) au lieu de
  `env.js_ollama_query` (nom du host JS). LinkError dans le REPL
  web. Fix : renommer l'extern dans les deux branches.

### Serveur HTTP en Heaven pur

- **`http_server.hvn` v0** (commit `2c35724`) : serveur multi-client
  en `.hvn`, 30 l. `@net_listen` + loop recursive + `@net_accept` +
  `@net_read` + `@net_write` + `@net_close`. Repond `hi`.
  Test : `curl http://127.0.0.1:8080/` -> `hi`.
- **`string_ends_with`** ajoute a `stdlib/string.hvn` (5/5 tests),
  avec warning documente (SIGSEGV en condition d'`if`).

### HKT V1b (pas 3)

- `@resolve_instance` et `@dispatch_instance` acceptent `.sym` en
  plus de `.lit.str` : `fmap List f xs` (commit `4841c6b`, 3 tests).
  V1b total 11 tests verts.

### Contraintes parser identifiees

- `string_eq` en condition d'`if` dans helper local -> SIGSEGV.
  `==` infixe OK. Voir `_syntax_gaps.md` section 2026-10-19.
- let-chain >= 3 niveaux dans helper -> valeur fausse.
- Forward ref de helpers -> mauvaise branche.

### Refutations

- **B3** entierement refute : le "3 bugs let-chain" venait de
  `is_command` qui mangeait `helper*`. Vrai fix : `normalizeLetChain`
  (`66f0b32`) pour le top-level run.
- **B2** entierement refute : les heredocs bash un-escapent `\n`
  avant ecriture. `printf` preserve. `\n`/`\r\n` marchent.

### Baseline

- ReleaseFast `--run-tests` = 0 fail (Debug = 3 crashes connus :
  test_parser, test_hashmap, test_bigint_d20).
- wasm32-freestanding = 0, wasm32-wasi = 0.


## 2026-10-19 (fin de session) -- HKT V1b 1+2, E5, B3 cutoff

### HKT V1b (matching structurel)

- **`@resolve_instance C T op`** -> `op_T` ou "". Table `instance_pairs`
  de V1a. Pas d'inference. 4 tests.
- **`@dispatch_instance C T op args...`** -> `op_T(args...)`. Type T
  passe en argument string (`fmap "List" f xs`). 4 tests (empty/
  one/multi + resolve intact).
- Décision : option A (matching structurel) retenue, cf. D-HKT1.

### E5 (partiel)

- **`bridge.zig`** : retire `matrix`/`fab` fields, imports
  `matrix_lib`/`autofab`. `startVesselServer(heaven, port, exiting)`.
  `main.zig` wrapper allégé.
- **E5-bis** : `main.zig` porte encore `Matrix.init`/`bob_loop`/
  `syncMatrixWithFile`. Extraction `bob_loop` = session suivante.

### B3 (let-chain) -- cutoff

- **FIXÉ** : `normalizeLetChain` top-level `heaven.eval` (`66f0b32`).
  `heaven run script.hvn` avec let-chain 2/3 niveaux OK.
- **KO** : let-chain helper `f _ = (let ... in let ... in body)`,
  `parseBodySmart`/`convertLetIn` non couvert.
- **NOUVEAU BUG** : `helper _ = 42` + `(helper 0)` en `heaven run`
  -> `ArityMismatch`. Probablement `splitStatements`/`runEvalFile`.
  Bloque E4b.
- **Tuto** : `docs/tutorials/no_let_chain.md` (workaround `fn`/`seq`).

### Baseline

- Debug=0, `zig build test`=0, ReleaseFast `--run-tests`=0 fail,
  wasm32-freestanding=0, wasm32-wasi=0.


## 2026-10-19 -- HTTP fullstack E3, JSON objects, baseline ReleaseFast

### Vessel / HTTP

- **E3a** : `serveTelemetry` délègue à `telemetry_store.render`.
  `WebBridge.store: *expr.Store`.
- **E3b** : `didSave` lit le fichier, split en statements,
  évalue via `Heaven.eval`. `WebBridge.heaven: *Heaven`.
  `syncMatrixWithFile` (stub) n'est plus appelé.
- **E3c** : dédup `heaven_expr`/`heaven_expr_mod`, retire
  `main_mod` orphelin de `bridge.zig`.

### JSON

- **H1/H2 clos** : le "bug" objects était un artefact de
  construction de string dans les tests (`\"` reste littéral en
  Heaven, 2 octets). Discriminants `test_disc2/3a/3b/5` : pattern
  OK, import qualifié OK, parser OK, lookup OK.
- Tests objects réels (`test_json_v1.hvn::mk_obj` via `poke_byte`),
  12/12.

### CI / baseline

- **3 crashes runner Debug-only** identifiés (`test_parser`,
  `test_hashmap`, `test_bigint_d20`, SIGSEGV). ReleaseFast = 0
  fail. Tracés dans `_runner_crashes_2026-10.md`. Priorité basse.
- Baseline 2026-10-19 : Debug build = 0, `zig build test` = 0,
  ReleaseFast `--run-tests` = 0 fail, wasm32-freestanding = 0,
  wasm32-wasi = 0.


## 2026-10-15 -- VFS, WASM 8 apps, book, fix type

### WASM / Web

- **wasm32-freestanding** : build exit=0 (contenu reel de wasm.zig
  restaure, `js_env` par alias).
- **8 apps Vessel** exposees : REPL, IDE, Dashboard, Docs, Tests,
  E-Graph, Process, Debugger.
- **GitHub Pages** : workflow `deploy.yml` (book + apps).
- **VFS** : 85 fichiers `.hvn` charges via fetch + manifest.
  `js_vfs_read_file` / `js_vfs_copy_buffer`.
- **`:load`** dans le REPL web : lit un fichier via le VFS et
  evalue chaque ligne.

### Book

- **Chapitres 19-23** : Algebres (Fantasy Land), HKT, CAS & E-Graph,
  HoTT, Validation.
- **5 SVG** : 19-algebras-chain, 20-hkt-functor,
  21-egraph-saturation, 22-hott-vs-cic, 23-validation-vs-result.

### Fix

- **`type true/"hello"/3.14`** retournaient `?`. Pre-reconnaissance
  directe des litteraux dans `typeOf`.
- **Separateur cmd/args** dans `repl.html::dispatch` (le wasm
  concatenait `"loadcore/std/list.hvn"`).
- **`File.content` + `Dir.openFile`** branches sur le VFS.


## 2026-10-14 -- C3 preemptif (D31), A-3a

### C3 -- Scheduler preemptif

- **Safepoint + budget de reductions** : `engine.reductions`
  decremente a chaque pas d'evaluation. A 0 -> `SuspendRequested`.
- **Fix livelock** : `schedule` avec budget insuffisant provoquait
  un freeze systeme. Fix A (garde budget==0) + Fix B
  (`.preempted` au lieu de `.blocked`).
- **`@budget_left`** : magic de cooperation budget-aware.
- **A-2** : hook capture conditionnel (`engine.capturing`) dans
  `evaluate`. Inerte en usage normal.
- **A-3a** : `TaskState.preempted` -- tache retriable au prochain
  `schedule`.

### Docs

- D31 + 3 addendums (`DECISIONS.md`).
- Specs : `_preemptive.md`, `_capture_eval.md`,
  `_cooperative_budget.md`, `_let_syntax.md`.
- Book : chapitre 13 (Concurrence) nuance.
- CI : `HEAVEN_NO_LEAK_CHECK=1` (aligne sur build.sh).

### Tests

- scheduler 3/3, preemptive 12/12, coop 4/4, split 3/3.


## 2026-10-09 (soir) -- Série Kmett + first-class + hex

### Série Kmett -- 4 chapitres, 3 modules

- **Ch14 -- Schémas de récursion** : `core/std/recursion.hvn`.
  `cata` (consommer), `ana` (générer), `hylo` (les deux), `para`
  (accès à la sous-structure). 22/22 tests.
- **Ch15 -- Optiques** : `core/std/lens.hvn`. Une lens est un couple
  `(getter, setter)`. `view`, `set_via`, `over`. 12/12 tests.
- **Ch16 -- Free monads** : `core/std/free.hvn`. AST d'opérations
  interprétable. Deux interpréteurs : `run_stack` (évaluation sur
  pile) et `run_trace` (collecte des logs). 14/14 tests.
- **Ch17 -- Catégories** : conceptuel. Foncteurs, monades,
  adjonctions, Yoneda. Documente pourquoi Heaven v0 ne peut pas
  (HKT, classes, quantification).

### Fix runtime -- fonctions first-class (`2810cc7`)

`((fst (pair g h)) 5)` échouait alors que `(let f (fst (pair g h))
(f 5))` marchait. Cause : dans `evaluate(.apply)`, la reconstruction
d'un `apply` gardait `span_a` avec l'opérateur original. 9 lignes.
Débloque les optiques, free monads, DSLs.

### Fix parser -- littéraux hex + parens triviales

- `0xFF` était tokenisé en `0` + `xFF` (deux tokens), produisant
  `(0 xFF)`.
- `parseFloat` acceptait `0x1` comme hex float C99 → `.float=1`.
- `(1) == 1` échouait (parens autour d'un atome produisaient un
  `apply` fantôme).

Corrigé dans `6fe55ec` + `0881c93`. `tests/test_parser_literals.hvn`
(23/23). Deux bugs préexistants débusqués au passage.

### RFC-0002 -- Bitstrings

- 4 magics bitwise (`band`, `bor`, `shl`, `shr`).
- P1 destructuration `<<x:4, y:8>>` -- 15/15.
- P2 construction `<<4:4, 5:4>>` -- 28/28 cumulés.
- P0 partiel : EBNF dans `GRAMMAR.md`. Tree-sitter différé (conflit
  GLR irréductible).

### Serveur HTTP statique (v2)

`core/http.hvn` remplace le hello-world par un vrai serveur de
fichiers statiques (~80 lignes) :

- Lit la requête (`io_read` + `string_of_bytes`).
- Extrait le path (`string_index_of` sur l'espace).
- Normalise : path terminant par `/` → `index.html`.
- Sert `src/vessel/public<path>` (`io_open` + `io_read`).
- 404 si absent, boucle infinie via `http_serve_loop` (TCO).
- Entrée : `http_serve unit`.

Usage : `./zig-out/bin/heaven run serve.hvn` puis
`curl http://localhost:8080/egraph-viz/`.

Permet de voir la viz egraph-viz (Qwen) en local, 100% Heaven.

### Book -- réorganisation

- Changelog avant les annexes (pas en préambule).
- Under the Hood en dernier chapitre (18).
- 8 transitions narratives ajoutées entre chapitres.

## 2026-10-08 (suite)

### Jalon 2 -- Structures de donnees en Heaven

- `core/std/array.hvn` : array mutable via raw_alloc. Push auto-resize.
- `core/std/string.hvn` : substring, index_of, starts_with. 15 tests.
- Magic `string_of_bytes(ptr, len)` pour construire une string depuis
  un buffer.

### Garde anti-shadowing

Les magics (`if`, `let`, `perform`, ...) ne peuvent plus etre
enregistres comme fonctions utilisateur. Message clair au lieu de
shadowing silencieux.

### Limites parser infix

- `if` prefixe sans parens casse.
- `if` multi-ligne avec `let-in` necessite des helpers nommes.
- Documente dans `docs/spec/_syntax_gaps.md`.

## 2026-10-07

Session fondatrice : **8 decisions structurantes**, ~42 tests nouveaux.

### Syscalls, IO, serveur (D10, D14, D16)

- **D10** : trois chemins d'acces systeme opt-in (A : `raw_syscall`,
  B : `@nom` via libc, C : freestanding `HEAVEN_NO_LIBC=1`).
- **D14** : IO en Heaven. 5 magics fins (`string_ptr`, `raw_alloc`,
  `raw_free`, `target_os`, `raw_syscall`). `io_open`/`io_read`/`io_close`
  dans `core/io_stream.hvn`.
- **D16** : serveur HTTP 100% Heaven. `core/http.hvn` repond sur 8080
  avec `Hello from Heaven`.

### Laziness, streams, BigInt (D12, D17)

- **D12** : laziness (`Tag.thunk` + `delay` / `force` + memoization).
  Streams paresseux dans `core/stream.hvn` (`stream_nats_from`,
  `stream_map`, `stream_filter`, etc.).
- **D17** : BigInt v0 en Heaven pur. `badd`, `bsub`, `bcmp`,
  `from_int`/`from_string`. Preuve : `10^26 + 1 > 10^26`.

### Syntaxe (D15, D18)

- **D15** : `let` magic symbol S-expr `(let name val body)`.
- **D18** : style Haskell multi-ligne. Loader par indentation +
  conversion `let x = v in body` -> `(let x v body)`. Le code devient
  lisible :

      http_serve_once unit =
        let sock = raw_syscall6 41 2 1 0 0 0 0 in
        ...

### Bugs resolus

- Multi-clauses (`parseBodySmart`).
- `force` dangling (`getPtr` apres `evaluate`).
- 3 sites `getPtr + evaluate` (actor, process, module alias).
- Panic `depth -= 1` sur `)` orpheline.
- `evalCmp` sur strings.

### Tests

- `test_stream_lazy.hvn` (8), `test_io_stream.hvn` (4),
  `test_bigint.hvn` (14), smoke 16.

### D8 3a-3-c-b -- Scheduler coopératif (2026-10-08)

- 4 magics : `add_task`, `schedule`, `yield`, `task_state`.
- Scheduler round-robin avec budget par tâche.
- Modèle redémarrable (pas de reprise exacte, cf Voie B).
- 3 tests dans `test_scheduler.hvn`.
- Nouveau chapitre `14-concurrency.md`.

## 2026-10-05

- Documentation mise à jour pour le pipeline HIR des déclarations `data` génériques.
- Ajout de la distinction entre types paramétrés (`List<a>`) et types dépendants (`Vec (n : Nat)`).
- Documentation du nouveau champ HIR `DataDecl.params`.

# Changelog du langage

## 2026-10-02 (après-midi)

### Ordre supérieur complet + compréhensions phase A (`f8e9535`)

Trois bugs racines :
1. **Symbole-fonction = valeur** : `evaluate(.sym)` rejettait
   tout symbole désignant une fonction user (UnboundVariable) --
   le bug « application partielle » du 28/09. `filter isBig ...`
   vivant. test_stream : 28 → 33/37.
2. **`defer env.delete` prématuré (3 sites)** : le corps d'une
   λ peut rendre une valeur différée qui résout le paramètre
   après la sortie -- le delete tuait le binding avant
   résolution. `filter (λx. (big x))` : suspension → résultat
   exact.
3. **Compréhensions phase A** : `(for (x <- xs) [(when p)] e)`
   désucré en texte vers `map`/`filter` du stdlib Stream.
   La forme carrée `[e | x <- xs, p]` et les générateurs
   multiples : phase B/C (tranchages ROADMAP).

Reste ouvert : le parseur de TEST (`parseOrDispatch`) ne
connaît pas λ S-expr -- 2 tests comprehension sur 12.

## 2026-10-02

### Cross-compilation QBE (--target)

- `compile-qbe <src> -o <out> [--target <name>]` : emet l'assembleur
  pour la cible demandee (QBE IL natif). Cibles : `amd64_sysv`,
  `amd64_apple`, `arm64`, `arm64_apple`, `rv64`.
- Sans `--target`, comportement natif inchange (QBE + cc + binaire).
- Verifie : assembleur correct produit pour les 5 cibles.
- Le binaire final pour cible etrangere necessite un cross-cc (non
  gere dans cette version).

### TCO mutuelle etendue - SCC 3+

- `fuseTailSCCs` generalise `fuseTailPairs` : tout SCC (2+ fonctions
  mutuellement recursives en tail) devient une fonction `$scc_N` avec
  tag dispatch a N branches. `findTailSCCs` utilise une fermeture
  transitive (Floyd-Warshall booleen).
- `f 1000000 = 200` sur un cycle `f -> g -> h -> f` (QBE + WASM).
- Non couvert : SCC avec arites differentes, trampolines generaux.
- Non-regression : 2-cycle (`isEven 100000000 = 1`), `fib`, `count_down`,
  `arith`.

### TCO mutuelle (QBE + WASM)

- WASM : `return_call` natif (proposal tail-call, wasmtime 49).
  `isEven 100000000 = 1` sur WASM, sans flag de pile.
- QBE : QBE 1.2 n'a pas de tail-call natif ; la recursion mutuelle
  est traitee par fusion SCC au niveau MIR. Une paire mutuellement
  recursive (a, b) devient une fonction `$scc_N` avec tag dispatch,
  les appels intra-SCC deviennent des appels a `$scc_N` avec tag
  constant. `isEven 100000000 = 1` sur QBE.
- Detection : `MirFunction.findTailPairs()`, dump debug via
  `HEAVEN_SCC_DUMP=1`.
- Non couvert : cycles de 3+ fonctions, trampolines generaux.
- Spec : `docs/spec/_tco_mutual.md`.
- Non-regression : `fib 25 = 75025`, `count_down 100000 = 100000`,
  `arith = 333338333350000` sur QBE et WASM.

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
- **C3 V0+ (2026-10-14)** : safepoint + `@budget_left` (coopération) +
  `TaskState.preempted` (retriable). Tests : scheduler 3/3,
  preemptive 12/12, coop 4/4, split 3/3.
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
- **Note (2026-10-06)** : `?-` Prolog, `:p-fact` et `:p-rule` sont
  désormais exposés au REPL (voir `12-knowledge.md`).
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

## 2026-10-09 — Chantier D21 : Unification du Lowering (100% complété)

### Pont Tree-sitter → Expr.Store
- **Statut** : ✅ COMPLÉTÉ
- **Nœuds supportés** : identifier, int, binary, call, pattern, simple_expr, var_decl, lambda
- **Commits** : `440a002` (let ... in), commit lambda
- **Impact** : Le pipeline principal peut désormais utiliser exclusivement le pont Tree-sitter pour toutes les primitives de base

### Lambdas
- Support du style classique : `\x. body`
- Curryfication automatique pour multi-paramètres
- Intégré dans : `03-syntax-in-functions.md` (à enrichir)

## 2026-10-15 (soir) -- Self-hosting : TCP, UDP, bitstrings P3

### Decisions
- **D-SH4** : pas de Zig std dans le code portable.
  `raw_syscall` ou `std.os.linux.syscall` uniquement.
- **D-SH1/2/3** : TLS via OpenSSL FFI, persistance Bitcask-like,
  IA via ONNX FFI.

### Livre
- **N1** : TCP client (@net_socket, @net_connect). Tests 5/5.
- **N1bis** : listen/accept/read/write raw syscalls. HTTP 13/13.
- **P3 bitstrings** : non aligne + /little + rest:bits. 74/74.
- **N2** : UDP socket (@net_socket_udp, @net_sendto, @net_recvfrom).
  DNS pur Heaven en cours (bloque par escape \x).

### Specs
- _selfhosting_roadmap.md : plan 9 etapes.
- _magic_0arg_gap.md : magics 0-arg strippes en RHS de let.
- _string_escape_gap.md : escapes \x non supportes.

### Book
- Chapitre 24 : Reseau.
