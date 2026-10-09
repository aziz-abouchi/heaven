# Décisions d'architecture Heaven

Document de référence pour les choix structurants.
Chaque décision est ancrée sur un constat de code (chiffres,
chemins, lignes). Une décision non appliquée reste **proposée**.

Dernière mise à jour : 2026-10-02.

## Contexte chiffré

Chiffres vérifiés le 2026-10-02 :

- **59 250 lignes de Zig** dans `src/` (**206 fichiers**)
- **18 TODO/FIXME**, **39 `@panic`/`unreachable`** (les `@panic` ont
  doublé depuis le 2026-09-29, à auditer)

Évolution depuis le 2026-09-29 :
- Fichiers : ~180 → 206
- Lignes : 54 258 → 59 250
- TODO/FIXME : 21 → 18
- @panic/unreachable : 19 → 39 (doublement à investiguer)

## D1 — Faire le deuil d'Astra (RÉVISÉE 2026-10-02)

**Constat après audit** : la version du 2026-09-29 supposait que
*les 20k lignes Astra étaient dormantes*. C'est **faux**. Audit du
2026-10-02 :

- **`matrix_lib`, `autofab_lib`, `vessel_lib`, `universal_lib`
  sont VIVANTS** : ils portent l'IDE web Vessel (dashboard, REPL
  web, visualisateur eGraph, process monitor). `vessel/bridge.zig`
  lit `matrix.getStats()`, `matrix.nodes.iterator()`, appelle
  `syncMatrixWithFile(matrix, fab, ...)`. `uni_ingest.ingest()`
  peuple la matrix à partir des `.hvn` (bootstrap, kernel, logic,
  prelude, io).

- **`transpiler_lib` est MORT** : 1 seule occurrence dans
  `main.zig` (l'import lui-meme). Retire le 2026-10-02.

- **`heaven_lib`, `react_lib`, `SRG`, `EQSATPlanner` sont VIVANTS**.
  Correction 2026-10-02 apres verification transitive :
  `heaven_engine` est passe a `shell_lib.Shell.init` (REPL) et a
  `loop.runLoop` qui appelle `engine.pulse` en boucle et
  `engine.srg.select`. `react_lib.ReactionEngine` est utilise dans
  le thread reseau `net_thread`. L'audit initial (grep local sur
  `main.zig`) avait conclu a tort qu'ils etaient morts.

**Décision révisée :**

- **Ne pas déplacer** `matrix.zig`, `matrix_bridge.zig`,
  `vessel/*`, `runtime/autofab.zig`, `inference/forge/universal.zig`,
  `runtime/shell/*` : ils portent Vessel.
- **Dégager** de `main.zig` les imports et blocs morts.
  Au 2026-10-02 : seul `transpiler_lib` (retire). Les 4 autres
  sont vivants et restent.
- **Découpler Vessel** du noyau Expr (recâbler le dashboard sur
  `expr.Store` au lieu de `matrix`) est le **vrai** chantier pour
  faire tomber Astra. Voir D9. Effort 1-2 sessions, pas 30 min
  comme annonce initialement pour D1bis.

**Note importante** : il y a un **doublon de bootstrap**. Les
5 fichiers `.hvn` sont chargés deux fois : une fois par
`uni_ingest.ingest()` dans la matrix (pour Vessel), une fois par
`heaven_expr.zig:347` + `std_loader.zig` (pour le REPL).
Tant que Vessel dépend de matrix, ce doublon reste.

**Effort** : 30 min pour le nettoyage des imports morts.

**Critère** : `zig build` vert, `zig build test` vert,
`./zig-out/bin/heaven repl` fonctionne, Vessel démarre
(`http://localhost:port/`) et affiche la matrix peuplée.

## D9 — Découpler Vessel du noyau Astra (NOUVELLE 2026-10-02)

**Constat** : Vessel (`vessel/bridge.zig`) lit directement
`matrix` (getStats, nodes.iterator, syncMatrixWithFile). C'est
le dernier point de couplage fort entre l'ancien écosystème
Astra et l'environnement utilisateur (IDE web).

**Action** : recâbler les endpoints de Vessel pour qu'ils
lisent le `expr.Store` au lieu de `matrix`. Nécessite :
- Un équivalent `getStats()` sur le Store (nb de nœuds, symboles).
- Un équivalent `nodes.iterator()` exposant les nœuds du Store.
- Un endpoint `syncWithFile` qui passe par `heaven_expr` au lieu
  de `syncMatrixWithFile`.

**Effort** : 1-2 sessions. Risque moyen (Vessel est l'environnement
principal, ne pas casser).

**Débloque** : la suppression effective de `matrix.zig` (D1
complète), et supprime le doublon de bootstrap.

## D2 — Moteurs logiques (FERMÉE 2026-09-28, doc + rename)

**Constat après audit** : 3 moteurs aux paradigmes **différents** :
- `core/kanren_expr.zig` (188 l.) : miniKanren Store-based
- `logic/kanren.zig` (969 l.) : miniKanren Term-based
- `runtime/prolog.zig` (308 l.) : Prolog SLD

**Pas de duplication sémantique.** Ce ne sont pas trois fois la
même chose, mais trois approches pour trois contextes différents.

**Problème réel** : dans `build.zig`, deux modules distincts sont
exposés sous le même nom `"kanren"` (ambiguïté silencieuse).

**Action** :
- Documentation : `docs/spec/_logic.md`
- Rename : `kanren_expr_mod` exposé comme `"kanren_expr"` (au lieu
  de `"kanren"`), `heaven_expr.zig` mis à jour.

