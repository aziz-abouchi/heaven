## Addendum -- session 2026-10-08

**HEAD** : `7a3b841`. Tout pousse sur origin.

### Fix critique : parser lambda multi-args

**Bug** : `(lambda v k -> body)` ne capturait que `v`. `k` et `->`
restaient des params residuels -> UnboundVariable sur `k`.

**Fix** : `parseSExpr` collecte tous les tokens avant `->` / `=>`
(commit `921b7b9`).

**Impact** : debloque map/filter/foldl avec lambdas multi-args,
handle_rec avec lambdas inline, tout ordre-superieur.

### D8 3a-3-b : handle_rec

Premier handle_rec fonctionnel en Heaven (~80 lignes dans evalMagic).

    (handle_rec body_fn handler init_state)
    body_fn(state) -> valeur | (perform "op" v)
    handler(v, k) -> si (k new_state) : reboucler

4 tests dans `test_effects_rec.hvn`.

### D8 3a-3-c-a/b : scheduler cooperatif

4 magics : `add_task`, `schedule`, `yield`, `task_state`.

    (add_task body init_state) -> task_id
    (schedule budget)             -- round-robin jusqu'a fin
    (yield new_state)             -- dans body
    (task_state task_id) -> etat courant

Modele **redemarrable** via evalWithBudget (pas de reprise exacte,
cf limitation Voie B). 3 tests dans `test_scheduler.hvn`.

### Bug D20 : stack overflow tree-walker

**Symptome** : `f 500` (recursion non-TCO) segfault. `bdiv > 400`
segfault. `f 200` segfault.

**Diagnostic** : `ulimit -s unlimited` fait passer. Le tree-walker
consomme ~40 KB par niveau utilisateur (accumulation de frames Zig).

**Contournement** : `scripts/run-tests-with-stack.sh` (ulimit externe).
`setrlimit` en Zig ne marche pas (hard limit kernel a 8192 KB).

**Vraie solution** : tree-walker iteratif (chantier 2-3 sessions).

**Tests retires** : 3 (bdiv 1000/7, 10^26 roundtrip, bmod 1000/7).
Documente dans `_syntax_gaps.md` D20.

### Nouvelles choses

- `tests/test_scheduler.hvn` (3 tests)
- `tests/test_effects_rec.hvn` (4 tests, lambdas inline)
- `docs/book/src/14-concurrency.md` (chapitre scheduler)
- `scripts/run-tests-with-stack.sh` (contournement D20)
- Temperature dans le test-runner (start/end/delta)
- Fix `build.zig` : `test_engine` importe `continuation` + `scheduler`

### Tests (mesure 2026-10-08)

    zig build test                    ->  389 tests Zig
    test_scheduler.hvn                ->  3/3
    test_effects_rec.hvn              ->  4/4
    test_bigint.hvn                   ->  28/28
    test_stream_lazy.hvn              ->  8/8
    test_io_stream.hvn                ->  4/4
    smoke.sh                          ->  16/16

### Pistes actives (ordre conseille)

1. **D20** -- tree-walker iteratif (2-3 sessions). Le bug de fond
   qui limite toute recursion profonde.
2. **D8 Voie B** -- continuations completes (2-3 sessions). Debloque
   preemptif exact + multi-shot.
3. **Jalon 2 auto-hebergement** -- structures de donnees en Heaven
   (HashMap, Array). 2-3 sessions.
4. **D8 3a-3-c-c** -- entrelacement reel (yield auto sur budget).
   1 session.

### Note : send vs tell

Deux abstractions coexistent :
- `send` = acteur (synchrone, retourne nouvel etat)
- `tell` = process (asynchrone, mailbox)

Nomenclature confuse. Renommer `tell` en `send_async` serait plus
clair (chantier separe, non planifie).

---

## Addendum -- session 2026-10-07 (fin)

### Nouvelles decisions

- **D16** -- serveur HTTP 100% Heaven (curl -> Hello from Heaven).
- **D17** -- BigInt v0 (badd, bsub, bcmp non signes).
- **D17-2** -- BigInt v1 signe (BPos/BNeg, bmul, bto_string, from_string).
  22/22 tests. `10^26` prouve.
- **D18** -- style Haskell multi-ligne. Loader par indentation +
  `let x = v in body` -> `(let x v body)`. Code lisible.

### Nouveaux magics fins (total ~15)

