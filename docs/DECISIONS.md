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

---

## D26 — Fonctions first-class : fix du reconstruct apply (2026-10-09)

**Contexte** : en implémentant les optiques (D27), on découvre que
`((fst (pair g h)) 5)` échoue alors que `(let f (fst (pair g h)) (f 5))`
marche. Les fonctions n'étaient pas pleinement first-class.

**Cause** : dans `evaluate(.apply)` (`engine_expr.zig`), la branche
`op_node.tag != .sym` reconstruisait un nouveau nœud `apply` avec
`payload = evaled_op` mais `span_a = node.span_a` (l'ancien span
incluant `op_id`). Résultat : `all_args[0] == op_id` ne matchait plus,
et `args` contenait 2 arguments au lieu d'1.

**Décision** : extraire `args_only` explicitement (skip `op_id` si
présent) et reconstruire via `store.apply(evaled_op, args_only)`.

**Impact** : débloque les optiques, free monads, DSLs — toute
structure contenant des fonctions comme valeurs.

**Commit** : `2810cc7` (9 lignes).

---

## D27 — Optiques v0 : lens = couple (getter, setter) (2026-10-09)

**Contexte** : suite de la série Kmett. Le chapitre 15 du book
présente les optiques. La question : implémenter ou documenter ?

**Décision** : implémenter v0 minimal — `core/std/lens.hvn` (32 lignes).
Une lens est un couple `(get, set)` construit par `lens`. Opérations :
`view`, `set_via`, `over`. Lenses pour `Pair` (fst, snd) + une lens
profonde manuelle.

**Limitations v0** :
- Pas de composition générique (types higher-rank absents).
- Pas de prism / traversal.
- Pas de record (pas de champ nommé).

**Justification** : la version minimale **fonctionne** et documente ses
limites. Le motif est capté, l'API est stable (`view`/`set_via`/`over`).

**Commit** : `b11af7e`. Tests : `test_lens.hvn` 12/12.

---

## D28 — Free monad AST interpretable v0 (2026-10-09)

**Contexte** : suite Kmett, chapitre 16. La vraie free monad demande
des HKT + continuations valuées.

**Décision** : implémenter une version dégénérée —
`core/std/free.hvn` (49 lignes). `data Free = Pure Int | Push | Add |
Mul | LogOp` = AST d'opérations. Plusieurs interpréteurs
(`run_stack` sur pile, `run_trace` collecte les logs).

**Limitations v0** :
- Pas de `>>=` (bind) monadique : `Pure` marque une position de pile,
  pas une valeur de retour. Les continuations valuées (`Int -> Free`)
  demanderaient des lambdas dans les continuations et un type de
  retour réifié.
- Le nom `bind` est **réservé** (6 primitives du noyau) — le nom
  `chain` avait été tenté puis retiré pour cause d'incompatibilité
  sémantique.

**Justification** : l'idée (séparer programme/interprétation) est plus
importante que la généralité. L'AST est utile, honnête sur ses limites.

**Commit** : `d0db939`. Tests : `test_free.hvn` 14/14.

---

## D29 — Literals hex + parens triviales (parser, 2026-10-09)

**Contexte** : en cherchant à fixer `0xFF`, on découvre un bug
préexistant plus profond : `(1) == 1` échoue alors que `1 == 1` passe.

**Trois bugs cumulés corrigés** :

1. **Lexer** (`expr.zig`) : `0xff` était tokenisé en deux tokens
   (`0` puis `xff`), produisant `(0 xff)` = `apply(0, [xff])`.
   Fix : lire les hex digits dans le même token `.num`.

2. **`parseFloat` C99** : acceptait `0x1` (syntaxe hex float C99),
   produisant `.float=1`. Fix : check hex **avant** `parseFloat`, dans
   `parse.zig` et `expr_parser.zig`.

3. **Cas trivial de `parseSExpr`** : un seul token sans structure
   devenait `apply(sym(tok), [])` au lieu d'un `int`/`str`/`bool`.
   Fix : déléguer à `parseExpression`.