**Effort** : 30 min. Aucun refactor de fusion justifié.

## D3 — Système de preuve (FERMÉE 2026-09-28, doc seule)

**Constat après audit** : il n'y a **pas de double CIC**. Trois
couches distinctes coexistent :

- **Frontend** (`elab.zig`, 1678 l.) : élabore `.hvn` → Core Store.
  N'utilise pas le kernel.
- **Store** (`proof.zig`, `proof_core.zig`, `proof_helpers.zig`,
  `proof_state.zig`) : orchestration des preuves au niveau Core.
- **Kernel** (`kernel/peano.zig`, 1966 l. au 2026-10-02 - a double depuis l'audit initial) : CIC minimaliste.
- **Pont** (`kernel_bridge.zig`, 143 l.) : traduit `Id` ↔ `u32`.

**Action** : documentation seule. Voir `docs/spec/_proof.md`.

**Effort** : 30 min. Aucun refactor justifié.

## D4 — Découper le shell (FAITE 2026-09-30)

**Constat initial** : `core/commands.zig` (2338 l.) +
`runtime/shell/commands.zig` (1604 l.) = 3942 lignes.

**État réel 2026-10-02** :
- `core/commands.zig` : **652 l.** (dispatch principal uniquement)
- `runtime/shell/commands.zig` : **1535 l.** (REPL interactif,
  pas le dispatch)
- `src/core/commands/` contient **8 sous-modules** : `cas.zig`,
  `defs.zig`, `dispatch.zig`, `format.zig`, `meta.zig`,
  `parse.zig`, `proofs.zig`, `runtime.zig`

Le découpage est fait. `core/commands.zig` est passé de 2338 à
652 lignes. Les sous-modules `logic.zig`, `modules.zig`,
`actors.zig` mentionnés dans le plan initial n'ont pas été créés
séparément - la logique correspondante vit dans `defs.zig`
(définitions, guards) et `dispatch.zig` (routage).

## D5 — Un seul `NodeKind` (RÉSOLU, faux problème)

**Constat vérifié 2026-09-28** : `NodeKind` est défini une seule
fois dans `platform/shell_parser_types.zig:55`. `parsing/shell_parser.zig:9`
et `core/bridge.zig:8` sont des **ré-exports** (`pub const NodeKind =
platform.shell_parser_types.NodeKind;`). `inference/forge/ts_normalize.zig:3`
a sa propre copie, mais c'est **légitime** (opère sur Tree-sitter brut,
pas sur la `Matrix` abstraite).

**Verdict** : rien à fusionner. D5 fermée sans action.

## D6 — Nettoyer `main.zig` (absorbée par D1bis 2026-10-02)

**Constat initial** : lignes 22-36 de `main.zig` importent 15
modules, dont plusieurs sans usage réel.

**État réel 2026-10-02** : après audit, la moitié sont vivants
(portent Vessel), l'autre moitié (`heaven_lib`, `react_lib`,
`SRG`, `EQSATPlanner`, `transpiler_lib`) est morte.

**Action** : voir D1bis (dans la D1 révisée). Effort : 30 min.
D6 fermée sans action séparée.

## D7 — Sérialisation canonique du Core (FAITE 2026-09-28)

**État réel 2026-10-02** : `src/core/serialize.zig` existe
(10 659 octets). API : `encode(store, writer)`, `decode(reader,
allocator)`. Format `HVN1` versionné (`MAGIC = "HVN1"`,
`VERSION = 1`). Refus explicite des versions inconnues.

**Ce qui est encodé** : nœuds du Store, pool d'arguments,
littéraux, interner de symboles.

**Ce qui reste à faire** (séparé, non planifié) :
- Test d'inverse explicite `decode(encode(e)) == e` avec
  α-équivalence sur plusieurs expressions Core.
- Intégration dans `core/network/*` (les TODO mentionnés dans
  la version initiale de cette décision).

**Débloque** : cache disque, communication entre process,
tests reproductibles, IPFS (si un jour).

## D8 — Continuations délimitées (Option B retenue, 2026-09-29)

**Constat** : `engine_expr.zig::evaluate` est un tree-walker récursif
direct. Chaque appel crée une frame native Zig. Impossible de
suspendre au milieu d'une expression. Bloque `handle-rec` et le
scheduler préemptif (C3 de `_concurrency.md`).

**Décision** : Option B — continuations délimitées style OCaml 5.
Primitives `pushPrompt`/`popPrompt`/`captureCont`/`throwCont`.
Tree-walker direct sauf aux frontières.

**Alternatives écartées** :
- A — CPS-transform intégral : 500-800 l., +10-20% perf, tous les
  call sites touchés. Trop intrusif.
- C — Coopératif strict : ne débloque rien au-delà du yield basique.

**Raisons** : effort/portée optimal (~200-300 l.), compatible avec
les magic symbols existants, approche mature (Dolan/Madhavapeddy),
débloque C3.

**Plan** : Prototype 3a en 3 sous-sessions — 3a-1 prompts (1 sess.),
3a-2 captureCont (1 sess.), 3a-3 branchement handle-rec + scheduler
(1 sess.). Détail dans `docs/spec/_continuations.md`.

**État réel 2026-10-02 (audite)** :
- 3a-1 FAIT : `src/core/continuation.zig` — `PromptStack`, push/pop/top
  avec tests.
