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

Ces sujets vivent dans `docs/VISION.md` (à créer), pas dans la roadmap.

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