4. **Cas 1 de `parseSExpr`** : `(X)` sans args produisait
   `apply(func_id, [])` fantôme. Fix : `if args.len == 0 return func_id`.

**Impact** : hex fonctionnel partout, parens triviales corrigées.
**2 bugs préexistants débusqués** au passage (parens atome, hex vs
float).

**Commits** : `e5e84ce` (lexer), `6fe55ec` (parser hex), `0881c93`
(parens). Tests : `test_parser_literals.hvn` 23/23.

---

## D30 — Serveur HTTP statique natif en Heaven (2026-10-09)

**Contexte** : D16 avait livre un serveur HTTP "hello world" (25
lignes, reponse hardcodee). Il fallait le rendre reellement utile :
servir des fichiers, parser la requete, boucler.

**Decision** : implementer un serveur HTTP **statique** en Heaven pur
(`core/http.hvn`, ~80 lignes). Aucune magic nouvelle, aucune
dependance externe (pas de libc, pas de Zig, pas de Python).

**Composants** :
- `http_serve` : setup socket + boucle infinie (TCO).
- `http_extract_path` : parse `GET /path HTTP/1.1` via `string_index_of`.
- `http_normalize_path` : `/` → `/index.html` (repertoires).
- `http_serve_file` : lit `src/vessel/public<path>`, 404 sinon.
- `http_sock_reuse` : SO_REUSEADDR (evite TIME_WAIT 60s).

**Syscalls utilises** : socket(41), accept(43), bind(49), listen(50),
setsockopt(54), openat(257), read(0), write(1), close(3).

**Deux serveurs coexistent** :
- **Vessel** (Zig, port 10999) : REPL web + WASM + endpoints API.
- **Serveur natif** (Heaven, port 8080) : fichiers statiques.
Distinction documentee dans le glossaire (C-glossaire.md) et Ch9.

**Limitations v0** :
- Port 8080 hardcode.
- Content-Type fixe (`text/html`).
- Pas de keep-alive, pas de routes dynamiques.

**Tests** : `tests/test_http.hvn` (13/13) pour les helpers purs.
Le serveur complet est teste manuellement :
`heaven run serve.hvn` puis `curl localhost:8080/egraph-viz/`.

**Commits** : `a73e29f` (v2), `b8b9374` (tests), `9ae9df5` (SO_REUSEADDR).

**Spec** : `docs/spec/_http.md`.

<!-- HEAVEN:D31 -->
## D31 — Scheduler préemptif C3 : safepoints + budget de réductions

**Date** : 2026-10-14
**Statut** : TRANCHÉE — implémentation partielle

**Contexte** : C3 listée comme option ouverte dans `_concurrency.md`.
Trois options : (1) safepoints instrumentés, (2) signaux + timer,
(3) coopératif pur.

**Décision** : option 1. Le compilateur insère des safepoints,
l'interpréteur décrémente `engine.reductions` à chaque pas
d'évaluation. À 0, la tâche est suspendue comme un `yield` implicite.

**Conséquence** : le safepoint n'est PAS une capture. La préemption
fine exige le branchement réel de `captureCont` (3a-3b). Sans 3a-3b,
C3 est conceptuellement débloqué mais techniquement partiel.

<!-- HEAVEN:D31:ADDENDUM -->
### D31 — Addendum 2026-10-14 (bug fix)

**Bug identifié** : `schedule` avec un budget insuffisant provoque un
livelock — la tâche suspendue sans yield est remise `.ready`, et la
boucle `while(true)` la reprend indéfiniment. Se déclenche dès que
`budget < reductions_necessaires`, y compris `budget 0` (freeze du
système, OOM).

**Fix A** : garde `budget == 0` en tête de `schedule` → retour
immédiat.

**Fix B** : en cas de `.suspended` sans `pending_capture`, marquer la
tâche `.blocked` (au lieu de `.ready`). La reprise exacte exige
`captureCont` (3a-3b) — hors scope. En attendant, `.blocked` garantit
la terminaison.