- 3a-2 FAIT (modele symbolique) : `CaptureStack`, `Frame`, `captureCont`,
  `throwCont`. **Mais** la pile est une simulation avec des `Frame`
  opaques (`prompt: u32`, `position: u32`, `env: u64`). Aucun lien avec
  `engine_expr.evaluate`. Cette couche est prete a etre utilisee, pas
  branchee.
- **Safepoint cooperatif existe deja** (session parallele) :
  `engine.reductions`, `error.SuspendRequested`, `evalWithBudget(id,
  budget) -> EvalOutcome { done, suspended }`. Modele **redemarrable** :
  le caller relance avec un budget plus grand, pas de reprise exacte.
- **3a-3 A FAIRE**, et plus gros que prevu :
  1. Le safepoint actuel n'est pas une capture. Il sert au yield
     top-level (interrompre un calcul pur), pas a `handle-rec`.
  2. Pour `handle-rec`, il faut re-evaluer **le corps du handler**
     depuis un point precis apres le `perform` — donc :
     - restructurer `evaluate` pour que les corps de handler soient
       evaluables par morceaux, pas d'un bloc recursif.
     - lier `continuation.zig` (frame symbolique) a `evaluate`
       (positions et env reels).
     - gerer les allocations Store qui peuvent se decaler entre
       capture et reprise (les `Id` restent valides, le pool realloue).
  3. Sans cette refonte, `handle-rec` rejoue les side effects.

**Effort restant revise** : 2-3 sessions (pas 1-2).

**Non couvert volontairement** : le yield top-level marche deja
grace au safepoint + `evalWithBudget` (modele redemarrable). Le
scheduler preemptif C3 peut utiliser ce modele sans attendre 3a-3.

**Débloque** : handle-rec (reprise exacte), scheduler preemptif C3
peut avancer independamment.

**Débloque** : handle-rec, scheduler préemptif C3, puis C2 distribution.

## Roadmap courte (recalibrée 2026-10-02)

| # | Session | État |
|---|---|---|
| 1 | Fix `parseExpression` (infix parenthésé) | FAIT |
| 2 | D2 — unifier miniKanren (rename) | FAIT |
| 3 | D3 — clarifier CIC/elab/proof_core | FAIT (doc) |
| 4 | D4 — découper `commands.zig` | FAIT (652 l. restants) |
| 5 | D7 — sérialisation Core | FAIT (`serialize.zig`) |
| 6 | Scoped syntax `bracket`/`local`/`catch` | FAIT |
| 7 | TCO self-tail + mutuelle | FAIT (QBE + WASM) |

**Ce qui reste réellement :**

| # | Session | Effort | Débloque |
|---|---|---|---|
| 1 | D1bis — dégager imports morts de `main.zig` | 30 min | clarté |
| 2 | D8 — brancher `continuation.zig` (3a-3) | 1-2 sess. | handle-rec, scheduler |
| 3 | D9 — découpler Vessel d'Astra | 1-2 sess. | suppr. matrix.zig |
| 4 | Audit des 39 `@panic`/`unreachable` | 1 sess. | robustesse |

## Ce qu'on ne fera pas (vision, hors scope)

- IPFS / IPLD : présuppose sérialisation + réseau + swarm
- Swarm distribué (Fed-LBAP, MinCost, stragglers thermiques) : rien dans le code
- QTT avec budgets temps/énergie : la QTT actuelle est multiplicité
- Couplage thermique runtime : lecture température = 30 min Linux, mais
  corréler avec scheduler = projet
- Brain cognitif complet : `inference/neural/synthesis.zig` expérimental
- Auto-hébergement total : jalon, pas tâche

Ces sujets vivent dans `docs/VISION.md`, pas dans la roadmap.

## Règle de méthode