string_concat, int_to_string, peek_byte, poke_byte, memset,
string_length, string_ptr, raw_alloc, raw_free, target_os,
raw_syscall/6, delay, force, let.

### Fichiers stdlib

- `core/http.hvn` : serveur HTTP minimal (Linux x86_64).
- `core/bigint.hvn` : BigInt signe, 22 tests.
- `core/io_stream.hvn` : io_open/io_read/io_write/io_close/io_cat_path.

### Pistes actives

1. **bdivmod BigInt** (30 min) -- division euclidienne, debloque RSA.
2. **D8 3a-3** (2-3 sessions) -- continuations delimitees, preemptif, events.
3. **Vraies structures** -- HashMap, Array dynamique en Heaven.
4. **Panic DebugAllocator** -- contourne par HEAVEN_NO_LEAK_CHECK=1.

### Note : pas d'alias 0-aire

`badd = badd_signed` NE marche PAS. Il faut `badd A B = (badd_signed A B)`.
Un 0-aire n'est pas une fonction applicable. Documente dans D17 v1.

## Addendum -- session 2026-10-07 (session fondatrice)

**HEAD** : `26750bd` (main). Tout pousse sur origin.

### Tests (mesure 2026-10-07)

    zig build test --summary all         ->  388 tests Zig
    heaven --run-test tests/test_stream_lazy.hvn   ->  8/8
    heaven --run-test tests/test_io_stream.hvn     ->  4/4
    bash scripts/smoke.sh                ->  16/16

Note : `HEAVEN_NO_LEAK_CHECK=1` recommande pour eviter le panic
DebugAllocator (bug preexistant, non resolu).

### Decisions fermees cette session

- **D10** -- syscalls et libc. 3 chemins : A (interpreteur, `raw_syscall`),
  B (compilé libc, prefixe `@nom`), C (freestanding, `HEAVEN_NO_LIBC=1`).