**Limite introduite** : une tâche dont le budget est épuisé passe
`.blocked` et **n'est jamais reprise**. Budget insuffisant = tâche
perdue. Ce n'est PAS la sémantique cible (round-robin équitable) ;
c'est un palliatif de terminaison en attendant le branchement réel
de `captureCont` (3a-3b), seul moyen de reprendre une tâche
exactement où elle s'est arrêtée.

**Test** : `test_preemptive.hvn` 12/12 ✓ (T1-T6) ; `test_scheduler.hvn`
3/3 ✓. La préemption fine reste un chantier, mais le livelock et le
freeze système sont éliminés.

### D31 — Addendum 2026-10-14 (A-3a)

**Livré** : `TaskState.preempted` (distinct de `.blocked` terminal)
+ conversion `.preempted -> .ready` en tête de `schedule` (une
seule fois, sinon livelock) + budget épuisé -> `.preempted`.

**Modèle** : redémarrable. La tâche repart du début (`current_state`
inchangé) mais n'est plus perdue. Coût quadratique en nombre de
suspensions — acceptable pour V0.

**Tests** : `test_preemptive_split.hvn` 0/2 -> 3/3. Non-régression :
scheduler 3/3, preemptive 12/12, coop 4/4, bigint 30/30,
hashmap 50/50, parser 22/22.

**Dette identifiée séparément** : `(+ 1 2 3 4)` dans une lambda
retourne 0 (bug d'arité sur le magic `+`, indépendant de C3).
Voir `docs/spec/_preemptive_split_bug.md`.

**Prochaine étape** : reprise exacte via `captureCont` (3a-3b) —
chantier séparé, cf. `_capture_eval.md`.

## D-SH4 — Pas de dependance Zig std pour la metacircularite

**Date** : 2026-10-15
**Statut** : TRANCHEE.

**Regle** : le code qui doit etre porte un jour en Heaven (runtime,
reseau, IO, crypto) utilise `raw_syscall*` directement, PAS
`std.posix.*` ni `std.net.*`.

**Autorise** : Zig std pour le host (allocator, debug, builtins,
FFI C comme OpenSSL).

**Interdit** : `std.posix.socket/connect/read/write`, `std.net.*`,
`std.fs.*` dans le code portable.

**Consequence** : N1 (TCP client) doit etre refactore. N2 (DNS)
sera en Heaven pur. Voir `_selfhosting_roadmap.md`.

## D-SH1 — TLS : OpenSSL via FFI

**Date** : 2026-10-15
**Statut** : TRANCHEE.

**Decision** : utiliser OpenSSL (`libssl.so`) via FFI C. TCC est
deja lie au build ; ajouter libssl est du meme ordre.

**Alternatives ecartees** :
- TLS en Heaven pur (6-12 mois, hors scope).
- Pas de TLS (non-deployable en prod).

## D-SH2 — Persistance : Bitcask-like en Heaven

**Date** : 2026-10-15
**Statut** : TRANCHEE.

**Decision** : Bitcask (append-only log + index RAM) ecrit en
Heaven pur. ~500 lignes.

**Alternatives ecartees** :
- SQLite FFI (moins Heaven-natif).
- Cassandra auto-heberge (operationnellement lourd).

## D-SH3 — IA : ONNX FFI + vector DB native

**Date** : 2026-10-15
**Statut** : TRANCHEE.

**Decision** : ONNX Runtime via FFI pour l'inference. Base
vectorielle (HNSW) en Heaven pur.

**Alternatives ecartees** :
- llama.cpp FFI (specifique LLM).
- Heaven pur (limite a < 10M params).

## D-HTTP1 — telemetry_store lit expr.Store, pas matrix

**Date** : 2026-10-19
**Statut** : TRANCHEE.

**Decision** : `/telemetry` sert depuis `expr.Store` (via
`src/vessel/telemetry_store.zig::render`), pas depuis
`matrix_lib.Matrix`. `WebBridge.store` puis `WebBridge.heaven`
remplace la dependance matrix pour cette route.

**Alternatives ecartees** :
- Garder matrix + traduire : double source de verite.
- Render dans bridge.zig : melange transport et serialisation.

## D-HTTP2 — didSave evalue via Heaven, pas syncMatrix

**Date** : 2026-10-19
**Statut** : TRANCHEE.

**Decision** : `textDocument/didSave` lit le fichier, split en
statements (`splitStatements`), evalue chaque statement via
`Heaven.eval`. Le resultat vit dans `Heaven.getStore()`, lu par
`serveTelemetry`. `syncMatrixWithFile` n'est plus appele.

**Alternatives ecartees** :
- Garder syncMatrixWithFile : etait un stub (`return;`), endpoint
  LSP mort.
- Eval par ligne : casse multi-lignes (`{ ... }`, let-chains).

**Note** : ce n'est pas un LSP complet (pas de diagnostics, hover,
positions). Eval-on-save seulement. LSP complet = E4+ et parser
incremental.