Avant toute décision structurante :
1. **Lire le code concerné** (pas de patch à l'aveugle)
2. **Vérifier les chiffres** (grep, wc, tests)
3. **Documenter le constat** (citations, chemins, lignes)
4. **Proposer l'action** avec effort et critère

Les rapports LLM (IPFS, λ_sc, ontologies) sont utiles pour la
direction mais doivent être **vérifiés ligne par ligne** avant
d'être planifiés. Plusieurs prêtaient au code des propriétés
qu'il n'a pas (sérialisable, distribué, typé).

## D10 — Appels système et libc (Option A+B+C, 2026-10-07)

**Constat** : les fichiers `examples/vision/platform/*.hvn` postulent
des features absentes : `inline_qbe`, `@syscall(...)`, `@extern("c", ...)`,
`ptr_of`. Aucune n'est dans le noyau 6 primitives ; QBE 1.2 n'a pas
d'inline asm. Pourtant la chaîne `Heaven → MIR → QBE → cc → libc` est
complète (le binaire `fib` importe `printf@GLIBC`).

**Décision** : trois mécanismes coopératifs, opt-in.

1. **Interpréteur (Path A)** — magic symbols `raw_syscall` (4 args) et
   `raw_syscall6` (7 args). Implémentés dans `engine_expr.zig::evalMagic`
   via `std.os.linux.syscall3` / `syscall6`. Retournent un `Int`.
   Invariant noyau respecté : ce sont des magics, comme `+`, `if`, `query`.

2. **Compilé, libc liée (Path B, défaut)** — préfixe `@nom` dans le
   source Heaven. Le symbole devient `Instr.extern_call` dans MIR, émis
   par QBE en `call $nom(...)`, résolu à l'édition de liens par libc.
   Exemple : `write fd buf len = @write fd buf len`.

3. **Compilé, freestanding (Path C, opt-in)** — variable d'environnement
   `HEAVEN_NO_LIBC=1`. Le link passe par `cc -nostdlib -nostartfiles
   -no-pie` avec :
   - `src/platform/stubs/start_amd64_linux.s` : `_start` custom qui
     appelle `main(argc, argv)`, puis `exit(code)` via syscall 60.
   - `src/platform/stubs/syscall_amd64_linux.s` : stub
     `heaven_syscall6(n, a1..a6)` (convention C).
   L'émission QBE bascule en mode minimal : pas de `printf`, pas de
   `data $fmt`, `ret` sans valeur dans `$main`.

**Alternatives écartées** :
- `inline_qbe "..."` : QBE 1.2 n'a pas d'inline asm ; forker
  `vendor/qbe-1.2/` demanderait un patch à maintenir à chaque bump.
- Nouvelle primitive dans le noyau 6 : casse l'invariant fondateur.
- `_start` fourni par libc (`crt1.o`) : lie implicitement libc.

**Débloque** :
- `examples/vision/platform/linux_x86_64.hvn` réécrit en syntaxe réelle
  (6 équations, compilable).
- Bootstrap : un binaire Heaven sans aucune dépendance dynamique.
- Base pour WASI (`fd_write` via imports, chemin séparé).

**Limites assumées** :
- Pas de types pointeur : les args sont des `Int` (suffisant pour
  l'expérimentation, pas pour une API sûre).
- Stubs amd64-linux uniquement (arm64 et darwin à faire).
- `linear` en argument (QTT) et `@if` (conditionnel de compilation)
  restent des chantiers séparés.
- Le codegen continue d'utiliser `printf` en mode libc. Les benchmarks
  et `bench-qbe` doivent rester en mode libc.

**Référence** : `docs/spec/_syscalls.md` (à créer, session suivante).

## D11 — Périmètre multi-plateforme de D10 (2026-10-07)

**Constat** : D10 valide trois chemins (magic `raw_syscall`, préfixe `@nom`,
mode `HEAVEN_NO_LIBC`) mais tous **amd64-linux uniquement**. Le backend
QBE sait déjà émettre pour 5 cibles (`amd64_sysv`, `amd64_apple`, `arm64`,
`arm64_apple`, `rv64`), mais les stubs syscall et les noms de symboles
libc sont spécifiques.

**Décision** : périmètre progressif, priorité décroissante :

1. **arm64-linux Path B** (libc identique à amd64-linux, doit marcher
   sans changement de code, juste un `cc` cross). 1 session de validation.
2. **arm64-linux Path C** (stubs `_start` + `heaven_syscall6` à écrire).
   1-2 sessions.
3. **amd64-apple / arm64-apple Path B** (préfixe `_` sur les symboles
   externes). ~2 h. Nécessite un `cc` cross ou une machine macOS.
4. **Windows** : chantier séparé, *pas* freestanding. `mmap` → `VirtualAlloc`,
   `write` → `WriteFile`, symboles dans `kernel32.dll` / `msvcrt.dll`.
   Spec : `docs/spec/_platform.md` familles `io`, `fs`, `mem`.
5. **WASI** : chemin entièrement différent (imports `fd_write`, etc.),
   pas de syscall natif. Chantier séparé, session parallèle identifiée.

**Non couvert** : aucun stub Windows freestanding (pas de syscall stable
NT). Aucun support macOS freestanding à court terme. Aucune cross-cc
automatisée dans `qbe_cmd.zig` pour l'instant.

**Débloque** : rien immédiat. Fixe le périmètre pour éviter qu'une
session parallèle ne réécrive les stubs en supposant une portabilité
qui n'existe pas.

**Note** : ceci est une décision de cadrage, pas un engagement de
livraison. Aucune de ces étapes n'est dans la roadmap courte.

## D12 — Laziness (v0, 2026-10-07)

**Constat** : `core/stream.hvn` est stable mais **strict** : chaque
étape (`map`, `filter`, `take`) matérialise toute la collection.
Impossible d'exprimer des pipelines infinis, des streams de taille
inconnue, ou l'IO en streaming. Le préalable est une notion de
*calcul différé* dans le noyau.

**Décision** : introduire un tag `Tag.thunk` (extension, **pas**
noyau — les 6 primitives restent 6) et deux magic symbols :

- `delay expr` : crée un `thunk` qui capture l'expression et
  un **snapshot de l'env** (`Env.clone`). Retourne l'Id du thunk
  sans évaluer.
- `force t` : si `t` est un thunk, évalue son expression dans l'env
  capturé, **mémoïse** le résultat dans `Engine.thunks[t].forced`,
  retourne la valeur. Idempotent.

`evaluate(.thunk)` retourne l'Id du thunk (non forcé) — un thunk est
une *valeur*, comme un `lambda`. Force est explicite.

**Représentation** :
- `Tag.thunk` dans `expr.zig` (extension, non-noyau).
- `Store.thunk(expr_id)` : constructeur.
- `Engine.thunks: AutoHashMapUnmanaged(Id, ThunkState)` avec
  `ThunkState { env: *Env, forced: ?Id }`.
- Cleanup dans `Engine.deinit` (les `Env` capturés sont libérés).

**Alternatives écartées** :
- Évaluation paresseuse par défaut (Haskell) : casserait tout le
  pipeline strict actuel (TCO, effets, QTT) et rendrait le
  debogage impossible.
- Tag dans le noyau (7e primitive) : casse l'invariant fondateur.
- Thunks sérialisables (`serialize.zig`) : chantier séparé,
  débloqué par D7 mais non requis pour les streams.

**Débloque** :
- Streams paresseux (`Cons x (delay rest)`).
- IO en streaming (`readChunk` → Stream paresseux).
- Base pour les events (multi-shot handler + boucle select).

**Limites assumées** :
- Pas de QTT sur les thunks (une valeur forcée plusieurs fois
  compte comme une seule occurrence).
- Pas de thunk dans le code compilé (`mir_qbe.zig`, `mir_wat.zig`) —
  c'est un mécanisme interpréteur uniquement pour l'instant.
- Le REPL top-level n'évalue pas `(let t (delay X) ...)` : bug de
  dispatch séparé (voir `_syntax_gaps.md`).
- `delay`/`force` sont des magic symbols, pas des formes syntaxiques.

**Validé** : `force (delay 42) = 42`, `force (delay (+ 1 2)) = 3`,
memoization confirmée par `twice t = (+ (force t) (force t))` avec
`twice (delay 99) = 198`.

**Référence** : commit `fc2e20c`, `smoke.sh` section D12.

## D14 — IO en Heaven (2026-10-07, suite de D13)

**Constat** : D13 avait livre des magics stateful en Zig (`open_file`,
`read_line`, `close_file`). Ce n'est pas aligne avec la VISION ("au max
en Heaven"). 90% de la logique etait en Zig, 10% en Heaven.

**Decision** : remplacer les 3 gros magics par 5 primitives **fines**
(cadrage "policy + mechanism" : Zig fait le mecanisme, Heaven fait la
politique).

Primitives fines (~5 lignes chacune, dans `evalMagic`) :

| Nom | Signature | Role |
|---|---|---|
| `string_ptr` | `String -> Int` | adresse des bytes d'une string internee |
| `raw_alloc` | `Int -> Int` | buffer malloc-style |
| `raw_free` | `Int Int -> Unit` | liberer |
| `target_os` | `() -> String` | "linux"/"macos"/"windows" |
| `raw_syscall` / `6` | (D10) | base de tout appel systeme |

**Logique en Heaven** (`core/io_stream.hvn`, Linux x86_64) :

    io_open path = (raw_syscall6 257 (- 0 100) (string_ptr path) 0 0 0 0)
    io_read fd buf n = (raw_syscall6 0 fd buf n 0 0 0)
    io_close fd = (raw_syscall6 3 fd 0 0 0 0 0)

**Alternatives ecartees** :
- Garder D13 (magics stateful) : 3 magics de 40 lignes, non portables.
- `inline_qbe "syscall"` : QBE n'a pas d'asm inline (rejete D10).
- Forker QBE : maintenir un patch divergent a chaque bump.

**Debloque** :
- Portable : ajouter `core/io_stream_macos.hvn` avec les memes noms.
- Auditable : la politique IO est lisible en Heaven.
- Testable : `io_open`/`io_read` utilisables en REPL sans recompiler.

**Limites assumees** :
- `raw_alloc` fuit : pas de GC, `raw_free` explicite.
- `-100` doit s'ecrire `(- 0 100)` (voir D15 / quirks parser).
- Pas de `peek_byte`/`poke_byte`/`string_concat` : vrai stream_file
  (parse '\n') = etape 2, session suivante.

**Tests valides** :
- `io_open` inexistant -> `-2` (ENOENT), existant -> `4`
- `(io_read (io_open "f") (raw_alloc 16) 16)` -> `6` bytes

## D15 — `let` magic symbol (2026-10-07)

**Constat** : `(let x 5 x)` etait affiche verbatim par le REPL. Le tag
`.bind` existe (Haskell-style `let x = 5 in x`) mais la forme S-expr
pure n'est pas evaluable. Impact : composer des expressions IO (D14)
demandait la syntaxe verbeuse `(let x = v in ...)`.

**Decision** : ajouter `let` a `isMagicSymbol`. Forme : `(let name val body)`.
15 lignes dans `evalMagic` :
- `arg0` : symbole (nom)
- eval `arg1` -> valeur
- `env.put(name, val)`
- eval `arg2` -> resultat
- `env.delete(name)`

**Note** : les deux formes coexistent (Haskell-style `.bind` + S-expr
`let` magic). Pas de deprecation.

**Debloque** :
- Syntaxe naturelle pour D14 : `(let fd (io_open "f") (let buf (raw_alloc 16)
  (io_read fd buf 16)))`
- Base pour `letrec`, `let*` (multi-bind) si besoin plus tard.


## D16 — Serveur HTTP 100% Heaven (2026-10-07)

**Constat** : apres D10 (syscalls), D14 (IO en Heaven) et D15 (`let`
magic), tous les composants pour un serveur HTTP etaient en place. Le
seul obstacle restant etait la **syntaxe du loader** : `std_loader.zig`
evaluait ligne par ligne, forcant un style Lispy illisible.

**Decision** :
1. **Loader multi-ligne** : `std_loader.zig` accumule les lignes tant
   que les parentheses ne sont pas equilibrees ET que le buffer ne
   finit pas par `=`. Permet les definitions sur plusieurs lignes.
2. **4 magics HTTP** : `peek_byte`, `poke_byte`, `memset`,
   `string_length`. `decodeEscapes` dans `expr.zig` pour `\r\n`.
3. **`core/http.hvn`** : `http_serve_once` (socket/bind/listen/accept/
   write/close). Aucun magic supplementaire -- tout en Heaven au-dessus
   de 13 primitives Zig.

**Alternatives ecartees** :
- Forker un mini-HTTP en Zig : contraire a la VISION.
- Parser Haskell-style `let x = v in body` : chantier separe (~1 session).
  S-expr multi-ligne suffit pour l'instant.

**Debloque** :
- `curl localhost:8080` -> `Hello from Heaven` (test E2E).
- Socket TCP client, chat, autres serveurs.
- Style lisible dans toute la stdlib (stream, io_stream, bigint).

**Limites v0** : pas de parser HTTP (repond toujours la meme chose),
pas de boucle (one-shot). Chantier v1 si besoin.

**Tests** : `curl` verifie dans le commit `3c94929`.

## D17 — BigInt v0 (2026-10-07)

**Constat** : `i64` plafonne a ~9.2 * 10^18. Pour l'auto-hebergement
(crypto, arithmetique de preuves, comptage) il faut de la precision
arbitraire. Le langage offrait tous les outils (listes, pattern
matching, recursion) depuis longtemps, mais la stdlib n'avait pas de
BigInt.

**Decision** : ecrire BigInt **en Heaven pur** (aucun magic
supplementaire).

Representation :
    data BList = BNil | BCons Int BList
    data BigInt = BZero | BPos BList | BNeg BList
Digits 0..9, MSB-first. BNeg construit mais operations v0 positives.

Operations v0 :
- `from_int` / `to_int` (i64 <-> BigInt)
- `from_string` (via `str_char` = `peek_byte (string_ptr s) i`)
- `badd` / `bsub` (reverse + LSB-first + carry)
- `bcmp` (par longueur puis element-wise)

**Preuve** : `10^26 + 1 > 10^26`, `(10^26 - 1) + 1 == 10^26`.
Depasse largement `i64`.

**Alternatives ecartees** :
- Linker libtommath : contraire a la VISION (auto-hebergement).
- BigInt en Zig : meme probleme.
- Base 2^32 (un digit par mot) : plus rapide mais necessite des
  operations bit-a-bit absentes. Base 10 suffit pour v0.

**Debloque** :
- Calculs de precision arbitraire.
- Base pour RSA, tests de primalite.
- Etape vers l'auto-hebergement.

**Limites v0** : BNeg construit mais non traite. Pas de `bmul`, `bdiv`,
`bmod`, `bto_string`. Session 2 planifiee.

**Tests** : `tests/test_bigint.hvn` (14 tests).

**Note** : `bnull` retourne `boolean` (pas `int`) -- `if` exige un
`.boolean`. Erreur frequente, cf `_syntax_gaps.md`.

## D18 — Style Haskell multi-ligne (2026-10-07, suite de D16)

**Constat** : apres D16 (multi-ligne S-expr), le style restait avec des
parentheses imbriquees. La forme `let x = v in body` sur plusieurs
lignes n'etait pas supportee -- le loader evaluait trop tot.

**Decision** :

1. **Accumulation par indentation** dans `std_loader.zig` et
   `test_runner.zig::splitStatements` : une ligne non-indentee (colonne 0)
   commence un nouveau statement ; les lignes indentees sont des
   continuations. Style Haskell/Python.

2. **`heaven_expr.zig::convertLetIn`** : conversion textuelle recursive
   `let x = v in body` -> `(let x v body)`. La **valeur** ET le **rest**
   sont wrappes dans des parens si multi-tokens. Cherche `' in'` suivi
   de whitespace (espace, tab, newline) ou fin de chaine.

**Alternatives ecartees** :
- Parser Haskell complet : surdimensionne. La conversion textuelle suffit.
- Analyse de lignes par parens uniquement : rate le cas ou le body suit
  sur la ligne suivante sans parens.

**Debloque** :
- `http.hvn`, `bigint.hvn`, `io_cat` reecrits en style lisible.
- Toute la stdlib future beneficie du meme style.

**Exemple** :

    http_serve_once unit =
      let sock = raw_syscall6 41 2 1 0 0 0 0 in
      let sa = http_mk_sa_8080 unit in
      let _ = raw_syscall6 49 sock sa 16 0 0 0 in
      let _ = raw_syscall6 50 sock 5 0 0 0 0 in
      http_handle_one sock

**Tests** : 5, 11 (let-in 1-ligne, multi-ligne, imbrique), curl
localhost:8080 -> Hello from Heaven.

## D18 — Style Haskell multi-ligne (2026-10-07, suite de D16)

**Constat** : apres D16 (multi-ligne S-expr), le style restait avec des
parentheses imbriquees. La forme `let x = v in body` sur plusieurs
lignes n'etait pas supportee -- le loader evaluait trop tot.

**Decision** :

1. **Accumulation par indentation** dans `std_loader.zig` et
   `test_runner.zig::splitStatements` : une ligne non-indentee (colonne 0)
   commence un nouveau statement ; les lignes indentees sont des
   continuations. Style Haskell/Python.

2. **`heaven_expr.zig::convertLetIn`** : conversion textuelle recursive
   `let x = v in body` -> `(let x v body)`. La **valeur** ET le **rest**
   sont wrappes dans des parens si multi-tokens. Cherche `' in'` suivi
   de whitespace (espace, tab, newline) ou fin de chaine.

**Alternatives ecartees** :
- Parser Haskell complet : surdimensionne. La conversion textuelle suffit.
- Analyse de lignes par parens uniquement : rate le cas ou le body suit
  sur la ligne suivante sans parens.

**Debloque** :
- `http.hvn`, `bigint.hvn`, `io_cat` reecrits en style lisible.
- Toute la stdlib future beneficie du meme style.

**Exemple** :

    http_serve_once unit =
      let sock = raw_syscall6 41 2 1 0 0 0 0 in
      let sa = http_mk_sa_8080 unit in
      let _ = raw_syscall6 49 sock sa 16 0 0 0 in
      let _ = raw_syscall6 50 sock 5 0 0 0 0 in
      http_handle_one sock

**Tests** : 5, 11 (let-in 1-ligne, multi-ligne, imbrique), curl
localhost:8080 -> Hello from Heaven.

## D17 v1 — BigInt signe + mul + divmod (2026-10-07, session 2)

**Constat** : D17 v0 couvrait badd/bsub/bcmp non signes. Pour un usage
reel (RSA, test de primalite, comptage), il faut les signes et `bmul`.

**Decision** : etendre `core/bigint.hvn` sans ajouter de magics
supplementaires (juste `string_concat` et `int_to_string`).

Ajouts :
- `string_concat s1 s2` -> s1 ++ s2 (magic fin, ~10 lignes).
- `int_to_string n` -> string (magic fin, ~10 lignes).
- `BPos` / `BNeg` operationnels : `badd_signed`, `bsub_signed`,
  `bmul_signed`, `babs`, `bneg`, `bsign`.
- `bmul_bl` (BList) via digit par digit + `bshift_bl` (x10) + carry
  correct (`bmul_digit_lsb` en LSB-first).
- `bto_string` / `from_string` signes.

**Piege documente** : `badd = badd_signed` (alias 0-aire) NE marche PAS.
Le moteur ne dispatche pas un 0-aire. Il faut :
    badd A B = (badd_signed A B)

**Alternatives ecartees** :
- Algorithmes de multiplication rapide (Karatsuba, Toom-Cook) : v2
  si les perf deviennent un probleme. Digit-school suffit pour v1.
- bdivmod (division euclidienne) : reporte en v2. Algo naif
  (soustraction repetee) code mais lent ; sera remplace par la
  division longue standard.

**Preuve** : 22/22 tests. Inclut :
- tous les signes (+ +, + -, - -, - +)
- `bmul 123 x 456 = 56088`
- `bto_string (from_int (- 0 7)) = "-7"`
- HUGE : `10^26 + 1 > 10^26`, `(10^26 - 1) + 1 = 10^26`

**Limites v1** : pas de `bdivmod`, pas de `bmod`, pas de Karatsuba.

## D8 3a-3-b -- handle-rec operationnel (2026-10-08)

**Constat** : la spec D8 demandait 3a-1 (prompts), 3a-2 (captureCont),
3a-3 (branchement). Les deux premiers etaient faits (continuation.zig,
9 tests). Le troisieme etait le blocage -- la pile Zig est deja
depilee quand perform remonte au handle.

**Decision** : handle-rec par replay avec etat (Voie pragmatique,
pas Voie B complete).

Primitive : (handle-rec body_fn handler init_state).
- Boucle : state := init. body_fn(state) -> valeur finale OU
  (perform op v) qui yield.
- Handler (v, k) recoit la valeur yielded et un magic-symbole k.
- Si handler appelle (k new_state) -> reboucle avec state = new_state.
- Sinon -> retour.

Implementation (~80 lignes, evalMagic) :
- RecCtx dans Engine : context persistant.
- perform : branche sur rec_ctx -> error.HandleRecYield.
- __handle_rec_k : magic, capture next_state + k_signaled.
- Dispatch env-bound : un symbole lie a un magic est route vers
  evalMagic (indispensable pour (k x)).

**Ce qui marche** (4 tests) :
- countdown 5 -> 0 (5 iterations yield/resume)
- sum jusqu'a 3 -> 3
- handler sans k -> one-shot (retour direct)
- 10 iterations -> 0

**Ce qui reste (Voie B, 2-3 sessions)** :
- Multi-shot general (backtracking, vrais generateurs).
- Replay total : les sous-effets dans body_fn sont rejoues a chaque
  iteration. Cout O(n^2) pour n iterations avec sous-effets.
- Scheduler preemptif C3 : sur Voie B uniquement.

**Impact** : debloque les boucles recursives via effet, prepare le
scheduler. Le langage peut maintenant exprimer des effets qui
"reviennent" (yield/resume).

**Piege** : (k x) exige que k soit un SYMBOLE binde (pas une lambda
directe). Sinon evalMagic ne dispatche pas.


## D8 3a-3-b (suite) -- fix lambda multi-args (2026-10-08)

**Bug decouvert en implementant handle_rec** : le parser ne lisait
qu'un seul parametre de lambda. (lambda v k -> body) capturait 'v',
laissait 'k' et '->' comme params residuels -> UnboundVariable.

**Fix** : parseSExpr collecte tous les tokens avant '->' ou '=>'.

**Impact** :
- handle_rec avec lambdas inline marche.
- map/filter/foldl avec lambdas multi-args marchent.
- Tout ordre-superieur debloque.

**Suite** : renomme handle-rec -> handle_rec (le '-' est tokenise
comme operateur infixe). Syntaxe finale : (handle_rec body handler init).

**Tests** : 4/4 dans test_effects_rec.hvn (lambdas inline).


## D8 3a-3-c-b -- Scheduler cooperatif (2026-10-08)

**Contexte** : 3a-3-b a livre handle_rec (yield/resume via RecCtx).
3a-3-c-a a branche Scheduler sur Engine. 3a-3-c-b livre les magics
qui exposent le scheduler a Heaven.

**Decision** : scheduler cooperatif via 4 magics.

Syntaxe :
    task_id = (add_task body_fn init_state)
    (schedule budget_per_iteration)
    (yield new_state)       -- dans body_fn
    (task_state task_id)    -- lecture etat courant

**Mecanique** :
- `add_task` cree une entree dans engine.scheduler.tasks avec
  body_fn + current_state.
- `schedule` : boucle while. Choisit tache .ready via scheduler.next().
  L'evalue via evalWithBudget. Si yield : maj current_state, tache
  redevient .ready. Si done : current_state = resultat, .finished.
- `yield` : Reutilise le RecCtx de handle_rec. Signale next_state +
  k_signaled. Le scheduler capture puis remet en queue.
- `task_state` : lookup task_id dans scheduler.tasks, evalue le Id
  du current_state (bug initial : retournait le Id du Store).

**Modele redemarrable** : quand budget epuise, la tache est re-mise
.ready et reevaluee depuis le debut. Pas de reprise exacte. Coherent
avec handle_rec et evalWithBudget.

**Ce qui marche** (3 tests) :
- 1 tache sans yield -> resultat final.
- 1 tache avec yield 3x -> etat intermediaire puis final.
- 2 taches entrelacees -> somme correcte.

**Limitations v0** (chantier futur = Voie B complete) :
- Pas de reprise exacte : une tache interrompue par budget repart
  du debut. Acceptable pour du calcul pur, pas pour des effets.
- Pas de priorites appliquees (policy .priority existe, pas utilisee).
- Pas d'integration avec spawn/actor (modeles paralleles).

**Debloque** :
- Multitache cooperatif utilisable en Heaven.
- Base pour le scheduler preemptif (C3, Voie B).
- Experimentations sur les effets concurrents.

**Tests** : test_scheduler.hvn (3 tests).

## D20 -- Recursion profonde : ReleaseFast par defaut (2026-10-08)

**Constat** : `f 200` segfault en Debug. `bdiv > 400` segfault.
Diagnostic initial : tree-walker recursif consomme ~40 KB par
niveau utilisateur (accumulation de frames Zig).

**Investigation** :
- Debug : limite ~130 niveaux (frames non optimisees, bounds checks,
  traces).
- ReleaseFast : limite ~500-700 (4-5x mieux). Pas de changement de
  code, juste le mode de compilation.
- Tentative inline (evalBinary, evalUnary, evalCmp, isMagicSymbol) :
  aucun gain. La frame d'evalMagic (1001 lignes, 30+ variables
  locales) domine.
- Tentative extraction du bloc handle_rec + scheduler (38 KB de code,
  48 var/24 if) : casse car le bloc utilise des variables du scope
  parent (`args`, `args_buf`). Refactor propre = 2-3 sessions.

**Decision** : ReleaseFast par defaut pour le binaire natif
(`build.sh`). WASM reste en ReleaseSmall (taille).

**Resultat** :
- `f 500` : OK
- `bdiv 1000/7 = 142` : OK
- `bmod 1000/7 = 6` : OK
- Limite haute : ~500-700 niveaux utilisateur

**Limitations restantes** (chantier futur, Voie B ou refactor) :
- `f 1000` echoue.
- `bdiv 10^26 / 7` echoue (27 digits, mais bdivmod_bl recursif).
- Le tree-walker recursif atteindra toujours une limite finie sur 8 MB.

**Vraie solution future** : tree-walker iteratif complet (state
machine, 2-3 sessions) OU refactor de `evalMagic` en sous-fonctions
(moins invasif, 1-2 sessions).

**Tests** : 30/30 BigInt (avec bdiv/bmod 1000/7 remis).


## D21 : Unification du Lowering vers Expr.Store (2026-10-08)
- **Contexte** : Coexistence de deux pipelines : `UniversalIngestor` → `Matrix/BobId` → `SurvivalTranspiler` (C) ET `Tree-sitter` → `Expr.Store` → `MIR` → `QBE/WASM`.
- **Problème** : Duplication de logique, maintenance de deux IRs, complexité accrue.
- **Décision** : `Expr.Store` (Id = Expr = Value) devient l'unique IR intermédiaire. `src/syntax/lower.zig` est étendu pour abaisser directement vers `Expr.Store`. `Matrix` et `SurvivalTranspiler` seront progressivement dépréciés et déplacés vers `src/legacy/`.
- **Critère de succès** : 100% des constructions syntaxiques de base (`binop`, `call`, `let`, `lambda`) passent par `lowerExprToStore` avec succès.

## Décision technique 2026-10-09 : Gestion du quirk Tree-sitter pour `let ... in`

**Contexte** : Lors de l'implémentation du pont Tree-sitter → Expr.Store pour `let x = 1 in x`, nous avons découvert que Tree-sitter groupe parfois la valeur et le mot-clé `in` dans un nœud `app_expr` (ex: `"1 in"`).

**Décision** : Plutôt que de modifier la grammaire Tree-sitter, nous avons implémenté un contournement dans `lowerExprToStore` :
- Détecter si le nœud `val` est un `app_expr` ou `call`
- Si oui, prendre son premier enfant nommé comme valeur réelle
- Sinon, utiliser le nœud tel quel

**Justification** :
- Minimise les changements à la grammaire
- Isolé dans un seul bloc de code facile à maintenir
- Peut être retiré si la grammaire est corrigée plus tard

**Alternatives considérées** :
1. Modifier `grammar.js` pour forcer un nœud séparé → Risque de casser d'autres tests
2. Ignorer `let ... in` dans le pont → Inacceptable pour le chantier D21