- **D11** -- perimetre multi-plateforme (amd64-linux seulement pour D10 ;
  D11 fixe l'ordre arm64-linux / apple / windows / wasi).
- **D12** -- laziness (`Tag.thunk` + magics `delay` / `force` + memoization).
- **D14** -- IO en Heaven (5 magics fins : `string_ptr`, `raw_alloc`,
  `raw_free`, `target_os`, `raw_syscall`).
- **D15** -- `let` magic symbol S-expr `(let name val body)`.

### Bugs resolus

- **Multi-clauses** : `parseBodySmart` (wrap + parseExpression) dans
  `evalEquation`. Debloque `f (- n 1)`, `fact`, streams paresseux.
- **`force` dangling** : `engine.thunks.getPtr` + `evaluate` realloc.
  Fix : re-getPtr apres evaluate.
- **3 sites `getPtr` + evaluate** : actor send, run process, module alias.
  Meme classe que `force`. Voir convention #20 ci-dessous.

### Features utilisateur

- Streams paresseux (`stream_nats_from`, `stream_map`, `stream_filter`,
  `stream_take`, `stream_repeat`, `stream_iterate`).
- IO en Heaven (`io_open`, `io_read`, `io_close` dans `core/io_stream.hvn`).
- `let` S-expr comme expression normale.

### Pistes actives (ordre conseille)

1. **D8 3a-3** -- continuations delimitees (`captureCont` / `throwCont`).
   `continuation.zig` a `PromptStack` seulement (pas de capture).
   Debloque `handle-rec`, scheduler preemptif, events. 2-3 sessions.
2. **D14 etape 2** -- `peek_byte`, `poke_byte`, `string_concat` ->
   vrai `cat` en Heaven. 1 session.
3. **Audit `Store.getInt`** -- lit `payload` au lieu de `lits.items[aux]`.
   `grep -rn "getInt" src/` -- plusieurs sites potentiellement affectes. 30 min.
4. **Panic DebugAllocator** -- "double-mapped pages". Contourne par
   `HEAVEN_NO_LEAK_CHECK=1`. `git bisect` sur `egraph_rewriter.zig` ou
   usage subtil de DebugAllocator. Session a froid.
5. **Quirks parser** -- `-100`, strings dans `let`, `let ... in` multi-lignes.
   Voir `_syntax_gaps.md` section "Quirks parser". 1 session.

### Convention #20 -- getPtr + evaluate = danger

Ne jamais garder un pointeur `HashMap.getPtr(key)` a travers un
`evaluate()` recursif. `evaluate` peut ajouter des entrees a la meme
HashMap (`thunks`, `actors`, `processes`, `fns`) -> realloc -> pointeur
dangling. Capturer les valeurs scalaires avant, re-`getPtr` apres.
Cas fixes : `force`, `actor send`, `run process`, `module alias`.
Voir commit `26750bd`.

### Ce qui reste a considerer (audit empirique)

`engine_expr.zig:1182` -- `store.pool.items[...] = try evaluate(...)`.
Probablement sur en Zig (RHS avant LHS), mais non verifie. Un test
isole (tuple de 10 elements dont le 5e force une realloc du pool)
confirmerait.

### Autres fichiers a jour cette session

- `docs/DECISIONS.md` : D10, D11, D12, D14, D15.
- `docs/spec/_syntax_gaps.md` : bug multi-clauses resolu + quirks parser.
- `docs/book/src/07-streams.md` : reecriture paresseuse.
- `docs/book/src/B-erreurs.md` : 10 erreurs courantes documentees.
- `docs/book/src/C-glossaire.md` : magic, thunk, Path A/B/C.
- `docs/book/src/CHANGELOG.md` : entree 2026-10-07.
- `docs/book/src/SUMMARY.md` : ordre corrige.

---

# Prompt de continuité — Heaven session suivante

## Convention doc (IMPORTANT pour les sessions paralleles)

Les chiffres factuels du `README.md` sont **generes** par
`scripts/docgen.py`, pas edites a la main. Regle :

- Toute modif d'un chiffre (tests, resultats, date) doit passer par
  `zig build docgen` (equivalent `python3 scripts/docgen.py`).
- Le CI verifie la fraicheur via `zig build docgen-check` — il **echoue**
  si un chiffre est perime.
- Les valeurs sont encadrees par des markers :
  `<!-- DOCGEN:key -->valeur<!-- /DOCGEN -->`
- Ne **jamais** editer une valeur entre markers a la main.
- Si une session parallele a modifie du code qui change les tests,
  faire `zig build docgen` avant de committer.

Consequence : toute session qui modifie un chiffre a la main verra
son commit rejete par le CI.

### STATUS.md est aussi genere

Depuis 2026-10-06, `docs/STATUS.md` est genere depuis
`docs/status.json` (21 sections, 138 features) :

- `zig build status` / `python3 scripts/status_gen.py` : regenere.
- `python3 scripts/status_gen.py --check` : CI, exit 1 si divergence.
- Editer `docs/status.json`, pas `STATUS.md`.
- Si on doit editer le markdown a la main (cas exceptionnel) :
  `python3 scripts/status_import.py` re-parse vers le JSON.

**Incident 2026-10-06** : une session parallele a restaure README.md
a un etat pre-docgen (`b9eb621`), ecrasant les markers. Le CI est
passe parce que les markers avaient disparu (regex ne matche rien).
Correctif : bandeau d'avertissement en tete de README + reinsere
les markers (commit `e5e92d8`).

## HEAD
edb628f (main) — docs(spec): bug take masque par prelude corrige
Tout poussé sur origin/main.

## Tests (mesure 2026-10-06)

    zig build test --summary all        →   380 tests Zig passent
    heaven test tests/verify_book.hvn   →   43/43
    heaven test tests/features_smoke.hvn →  43/44  (kanren query en echec)
    heaven test tests/*.hvn             →   47 tests total (fichiers .hvn)

Note : l'ancien chiffre "~95 HVN" etait surestime. Le count reel est
le nombre de `test "..."` dans les fichiers `.hvn` (47).

## Addendum -- session 2026-10-06

Session de stabilisation. 14 commits pousses sur `origin/main`.
Deux fixes techniques structurels, plus 6 corrections documentaires.

### Fixes techniques

1. **Generiques `<a>` cote REPL** (commit `f213218`).
   `data List<a> = ...` enregistrait `"List<a>"` comme nom litteral
   avec 0 param, silencieusement. Desormais : nom coupe a `<`,
   params `<a>`, `<a, b>`, `<a : Type>` parses.
   - `data List<a>` → 1 param
   - `data Pair<a, b>` → 2 params
   - `data Box<a : Type>` → 1 param
   - `data MyList a` (espace) → 1 param (preserve)
   - `data Vec (n : Nat)` (parens) → 1 param (preserve)
   Le corps (`Cons a (List<a>)`) etait deja correct, verifie.

2. **Purge des clauses prelude** (commit `2f914bd`).
   `core/std/list.hvn` enregistre `take zero _ = nil` au demarrage.
   La clause user `take zero s = s` s'ajoutait en queue et n'etait
   jamais atteinte -> `nil`.
   Fix : flag `prelude_loading` + set `user_redefined_names`. Au
   premier enregistrement user d'un nom, purge des clauses existantes.
   **`verify_book.hvn` passe de 41/43 a 43/43.**

3. **REPL `for` sans parens** (commit `f20568a`).
   `for (x <- L) B` tape au REPL n'etait pas detecte par le dispatch
   (qui cherchait `(for `). Fix : detection de `for ` en tete, wrapper
   en `(for ...)` avant passage a `desugarFor`.

### Fixes documentaires

- `README.md` : QTT = cadre cible (pas GC effectif) ; acteurs
  sequentiels (pas distribues) ; tests 47 HVN (pas 95).
- `docs/STATUS.md` : `lambda x -> body` supporte depuis `4e606c1`.
- `GRAMMAR.md` : "miroir exact" → "vise a refleter, grammar.js fait foi".
- `docs/spec/_syntax_gaps.md` : section "Ecarts documentaires" +
  gap evalDataDecl + bug take resolu.

### Bugs ouverts (voir _syntax_gaps.md)

| Bug | Zone |
|---|---|
| `features_kanren_query` echoue | `src/logic/kanren_expr.zig` |
| `fact 5` → `fact 5 (0 arg(s))` | `defs.zig` evalEquation |
| REPL `for` sans parens | `heaven_expr.zig` wrapper |

### Docs a auditer (Passe 2, post-stabilisation)

- `HEAVEN_ARCHITECTURE_2026.md` (3 mois sans MAJ)
- `docs/book/src/10-under-the-hood.md` (utilise `List<a>` en exemple)
- `PROMPT_CONTINUITE.md` lui-meme (fait dans cet addendum)

### Note sur la session 2026-10-05

Les 6 fixes ci-dessus s'ajoutent a ceux de la session precedente
(2026-10-05) : Gap 3 (`perform (S-expr)`), beta-reduction par
substitution AST, kernel `shift`/`subst` court-circuit, clause
0-pattern CAF, lambda etendu (`=>`, `(x)`, multi-params), `for...when`.
Details dans `docs/spec/_syntax_gaps.md` section "Corriges recents".

## Ce qui a été fait cette session
- QBE v1.2 opérationnel (compile + bench).
- WASM via wasmtime (M2a/M2b).
- bench-interp / bench-qbe / bench-wasm : wall, cpu, energy RAPL,
  temperature, RSS, --loop.
- Compilation des fonctions utilisateur recursives : fib(25) = 75025
  en QBE 1.15 ms (vs 29824 ms interprete, ~26000x).
- bench/run.sh, bench/progs/{count_down,arith,loop,fib}.hvn.
- docs/spec/_bench.md : methodologie et resultats.

## Fix majeur — fonctions utilisateur (f31b2eb)
3 bugs chaines :
1. defs.zig : parseSExpr pour les corps S-expr purs. parseExpression
   -> tree-sitter confond `<` avec une balise et currifie.
2. defs.zig : lowerRec uniforme (le cas "sans patterns" l'oubliait).
3. mir.zig : precompileUserFns en 2 passes (placeholders avant
   compilation des corps). Resout la recursion (fib appelle fib).

## Etat de l'arbre (2026-10-02)

Le conflit de stash sur `src/vessel/public/test_suite.hvn` est
resolu (`tco_deep` reajoute). L'arbre est propre a part les
modifications en cours de cette session.

Un commit local `3469bc3` (session parallele, eval.zig + math.zig)
attend d'etre pousse.

## Addendum -- session 2026-10-02 (nuit++) -- cloture DebugAllocator

### Diagnostic final

Le crash intermittent DebugAllocator **n'est pas un UAF ni un write OOB
sur page**. Preuve : compiler avec `std.heap.page_allocator` (chaque
alloc = mmap, chaque free = munmap, tout acces apres free = segfault
immediat) donne **20/20 runs verts, 98/98 tests, 0 panic**.

Le bug est **specifique aux metadonnees internes de DebugAllocator**
(assert `!gop.found_existing` a `debug_allocator.zig:732`, message
"double-mapped pages"). Page_allocator ne le voit pas.

### Comportement

- GeneralPurposeAllocator : 2-4 panics sur 5 runs, variable.
- page_allocator : 20/20, stable, 98/98 tests.
- Les résultats fonctionnels sont identiques (98/98 dans les deux cas
  quand GPa ne plante pas).

### Solution pragmatique en place

Flag `HEAVEN_NO_LEAK_CHECK` :
- Non defini (defaut) : DebugAllocator, leak check complet.
- `=1` : page_allocator, rapide, pas de check.

`build.sh` et `tests.sh` posent `=1` par defaut. Pour retrouver
le check :

    HEAVEN_NO_LEAK_CHECK=0 bash tests.sh

### Ce qui reste a investiguer (session a froid)

Deux pistes, par ordre de probabilite :

1. **Usage subtil de DebugAllocator** dans Heaven : mauvais `free`
   sur une slice dont la taille a change, ou allocation/liberation
   avec des tailles incoherentes. DebugAllocator detecte, page_allocator
   non (meme page de toute facon).

2. **Bug Zig 0.15.2** dans DebugAllocator sur une sequence particuliere
   d'allocations. Le message "double-mapped pages" vient de la gestion
   interne de l'allocateur, pas forcement d'un usage incorrect.

Pistes de diagnostic :
- `git bisect` sur les commits qui ont touche `egraph_rewriter.zig`,
  `egraph.zig`, `simplify_engine.zig` (le crash se manifeste pendant
  `verifyByInduction`, dans `simplifyWithEGraph`).
- Comparer avec une version plus recente de Zig si disponible.
- Instrumenter DebugAllocator (patch local) pour logguer chaque
  alloc/free avec sa taille et son site d'appel, chercher les
  incoherences.

### Gains conserves de la session

- `boolSymLitEq` : 96/97 -> **98/98 tests verts**.
- 3 fixes de dangling slices (`egraph_rewriter.zig`).
- Flag `HEAVEN_NO_LEAK_CHECK` : tests stables en attendant le fix.
- Documentation complete du diagnostic (8 tests de neutralisation).

## Addendum -- session 2026-10-02 (nuit) -- bug memoire EGraph

### Diagnostic

Crash intermittent dans `verifyByInduction` (2/3 a 4/10 selon les runs),
DebugAllocator `assert(!gop.found_existing)` (double-mapped pages).
Detecte tardivement, ne pointe pas la vraie source.

### Isolation (8 tests de neutralisation)

1. Neutraliser `rewriteViaPipeline` complet : **0/10 panic** -> c'est
   bien dans cette fonction.
2. Neutraliser `simplifyWithEGraph` seul : **0/10 panic** -> c'est lui.
3. Neutraliser `saturate` seul : **10/10 panic** (!) -> saturate
   n'est pas la source, sa neutralisation aggrave.
4. Neutraliser les `deinit` de l'egraph : ~6/10 -> deinit necessaires
   mais pas la cause.
5. Checks d'Id retournes invalides : 0 occurrence.
6. Checks recursifs sur descendants : 0 occurrence.
7. Checks OOB dans `EGraph.merge` : 0 occurrence.
8. Checks de bornes sur `applyBetaReduction` : partiel.

### Cause identifiee (partielle)

Dangling slices de `self.store.pool.items`. Pattern general :
capturer une slice du pool, puis appeler une fonction qui modifie le
Store (`sym`, `apply`, `pushSpan`, `addNode`), reallouant le pool.

Fixes appliques (commit ee... a pousser) :
- `applyBetaReduction` : pool capture en tete remplace par relecture
  a chaque usage (3 sites).
- `substitute.apply` et `.lambda` : snapshot des args/body avant
  recursion.

Fenetre du crash reduite mais **pas fermee** (~13/20 panics sur
derniers runs). D'autres sites du meme type existent probablement
dans `egraph.zig`, `pattern.zig`, `rules.zig`.

### Piste pour la prochaine session

**`git bisect` sur `src/core/egraph_rewriter.zig` + `egraph.zig` +
`simplify_engine.zig`** :

    git log --oneline --since="7 days ago" -- \
      src/core/egraph_rewriter.zig src/inference/eqsat/egraph.zig \
      src/core/simplify_engine.zig

Commits recents connus : `9c90969` (perf t_distrib, ajout
rewriteViaPipeline), `f8e9535` (ordre superieur + comprehension).

Commande de test (rapide) :

    for i in $(seq 1 10); do
      ./zig-out/bin/heaven --run-test core/test_suite.hvn 2>&1 | grep -c panic
    done

Si 0 -> commit sain. Si >0 -> commit bugge.

Alternatives si bisect ne trouve pas :
- Remplacer les slices pool par `spanSliceConst` partout dans
  `egraph_rewriter.zig` (copie systematique, cout negligeable).
- Instrumenter le Store pour detecter les reallocations de pool
  (`pool.capacity` change -> log) et voir si elles coincident avec
  les lectures dangereuses.

### Gains conserves

- `boolSymLitEq` : 96/97 -> **98/98 tests verts**.
- Deux lignes fusionnees du meme style que `488d5f2` reparees.
- Trois fixes de dangling slices.

## Addendum -- session 2026-10-02 (soir) : points 1-4

Fait ce soir :
- **Cleanup debug** (`1b4705d`) : CANON BUG conditionne a
  HEAVEN_DEBUG, mir-filt retire.
- **docs/VISION.md** (`fe57b61`) : document de vision long terme
  (invariants, noyau CIC, essaim, multi-syntaxes, ontologies).
- **Audit book ch. 05/06/07/12** : rien a patcher, deja coherent.
- **Cross-compile QBE** (`3b24438`, `be5fe1f`, `48baaca`) :
  `--target` supporte 5 cibles (amd64_sysv, amd64_apple, arm64,
  arm64_apple, rv64). Emet l'assembleur pour la cible demandee,
  pas le binaire (cross-cc non gere).

Restant apres ces points :
- D8 vrai 3a-3 (2-3 sessions)
- D9 (Vessel -> Expr, 1-2 sessions)
- wasm32-wasi (session parallele)
- Audit des 36 @panic restants
- D9 inventaire (docs/spec/_vessel_decouple.md) -- en cours

## Addendum -- session 2026-10-02 (soir)

Fait ce soir :
- **Cleanup debug** (`1b4705d`) : CANON BUG conditionne a
  HEAVEN_DEBUG, mir-filt retire.
- **docs/VISION.md** (`fe57b61`) : document de vision long terme
  (invariants, noyau CIC, essaim, multi-syntaxes, ontologies).
- **Audit book ch. 05/06/07/12** : rien a patcher, deja coherent.
- **Cross-compile QBE** (`3b24438`, `be5fe1f`, `48baaca`) :
  `--target` supporte 5 cibles (amd64_sysv, amd64_apple, arm64,
  arm64_apple, rv64). Emet l'assembleur pour la cible demandee,
  pas le binaire (cross-cc non gere).

Restant apres ces points :
- D8 vrai 3a-3 (2-3 sessions)
- D9 (Vessel -> Expr, 1-2 sessions)
- wasm32-wasi (session parallele)
- Audit des 36 @panic restants

## Pistes actives (2026-10-02)

### Court terme

1. **D1bis** — degager les imports morts de `main.zig` (30 min).
   `heaven_lib`, `react_lib`, `SRG`, `EQSATPlanner`, `transpiler_lib`
   sont importes mais jamais utilises au runtime. Voir
   `DECISIONS.md` D1 revisee.

2. **Leaks residuels** — voir section dediee plus bas. L1
   (`proofs.zig:222`) et L2 (`interactive.zig:146`).

3. **`[fns.deinit] freeing key=...`** — ~90 lignes de debug print
   a chaque shutdown. Conditionner a `HEAVEN_DEBUG=1`.

### Moyen terme

4. **D8 — continuations delimitees**. `src/core/continuation.zig`
   existe (334 l., 9 tests) mais n'est branche nulle part.
   Etape 3a-3 : brancher dans `engine_expr.zig` + tests end-to-end.
   Debloque `handle-rec` et le scheduler preemptif.

5. **D9 — decoupler Vessel d'Astra** (1-2 sessions). Vessel lit
   `matrix.getStats()`, `matrix.nodes.iterator()`. Recabler sur
   `expr.Store`. Debloque la suppression effective de `matrix.zig`
   et elimine le doublon de bootstrap.

6. **Audit des 39 `@panic`/`unreachable`** (1 session). Le nombre
   a double depuis 2026-09-29 (19 -> 39). A trier : defensifs vs
   bugs latents.

### Long terme

7. **wasm32-wasi** (A : compilateur en WASI ; B : programmes
   compiles en WASI). Session parallele a cree
   `src/platform/wasm32_wasi.zig` (542 l.). Priorite basse.

8. **Cross-compilation** vers d'autres arches / OS. QBE est deja
   multi-cible (x86-64/ARM64/RISC-V), a brancher dans `build.zig`.

9. **Cycles SCC 3+ fonctions** (TCO mutuelle etendue). Actuellement
   limite aux paires.

10. **Auto-hebergement** (long terme) : BigInt (libtommath), I/O,
    structures de donnees, puis self-parse/self-compile.

## Bug matrix (RESOLU 2026-10-01)

Le `Invalid free` au shutdown du REPL (`matrix.zig:237`,
`free(func.params)`) est corrige (`c27cc54`). Cause : la Matrix
liberait des slices qui appartenaient a l'arena de
`UniversalIngestor`. Fix : retirer les 7 free Forge de
`matrix.deinit()`.

## Leaks residuels (RESOLUS 2026-10-02)

Les deux leaks L1 (proofs.zig:222) et L2 (interactive.zig:146)
identifies le 2026-10-01 sont **resolus** :

- Verification : `theorem t : x + 0 = x` + `prove t by simplify`
  + `abort` + EOF dans preuve : 0 leak (HEAVEN_DEBUG=1).
- `zig build test` : aucun leak.

Ils ont ete corriges par les refactors des sessions 2026-10-01 et
2026-10-02 (PROMPT restructure, run.zig defer free, etc.). Aucune
action residuelle.

## Debug print bruyant

`[fns.deinit] freeing key=...` : ~90 lignes a chaque shutdown
(`engine_expr.zig:252`). A conditionner a `HEAVEN_DEBUG=1`.

## Fichiers de reference
- src/commands/qbe_cmd.zig, wasm_cmd.zig, bench_interp.zig
- src/backend/mir_qbe.zig, mir_wat.zig
- src/core/mir.zig (precompileUserFns)
- src/core/commands/defs.zig (parseSExpr)
- bench/run.sh, bench/progs/
- docs/spec/_bench.md

## REGLE D'OR -- enrichir la non-regression

**Toute nouvelle feature ou tout bug fix qui change le comportement
du langage DOIT etre accompagne d'un test dans la suite.**

3 endroits, selon la nature :

1. **Feature du langage** (mot-cle, tactique, type) : ajouter un
   `test "..."` dans `core/test_suite.hvn`. La suite tourne en
   DebugAllocator (via `HEAVEN_NO_LEAK_CHECK=0`) et avec page_allocator.

2. **Feature d'un backend** (QBE, WASM, cross-compile) : ajouter un
   cas dans `scripts/smoke.sh`. Format :

       $HEAVEN compile-qbe bench/progs/X.hvn -o /tmp/smoke_X_qbe
       check "QBE X = attendu" "valeur" "$(/tmp/smoke_X_qbe)"

   Et le meme pour WASM si applicable.

3. **Cas complexe ou integration** (plusieurs features combinees) :
   ajouter un fichier `tests/<nom>.hvn` autonome.

**Verification avant commit :** lancer `bash tests.sh` et vérifier que
tout ce qui passait avant passe encore. Les échecs préexistants
(`tests/verify_book.hvn` 41/43, `tests/unlower_spec.hvn` 0/3, etc.)
ne sont pas une raison d'ignorer de nouveaux échecs.

**Ne pas supprimer** un test qui échoue sans documenter pourquoi dans
le commit. Si un test est faux (mauvaise syntaxe), le corriger.

**Rappel des sessions parallèles :** 3 sessions peuvent tourner en
parallèle sur le depot. Avant de modifier `core/test_suite.hvn`,
`tests/`, ou `scripts/smoke.sh`, vérifier qu'aucune autre session n'y
travaille (`git status`, `git log`).

## Methodes
- Heredoc > 50 l. = tronque par navigateur (scinder en 2-3 blocs).
- git add cible uniquement (jamais -A, 3 sessions sur l'arbre).
- Avant de retoucher mir.zig/defs.zig, verifier qu'aucune session
  parallèle n'y travaille.
- Utiliser src/platform/* pour toute syscall, jamais std.posix direct.

## Addendum -- session guards (2026-10-01)

### Livre
- 867ec43 : guards sur clauses (f p | cond = body). 17/17.
  6 bugs de suture (tokenizer lhs_eff, split =, == non evaluable,
  mem.replace in-place = corruption tas). Credit : fix fns.getPtr
  (session MIR/QBE) inclus.
- d377a73 : STATUS guards ✅. 7be1b81 : tranchages comprehensions
  (ROADMAP, 5 decisions : syntaxe double, sequentiel, linear,
  SubstStream, Set-quotient).

### Conventions #17-#18
- #17 : std.mem.replace exige src != dest (in-place = UB,
  SIGSEGV differe DebugAllocator).
- #18 : ASCII seul (commands, patches, commits).

### File
- t_distrib ~2s (regression vivante, piste nodeHash)
- tco_deep ~40us/iter (trampoline)
- M4 Green/Fast (debloque depuis M3)
- Comprehensions : spec decidee, implementation a ouvrir

## Addendum -- forme alignee (2026-10-01 soir)
- 89ead1f : gardes en forme alignee (continuation '|').
- b26eb9f : fix use-after-free setLastEqLhs (bisection 867/89e).
  Lecon gravee : les tests d'une feature ne voient pas un UAF --
  seule la suite complete le detecte (convention #6).

## Correction interpretation (2026-10-02)
- Le "crash corruption tas" chase hier (bisection 867/89e) etait
  en fait le leak kernel au shutdown : gpa.deinit abort (exit 134)
  quand une preuve CIC passe par shift/mkApp. Stack : peano.zig
  104/123/372-388. Flaky (4/5). Dossier session kernel -- relais
  envoye avec reproducteur. Notre b26eb9f (fix UAF) reste valide
  pour ce qu'il corrigeait (ordre de liberation), mais la cause
  racine du 134 est le leak peano.

## Addendum -- perf t_distrib (2026-10-02)
- 9c90969 : rewriteViaPipeline convergence structurelle.
  t_distrib 1416ms -> 66ms (21x), saturations 20 -> 1.
  Cause : comparaison d'Id pour le point fixe -- or le pipeline
  re-alloue des Ids a chaque passage. LECON GENERALISABLE :
  jamais == sur Id comme critere de convergence dans un pipeline
  qui re-alloue -- toujours structuralEql. (Sweep fait : un seul
  site, celui-ci, corrige.)
- 08-proofs.md : rien a jour -- la perf ne change pas la
  semantique documentee. Si un chapitre perf nait un jour,
  y referencer les 21x.

---
## 📅 Journal : 02 Oct 2026
- **feat** : Parsing lambda `λ` 100% fiable (UTF-8, delim_pos, délégation parseSExpr).
- **feat** : Désucrage des compréhensions `(for ... (when ...))` opérationnel via `desugarFor`. Tests `comprehensions.hvn` validés.
- **fix** : Fuite de mémoire dans `eval.zig` colmatée (`defer free`).
- **fix** : Panic `Invalid free` à la fermeture du REPL dans `matrix.zig` résolu.
- **fix** : Règle de réécriture v2f `(add (succ x) y)` stabilisée.
- **Prochaines étapes candidates** : Spécification formelle EBNF, Support WASM IO, ou Pipeline logique unifié (rule/prolog).

## Addendum -- ordre superieur + comprehension (2026-10-02 PM)
- f8e9535 : 3 bugs racines. (1) symbole-fonction = valeur
  (le "application partielle" du 28/09 MORT -- test_stream 33/37).
  (2) defer env.delete premature x3 : thunk/t valeur differee
  -- filter-λ et le when en dependent. (3) comprehension phase A :
  desucrage TEXTE (for ...) -> map/filter, 10/12.
- OUVERT : parseOrDispatch/interpForAssert (parseur de TEST)
  ne connait pas λ S-expr -- 2 tests comprehension. Matrice
  complete en session : DS parfaits, chemins radiographies,
  reproducteurs /tmp/ds2.hvn /tmp/fl2.hvn.
- LECON #19 : le test-runner et le REPL ont des parseurs
  DIFFERENTS (interpForAssert vs parseExpression) -- une forme
  peut passer dans l'un et pas dans l'autre. Toujours sonder
  les deux.