## D-CI1 — baseline --run-tests en ReleaseFast, pas Debug

**Date** : 2026-10-19
**Statut** : TRANCHEE.

**Decision** : `HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven
--run-tests tests` doit etre lance sur le binaire **ReleaseFast**
(`zig build -Doptimize=ReleaseFast`). En Debug, 3 fichiers crashent
(SIGSEGV) : `test_parser.hvn`, `test_hashmap.hvn`,
`test_bigint_d20.hvn`. Debug-only, priorite basse.

**Alternatives ecartees** :
- Fixer Debug : 1 session de triage, non prioritaire, ReleaseFast
  est la cible prod.
- Ignorer : risque de "regression" fantome a chaque session.

**Consequence** : `zig build test` reste en Debug (tests Zig
unitaires), `--run-tests tests` est en ReleaseFast. Voir
`_runner_crashes_2026-10.md`.

## D-HKT1 — HKT V1b : matching structurel (reco A)

**Date** : 2026-10-19
**Statut** : TRANCHEE.

**Decision** : V1b = matching structurel explicite (option A du
`_hkt_v1b_plan.md`). Le type `T` est passe en argument string
(`fmap "List" f xs`), pas d'inference de type. Deux magics livrent
la mecanique :

- `@resolve_instance C T op` -> `op_T` ou "" (pas 1, `62155ce`).
- `@dispatch_instance C T op args...` -> `op_T(args...)` (pas 2,
  `1ba6aa4`).

**Alternatives ecartees** :
- Option B (inference via `elab.zig`) : 3-4 sessions, risque de
  decouvrir que `elab` type-check mais n'inferre pas. Repousse.

**Consequence** : V1c (contraintes `Functor f =>`) devient un
checker simple. V1b pas 3 = dispatch sur sym `List` sans quotes
(acces `.sym` name), ~1 bloc.

## D-B3-1 — B3 cutoff apres 2 tentatives

**Date** : 2026-10-19
**Statut** : TRANCHEE (cutoff).

**Decision** : sur `let a = 1 in let b = 2 in body` (B3), 2 fixes
tentes, 0 effet, un 3e bug decouvert. Cutoff applique (rollback +
doc). Ne pas re-tenter a chaud.

**Bilan** :
1. `normalizeLetChain` top-level `heaven.eval` -> **FIXÉ**
   (`66f0b32`). Debloque `heaven run script.hvn` avec let-chain.
2. `normalizeLetChain` dans `parseBodySmart` -> **KO** (rollback).
3. Pattern `_` + `heaven run` : `helper _ = 42` + `(helper 0)` ->
   `ArityMismatch`. Decouvert en fin de session, non diagnostique.
   **Bloque E4b**.

**Regle** : 2 tentatives max par bug, puis cutoff. Le discriminant
doit preceder le patch (5 faux diagnostics cette session : grep
`"net_` au lieu de `"@net_`, `@net_listen` bugge, B1 non-evalue,
PI kernel absent, `_let_wildcard` non reproductible).

## D-E5-1 — E5 en deux temps (partial)

**Date** : 2026-10-19
**Statut** : TRANCHEE (phase 1).

**Decision** : E5 = retire `matrix`/`autofab` de `bridge.zig` en
premier (`0ece80f`), garde `main.zig` intact. Extraction de
`bob_loop` + `Matrix.init` + `syncMatrixWithFile` = E5-bis,
session fraiche.

**Raison** : `bridge.zig` etait le chemin HTTP actif (D9). Tant
que `bob_loop` (boucle Bob principale) tourne sur `matrix`, la
suppression cote main casse le runtime. E5-bis demande extraction
de la boucle, pas juste une suppression.

## D-E5-TER — Migration complète Matrix -> Store (actée 2026-10-19)

**Date** : 2026-10-19
**Statut** : TRANCHEE (migration complète, pas cohabitation).

**Décision** : migrer les 6 consommateurs de `Matrix` vers
`expr.Store` + `egraph`. `Matrix`/`AutoFab` iront en `src/legacy/`
quand la migration sera terminée.

**Constat d'audit (2026-10-19)** : `Matrix` et `Store` ne sont PAS
deux implémentations de la même abstraction. Ils diffèrent sur :

| Matrix | Store |
|---|---|
| `nodes: Map BobId -> Node` | `nodes: []Node` (Id u32) |
| `next_id` (BobId monotone) | `intern()` (hash-consing) |
| `add`, `find`, `get(BobId)` | `get(Id)`, `apply`, `lit`, `sym` |
| `saturate` (e-graph local) | Pas d'equivalent (egraph.zig separe) |

**Consommateurs à migrer** (audit grep 2026-10-19) :
- `main.zig` : `matrix.deinit` + 10 sites de threading.
- `bob_loop.zig` : `m.next_id`, `m.saturate`.
- `UniversalIngestor` : `matrix.add`, `matrix.find`, `matrix.nodes`.
- `AutoFab` : `matrix.get`, `matrix.nodes`.
- `ReactionEngine` : `matrix.add`, `matrix.get`.
- `Shell` : (grep vide, à reverifier -- possible usage indirect).

**Effort réel** : 4-5 sessions (pas 2-3). Change la sémantique :
BobId (reseau) devient optionnel, `saturate` passe sur `egraph`,
`find` devient du pattern matching sur DAG.

**Plan phasé (propose)** :

- **E5-ter-0 (session design, 0 code)** : trancher (a) mapping
  BobId <-> Id (garder ou abandonner), (b) sort de `saturate`
  (egraph global), (c) ordre de migration. Ecrire
  `_matrix_migration_plan.md`.
- **E5-ter-1** : migration `ReactionEngine` (le plus petit, 3
  methodes).
- **E5-ter-2** : migration `UniversalIngestor` (add/find/nodes).
- **E5-ter-3** : migration `AutoFab` (get/nodes) -- proche de
  ReactionEngine.
- **E5-ter-4** : migration `bob_loop` (next_id/saturate, couplage
  reseau).
- **E5-ter-5** : `main.zig` sans `matrix_lib`/`autofab_lib`,
  `Matrix` -> `src/legacy/`.

**Ne pas commencer sans E5-ter-0.** La sémantique de BobId est
utilisee par `scut/network.zig` (sync pair-a-pair). Une migration
naive casserait le reseau.

**Alternatives ecartees** :
- Cohabitation (ma reco initiale) : rejetee par l'utilisateur.
  Matrix reste pour KB/RDF, Store pour eval/proofs. Plus simple
  mais laisse deux modeles.
- Legacy partiel : `Matrix` reexporte, pas de migration reelle.

**Consequence** : E5 (D9) n'est PAS fini. E5a/E5b faits
(bridge propre, bob_loop extrait). E5-ter = chantier separe de
4-5 sessions, demarre par E5-ter-0.

