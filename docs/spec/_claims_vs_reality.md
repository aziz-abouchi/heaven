# Affirmations vs réalité — Heaven

> Registre des affirmations du livre / de la spec confrontées au code
> réel. But : éviter de confondre la **vision cible** avec l'**état du
> binaire**. Mis à jour au 2026-11-12 (commit `804ee84`).

## Statut du binaire

- **Version binaire** : `v0.1.0` (voir `heaven --version`)
- **Version livre** : parle de v0.5 / v0.6 comme « ACTUEL »
- **Écart** : le livre décrit la vision cible, pas le binaire livré

## Tableau affirmations vs réalité

| # | Affirmation (livre/spec) | Réalité (code/tests) | Statut |
|---|---|---|---|
| 1 | HoTT cubique natif (Path, HIT, univalence) | Kernel gère `refl`/`eq` Peano seulement (`kernel.zig`, ~780 l.) | ❌ Spec |
| 2 | TCB CIC complet (quotients, proof irrelevance, Prop imprédicatif) | Prop imprédicatif : 0 %. Proof irrelevance : 0 %. Quotients : prototype isolé | ❌ Partiel |
| 3 | QTT zero-GC (Perceus) | QTT runtime vérifié (`LinearViolation` testé), pas de FBIP/Perceus dans les backends | ⚠️ Runtime seul |
| 4 | Holes + refine interactif (`:hole`, `:refine`) | `@hole` sentinelle `-1`, `refine_tdd` = identité déguisée. Vrai AST refine : 5 % | ⚠️ Prototype |
| 5 | TCO O(1) mutuelle | **Détection + fusion + exécution MIR et QBE natif prouvées** : `findTailSCCs`, `fuseTailSCCs`, exécution MIR (`mir_tco_test.zig`) et binaire natif QBE `even(2_000_000) == 1` (`test_mir_qbe.zig`) passent en pile O(1). | ✅ MIR + QBE |
| 6 | Versioning v0.5 / v0.6 « ACTUEL » | Binaire `v0.1.0` | ❌ Décalage |
| 7 | MPST généralisé | Runtime seul pour acteurs (`protocol.hvn`). Streams, réseau, UI : 0 % | ⚠️ Acteurs seulement |
| 8 | HKT Rank 1 (`Strategy ∀h`) | ✅ Implémenté et testé (O2.2) | ✅ |
| 9 | HIT Rank 1 (Interval, S¹, ‖A‖) | Kernel : rien. Spec : seulement | ❌ Spec |
| 10 | `run` multi-message fiable | 1 message fiable (STATUS.md:303). `dispatch_from` = contournement documenté | ❌ Bug |
| 11 | Actor mailbox natif | ✅ mailbox multi-msg résolu (`04de61c`, 5 msgs = 15). Thunks top-level fixés (`9a301c7`). | ✅ Stable |
| 12 | Backpressure (mailbox bornée, streams) | 0 %. Mailbox illimitée. Streams sans push/pull | ❌ Absent |
| 13 | Erreurs pédagogiques (expected/found/suggestion) | `heaven check` : arity (`arity mismatch: 'add' attend 2, reçu 1`) + syntax (tree-sitter ERROR) + literal + lambda. Messages clairs sur 4 cas, cryptiques ailleurs | ⚠️ Partiel |
| 14 | `heaven check` = typechecker | ✅ syntax (exit 1, ERROR tree-sitter) + arity (`fn_arity`, `msg_pool`). Pas d'unification complète (Typer minimal). | ⚠️ Partiel |
| 15 | `heaven test` tous les tests | Oui, si on utilise `heaven test tests/`. `heaven run` = 1 test | ⚠️ Piège |

## Ce qui **est** vrai (livré et testé)

- Solidité des preuves & statut explicite : enum `Status` à 7 valeurs (`[PROVED]`, `[SOLVED]`, `[EQ]`, `[AXIOM]`, `[TRUSTED]`, `[LEGACY]`, `[ ]`), `verified:bool` supprimé (`5f05a37`), discriminateurs `false_theorems.sh` + `mcp_soundness.sh` (avec `heaven_prove` multi-ligne `d123b96`) bloquants en CI
- Livre & REPL : 151/151 commandes doctest passent en CI bloquante (`de1b635`), continuation multiligne REPL (`bc8f239`)

- OTP core : GenServer, links, trap_exit, 3 stratégies superviseurs, event-driven (27 tests)
- MPST runtime pour acteurs : `mpst_trace`, `check_dual`, `check_protocol` (3 tests)
- TDD v1 : `@hole`, `@is_hole`, `@assert_no_hole`, `refine_tdd`, `match1..4` (12 tests)
- Hab MVU : lens `Lens(State, MvuState)`, `dispatch_from`, superviseur n enfants (10 tests)
- Check v1 : arité, literal-as-function, partial-lambda (4 tests)
- HKT Rank 1 : `Strategy : ∀h. (h, Children) → Children` (O2.2)
- Endofunctor superviseur : `S : End(Children)`, `S∘S = S`, `|S(c)| = |c|` (O2.1, O2.3)
- Lois optiques : `view(set(v,s))=v`, `set(view(s),s)=s` (O4.1)

## Règles de lecture du livre

1. Toute affirmation **non testée** dans `tests/` est **spécification**, pas réalité.
2. Toute mention de version (v0.5, v0.6) est **roadmap**, pas binaire.
3. Les ⚠️ sont des **prototypes partiels** — utilisables mais instables.
4. Les ❌ sont des **specs non implémentées** — ne pas s'attendre à ce qu'elles marchent.

## Comment mettre à jour ce document

Avant toute session qui implémente une feature du livre :
1. Vérifier si l'affirmation est déjà dans le tableau
2. Si oui : noter le nouveau statut (❌ → ⚠️ → ✅)
3. Si non : ajouter une ligne avec statut initial

Ce document est la **vérité terrain** pour planifier — pas le livre.


## Selfhost natif (mise à jour 2026-10-30)

| # | Affirmation | Réalité | Statut |
|---|---|---|---|
| S1 | `bin/heaven.hvn` → ELF natif | QBE 1.2 + cc -lc, 18 Ko | OK |
| S2 | `@puts`/`@printf`/`@getenv`/`@strcmp` | extern_call glibc | OK |
| S3 | `@argv N` (ABI SysV) | wrapper `l $main(l, l)` | OK |
| S4 | Dispatch CLI | `@strcmp` + cascade `if` (V0.6) | OK |
| S5 | Multi-clauses `dispatch 0=0 \| ...` | **Compilées** par MIR (variables, entiers, jokers, gardes, bool, ADT n-aires) en QBE et WASM ; vérifié par `tests/diff` 12–20 (interpréteur = QBE = wasmtime). Rejet explicite (`UnsupportedCall`) seulement hors de ces formes (chaînes, flottants) | ✅ MIR + QBE + WASM |
| S6 | `@argv` dans fn user | segfault (`argv_sym` local) | G.33 |
| S7 | `@strcmp "str"` dans fn user | `undef fN` (`str_pool` local) | G.34 |
| S8 | WASM selfhost (`mir_wat`) | primitives non émises | TODO |
| S9 | `heaven_eval.hvn` complet | 71 lignes (toy) | TODO |

Voir `docs/book/src/39-selfhosting.md` et annexe G (G.25 → G.34).

## heaven_eval + WASM selfhost (mise à jour 2026-10-30 nuit)

| # | Affirmation | Réalité | Statut |
|---|---|---|---|
| E1 | `heaven_eval.hvn` évalue (+ 1 2) | VInt 3 via HP.lex + HE.eval_file | OK |
| E2 | Listes/pairs | cons/head/tail/pair/fst/snd | OK |
| E3 | `string_concat` | VStr "ab" (AST hardcodé) | OK |
| E4 | `λ`/`fn` closures | VLam1 (AST hardcodé) | OK (AST) |
| E5 | `λ`/`fn` via `.hvn` source | `ArityMismatch` (G.39) | ❌ Parser |
| E6 | `let` | non géré (G.38) | ❌ Parser |
| W1 | `compile-wasm main=42` | wat2wasm --enable-tail-call + node → 42 | OK |
| W2 | `compile-wasm (+ 1 2)` | → 3 exécutable | OK |
| W3 | `@puts` en WASM | `extern_call` émis → `unreachable` dans le WAT (trap runtime, pas rejet à la compilation). WASI `fd_write` absent | ❌ TODO |

Voir `docs/book/src/40-heaven-eval.md` et annexe G (G.35 → G.39).


## Contrat d'appel MIR → backend (2026-11-12)

Trois issues distinctes pour un `Instr.call_user`, selon la cible :

| Cible | Résolution | Comportement backend |
|---|---|---|
| `fn_defs[name]` | lambda compilée | émise (QBE : `call $fN` ; WAT : `call $fN`) |
| `engine.fns[name]` (fn utilisateur hors `fn_defs`) | exclue par `precompileUserFns` (multi-clause, garde, pattern non-sym) | **`error.UnsupportedCall`** (`31b5ba1`) |
| nom inconnu (ni fn, ni `@xxx`) | arm `compileExpr.apply` épuisé | **`error.UnsupportedOp`** à `compileExpr` |

Et une issue distincte pour `@xxx` :

| `@xxx` (externe) | `.extern_call` émis | QBE : link libc ; WAT : `unreachable` (trap runtime, pas rejet) |

Voir `docs/MIR_CONTRACT.md` §6, §8 (source de vérité).

| 15 | Selfhost = compilateur Heaven | briques (parse+eval) partiellement en .hvn, PAS un compilateur. head-18 passe, full-file cyclique. | WIP |
| 16 | heaven check = typechecker | syntax + arité (48/148 faux positifs tree-sitter). Pas d'unification. | Partiel |


<!-- TCO-MUTUAL-EVIDENCE 2026-11-13 -->
Update 2 (2026-11-13) [SUPERSEDED by Update 5, see bottom of file - 464a344 fixed level 3a]: cloneFunction fix landed (4a483f7).
Pre-fusion execution works (even(10)=1, fac(5)=120 via executeLegacy).
Post-fusion execute crashes on uninitialized register — fuseTailSCCs
emits QBE-only ABI (tag@reg0, params@reg4+), incompatible with
executeLegacy. Level 3a blocked [SUPERSEDED - see Update 5]; level 3b (QBE run) untested.
Claim status: detection+fusion proven (1+2), execution blocked (3a/3b).
Preuves exécutables: `src/core/mir_tco_test.zig` (2 tests actifs, 1 neutralisé). Build: 425/426 pass. Bug kernel: `cloneFunction` ne propage pas `fn_defs`. Ticket séparé pour fix.<!-- HOLES-EVIDENCE 2026-11-13 -->

Claim #4 - three strata, two implemented:
  STRATUM 1 (SOLID): hole_runtime.zig inferHoleType arith->Int cmp->Bool
  STRATUM 2 (OK): HoleState.refine stores hole->expr mapping
  STRATUM 3 (ABSENT): no AST rewrite, @hole still yields -1 after refine
  Workaround: refine_tdd identity in core/std/tdd.hvn:6
  Status: PARTIAL (recording OK, substitution 0%).

<!-- QTT-EVIDENCE 2026-11-13 -->

Claim #3 - two strata, one implemented:
  STRATUM 1 (OK): LinearChecker src/core/types.zig:148, Quantity one/zero/many
  STRATUM 2 (OK): shell :qtt integration, commands.zig:871, test_qtt_linear.hvn 8 pass
  STRATUM 3 (ABSENT): no Perceus/FBIP in src/*.zig, only docs/_memory.md and _backend_strategy.md mention it
  Workaround: none - runtime checker verifies declarations, no drop-reuse optimizer
  Status: PARTIAL (runtime tracking OK, zero-GC Perceus not implemented).

<!-- CIC-EVIDENCE 2026-11-13 -->

Claim #2 - CIC substantially implemented (PASS B used wrong path):
  STRATUM 1 (OK): Sort.Prop in typechecker.zig:47, ast.zig:56
  STRATUM 2 (OK): Proof irrelevance active in conversion.zig:23-26
    reactivated 2026-10-19, tested by test_proof_irrelevance.zig
  STRATUM 3 (OK): Quotients primitive in ast.zig:56
    tested by test_quotient.zig and test_transform.zig
  STRATUM 4 (OK): Prop impredicative, typechecker.zig:46-47 (codomain Prop returns Prop)
  Status: FULL (4 of 4 components implemented and tested).
  Meta: PASS B grep-ed src/core/kernel.zig (does not exist).
    Real path is src/kernel/kernel.zig. Other claims may be under-reported.

<!-- HOTT-EVIDENCE 2026-11-13 -->

Claim #1 - HoTT facade only, no kernel native:
  STRATUM 1 (OK): lib/hott/path.hvn exists, covered by test_hott_path.hvn (14+ tests pass)
  STRATUM 2 (OK): integer encoding - path_witness returns Int, refl=0, trans=sum
  STRATUM 3 (ABSENT): no Path type in src/kernel/*.zig
  STRATUM 4 (ABSENT): no univalence, no HIT, no higher inductive types
  STRATUM 5 (ABSENT): kernel refl is CIC Eq-refl (typechecker.zig:166), not HoTT Path-refl
  Status: FACADE (rank-1 simulated paths, kernel native HoTT absent).
  Meta: PASS B was accurate for claim 1 (correctly reported 0 hits).


Update 3 (2026-11-13) - fuseTailSCCs ABI mismatch precise diagnosis:
  BUG 1: wrapper wrapWithSccCall (mir.zig:378-408) sends args=[params..K-1, tag@K]
    body fuseTailSCCs (mir.zig:570-574) expects [tag@0, zero@1, cond@2, const@3, params@4+]
  BUG 2: wrapWithSccCall shared by fuseTailPairs (L499-500) and fuseTailSCCs (L637)
    changing wrapper ABI breaks pairs; separate wrapper needed
  BUG 3: mir_qbe.zig has 0 mention of scc_sym - backend consumption unclear
    comment L413-414 claims QBE TCO rewrites call_user to jmp @b0 but no trace in backend
  Status: fuseTailSCCs emits MIR that is broken at wrapper boundary.
    Test 3 stays neutralized. Fix needs: align ABI + separate wrapper for pairs/scc +
    verify QBE consumption. Estimated: dedicated session, production code.


Correction (2026-11-13) - 7c0495d impact claim was wrong:
  Commit message claimed four test files (test_hashmap 50, test_list 46,
  test_bitstrings 42, test_dns_v1 40) already exceeded 32 clauses and were
  being silently truncated at load.
  That audit was WRONG. Correct scan (regex that skips test/let and distinguishes
  == from =) across 202 .hvn files in lib/, tests/, core/:
    max clauses for a single function = 19
    zero functions > 32 clauses
  No .hvn was actually losing clauses before 7c0495d.
  The fix remains valid as defensive hardening:
    - silent truncation in addClause was a real latent bug
    - 3 inline tests prove the new explicit-error behavior
    - [32]->[64] gives margin for future growth
  But the "four files were truncated" narrative is incorrect.


Correction (2026-11-13) - Update 3 ABI mismatch diagnosis was WRONG:
  Update 3 claimed wrapper and body had mismatched ABI: "wrapper sends
  [params..K-1, tag@K], body expects [tag@0, zero@1, cond@2, const@3, params@4+]".
  Full trace shows this is consistent: body param_regs = [def0.param_regs+4..., 0],
  wrapper sends [def.param_regs..., tag_r]. executeLegacy maps arg[i] to
  param_regs[i], so params land in [4..] and tag lands in [0]. Coherent.
  The real crash is index 0xAAAAAAAB on values, i.e. an undefined reg read
  as call_user arg, in executeLegacy where cu.args have no bounds check.
  Suspected source: shiftInstr call_user path or copyBlocksForFusionN
  passing an undefined arg through. Under investigation.

Update 5 (2026-11-13) - fuseTailSCCs execution works
  Update 3 (1054e6e) said "ABI mismatch between wrapper and body". WRONG.
  Full trace: wrapper sends [def.param_regs.., tag_r], body param_regs =
  [def0.param_regs+REG_BASE.., tag_reg=0], executeLegacy maps arg[i] to
  param_regs[i]. Coherent.
  Real crash (index 0xAAAAAAAB) was cloneFunction shallow-copying:
    - clone shared call_user.args slice with parent fn_def.fn_mir
    - temp_mir.deinit() freed those shared slices
    - arena reclaimed last block, parent.args became 0xAAAAAAAA
    - next clone read 0xAAAAAAAA + reg_off = 0xAAAAAAB5 as arg -> OOB
  Fixed in 464a344: deep-copy args/incoming in cloneFunction.
  Verified in 8e4c54f: even(3)=0 and odd(10)=0 discriminators prove real
  recursion (not accidental cmp(undef==0)=true).
  Claim #5 status:
    Level 1 (findTailSCCs groups {even, odd}):        PROVEN
    Level 2 (fuseTailSCCs produces scc_sym):          PROVEN
    Level 3a (executeLegacy before/after = same):     PROVEN
    Level 3b (QBE compiled equivalence):              UNTESTED
  Gate ddd6446 (HEAVEN_SCC_FUSION opt-in, default off) STAYS OFF until
  level 3b is proven on a QBE-compiled binary. The 3a result is oracle-
  level only; production trust requires running through QBE.

<!-- AMBITIONS-VS-CLAIMS-2026-11-16 -->
**Ambitions vs claims (2026-11-16)**

Deux ambitions déclarées dans README et ROADMAP ne sont pas des claims :

- **π-calcul (canaux mobiles)** : voir ligne 23 (MPST généralisé — runtime seul). Aucun composant π-calcul dans `src/`. La vérification de conformité MPST dans `elab.zig` n'est pas raccordée à `mpst.zig` (import neutralisé).
- **Cubical HoTT** : voir ligne 17 (HoTT cubique natif — Spec) et le bloc `HOTT-EVIDENCE` (2026-11-13) qui distingue la façade `lib/hott/path.hvn` (rang-1, witness entier) du noyau natif. Aucun type `Path` natif dans `src/kernel/`.

Conditions cumulatives pour tout futur claim cubical : soundness du noyau (aucun `verified` sans validation), noyau CIC consolidé, `Path` natif avec sémantique effective. Voir aussi chapitres 22 et 41 du livre.

<!-- A1-REPRODUCIBILITY-EVIDENCE 2026-11-17 -->
**A1 — Build reproductible. Mesures du 2026-11-17, Guix / Zig 0.15.2.**
**HEAD local `e039106` != `origin/main` `93536ff`.** Le depot local porte
des commits non pousses, dont un qui a COMMITTE la troncature de ce
registre (237 -> 12 lignes). Un `git restore` rendait donc la version
tronquee : la perte etait dans l'historique, pas seulement dans l'arbre
de travail. Registre reconstruit le 2026-11-17 depuis `origin/main`.

Baseline sur la copie de travail complète :
- `zig build test --summary all` : 98/98 steps, **457/458 tests, 1 skip**
- `zig build test-regression` : 98/98, « Memory clean: No leaks detected »
- `zig build -Dtarget=wasm32-freestanding` : succès en Debug **et** ReleaseSmall
- README (docgen 2026-11-16) annonce 456 : écart de 2, docgen à régénérer

| # | Affirmation | Réalité mesurée | Statut |
|---|---|---|---|
| A1.1 | Un clone frais compile (Quickstart = `zig build`) | FAUX. `vendor/*` gitignoré ; seuls tree-sitter-heaven, tree-sitter-pie et vendor/cache/qbe-1.2.tar.xz sont trackés. Clone nu → `file_hash FileNotFound`. Le bootstrap réel est `bash build.sh`, absent du Quickstart | ✅ Corrigé 2026-11-17 (doc + garde build.zig) |
| A1.2 | Dépendances vendor épinglées | build.sh clonait master pour tree-sitter, -c, -zig, tinycc, libdatachannel | ⚠️ Partiel : tcc épinglé, reste à faire |
| A1.3 | Provenance du runtime tree-sitter identifiable | NON. Pas de `.git`. Makefile `VERSION := 0.27.0` mais sha256(lib.c)=4e28f87e… ≠ tag v0.27.0 (a9830f5a…) → snapshot de master entre deux releases. ABI 15 / min 13 face à des parsers ABI 15 : compatible par chance, pas par contrat | ❌ À ré-épingler |
| A1.4 | tree-sitter-c / -zig versionnés | NON. Copies nues (`src/` seul, aucun package.json). parser.c 3 872 019 o et 5 147 602 o | ❌ À vendored ou épingler |

**Claim #5 (TCO mutuelle) — niveau 3b : PROUVÉ localement le 2026-11-17.**
Le seul skip de toute la suite est `src/syntax/lower_test.zig`
(`if (true) return error.SkipZigTest`, syntaxe `range` non lowered ; plan
de levée en 4 étapes déjà documenté dans le fichier). Les deux tests
appelant `runNative` — oracle M3 et `even(2_000_000) == 1` natif — sont
donc passés. Update 5 marquait 3b « UNTESTED » : dépassé. Reste à
trancher la bascule du gate `HEAVEN_SCC_FUSION` par défaut.

**Commentaire de gate périmé.** `qbe_cmd.zig` justifiait le gate par
« broken wrapper ABI (claim #5 Update 3) ». Update 5 rétracte Update 3 :
ABI cohérente, bug réel = shallow-copy de `cloneFunction`, corrigé en
`464a344`. Commentaire réécrit le 2026-11-17.

**`test-files` ECHOUE — 14 fuites (mesure 2026-11-17).**
`zig build test-files` -> **exit=1**, avec **14** `MEMORY LEAK DETECTED!`
(compte exhaustif). Le « deux fuites » d'une premiere lecture venait d'un
`tail -40`, pas d'un comptage. Toutes les assertions passent ; le process
echoue sur les fuites. Les fuites SONT bloquantes.

**Ecart de claim associe.** README et docgen annoncent
`test_files = 1342/1342`. Vrai des assertions, faux de la commande :
docgen ne consulte pas le code de retour. Le correctif est dans
`scripts/docgen.py`, pas seulement dans le README.

**Traces non symbolisables.** `zig build test-files` sans
`-Doptimize=Debug` ne produit pas d'exe Debug : passer le flag a LA MEME
invocation, pas a une invocation precedente.

A4 est donc plus large que « reactiver le leak check » : il faut attribuer
les 14 fuites, les corriger, et rendre docgen sensible au code de retour.

**Deux hypothèses fausses — à ne pas re-chasser.**
1. « `cc` n'existe que comme alias shell, invisible pour execvp » : FAUX.
   `env cc --version` → GCC 16.2.0, et `~/.guix-profile/bin/cc` est un
   symlink réel vers gcc-toolchain-16.2.0. L'alias bash est redondant.
2. « v2f (unification modulo arithmétique) est le chantier prioritaire » :
   FAUX. `src/core/unify.zig` est l'unificateur kanren legacy sur
   Matrix/BobId, pas le chemin des types dépendants (`kernel/` + `elab`).
   Priorité fixée par ROADMAP session 49 : Phase A, puis voie C.

<!-- COVERAGE-AND-DOCGEN-EVIDENCE 2026-11-17 -->
**Couverture réelle de `test-files` et intégrité de docgen (2026-11-17).**

| # | Affirmation | Réalité mesurée | Statut |
|---|---|---|---|
| C1 | `test-files` couvre `tests/*.hvn` | PARTIEL. `DEBUG_SKIP_FILES` (`test_runner.zig:307-318`) écarte 7 noms **en Debug seulement** (`shouldSkipDebug` retourne false hors Debug). 6 existent, `test_web_ontology.hvn` est une entrée fantôme. La raison EST documentée : SIGSEGV intermittent Debug-only, auto-généré 2026-10-27, cf. `docs/spec/_runner_crashes_2026-10.md`. Défaut réel : aucun avertissement au runtime, et le mode par défaut de `zig build` étant Debug, l'invocation par défaut couvre 6 fichiers de moins que le chiffre du README | ⚠️ Couverture réduite non divulguée |
| C2 | Une seule mécanique d'exclusion | NON. Deux : `DEBUG_SKIP_FILES` (Zig, Debug-only, raison documentée) et `scripts/test_all_hvn_known_fails.txt` (script shell, raisons documentées). Elles ne se recouvrent pas et ne se consultent pas | ⚠️ À réconcilier |
| C3 | Le contrôle de fuite est par fichier | NON. Il est par évaluation : les verdicts apparaissent entre deux tests d'un même fichier. 128 clean + 14 leak = 142 événements, pas 142 fichiers | 📌 Note de méthode |
| C4 | docgen publie des chiffres mesurés | NON. Trois défauts corrigés : `sh()` jetait le returncode ; `test_regression = f"{n_reg}/{n_reg}"` était une tautologie incapable de rapporter un échec ; fuites non comptées. docgen refuse désormais de publier sur suite rouge | ✅ Corrigé |

**14 événements de fuite sur 12 fichiers** : test_json_v1 (×2), test_hkt_v1a (×2),
test_propagator, test_parse_infix, test_meta_if, test_effects_rec,
test_continuations, tdd_hole_2, otp2_rest_for_one_prefix,
otp2_one_for_one_sibling, otp2_inv_rest_for_one, o4_sup_one_a. Transversal :
cause commune probable dans le runtime, pas 12 bugs indépendants.

**Concurrence d'écriture.** Une seconde session commit et pousse sur `main`
toutes les 3-5 min (E1.2 → E2.2, 17:04→17:32). Le commit `ecc4e01` a écrasé
ce registre (237 → 12 lignes) et l'a poussé. Reconstruction depuis
`origin/main` d'avant `ecc4e01`. Deux sessions sur un même dépôt : tout
travail non commité peut être absorbé ou détruit.

**Cause du `MissingDebugInfo`.** `build.zig` posait `.strip = true`
**inconditionnellement** sur le module de l'exécutable principal
(`src/main.zig`), Debug compris. Aucune DWARF, donc le
GeneralPurposeAllocator ne pouvait pas symboliser les fuites. Seule
section « debug » restante : `.gnu_debuglink`. Corrigé le 2026-11-17 :
`.strip = optimize != .Debug`.

**Dette corrélée à traiter comme un seul chantier.** Les 6 fichiers
écartés le sont pour SIGSEGV intermittent en Debug, blanchis le
2026-10-27 et jamais corrigés. Les 14 fuites sont mesurées dans ce même
mode. Corruption mémoire et fuites dans un même runtime ne font
probablement pas deux chantiers. Le census des fuites en Debug est
incomplet : les 6 fichiers écartés n'y sont pas comptés.

<!-- A4-CLASS-INSTANCE-EVIDENCE 2026-11-17 -->
**Fuites class/instance et dette `raw_alloc` (2026-11-17).**

56 allocations perdues, classées par site d'allocation. Trois catégories
distinctes, à ne pas traiter ensemble :

| Catégorie | Sites | Nombre | Statut |
|---|---|---|---|
| Clés class/instance non libérées | `heaven_expr.zig:1044`, `:1054` (stockage) + `engine_expr.zig:507-508` (deinit libère buckets mais pas clés) | 5 | ✅ Corrigé par libération explicite des clés |
| Magic `raw_alloc` sans libérateur | `engine_expr.zig:2008` | 2 | ⚠️ Dette documentée (TODO dans le code) |
| Hash map interne (bucket allocation) | `hash_map.zig:1478` | 1 | Effet collatéral de la catégorie 1 |

**API `StringHashMapUnmanaged.deinit`** : libère les buckets, pas les clés
string. Ce n'est pas un bug de l'API, c'est son contrat — mais Heaven
le méconnaissait en stockant des `[]const u8` dupés sans les libérer
explicitement.

**Hypothèse rejetée — pas de mismatch d'allocateur.** `Heaven.init` fait
`Engine.initTest(allocator, …)` : `self.engine.allocator == self.allocator`.
Pas d'UB à la ligne 1044 de `heaven_expr.zig`. Un patch d'uniformisation
aurait été correct mais pour la mauvaise raison.

**Dette `raw_alloc` à traiter séparément.** Le magic alloue via
`engine.allocator.alloc(u8, sz)` et le commentaire dit `TODO` pour
`raw_free`. Ce n'est pas une fuite accidentelle : c'est une absence de
libérateur symétrique dans le runtime. Le chantier correct nécessite
un magic `@raw_free` + un tracker des buffers vivants + une spec. Hors
scope du fix A4 immédiat.

**Dette corrélée toujours ouverte : 6 fichiers blanchis pour SIGSEGV
intermittent Debug-only** (cf. `DEBUG_SKIP_FILES` + `_runner_crashes_2026-10.md`
depuis le 2026-10-27, jamais corrigés). La corruption mémoire Debug et
les fuites partagent le même runtime ; une fois les leaks closes,
relancer les 6 fichiers blanchis est le prochain chantier mémoire.

<!-- SESSION-CLOSURE-EVIDENCE 2026-11-17 -->
**Clôture de session (2026-11-17, 17:00→21:00).**

Commits atterris sur `main` :
- `1486238` : DWARF en Debug (`.strip = optimize != .Debug`) — permet de
  symboliser les fuites du GPA
- `cacfd8a` : A1 (bootstrap explicite, TCC épinglé, garde vendor dans
  build.zig) + docgen non tautologique (suppression du `N/N` tautologique,
  capture du returncode, refus de publier sur suite rouge)
- `3cdca7d` : A4 class/instance (itérateur explicite dans `Engine.deinit`,
  8 → 3 fuites sur 12 fichiers transversaux)

Mesure finale : `zig build test-files` → exit=1, **3 fuites** (toutes
`raw_alloc`, dette documentée TODO). Suite de tests Zig : 457/458.

**Dettes formalisées (plus inconnues) :**

| ID | Dette | Effort | Priorité | Ticket |
|---|---|---|---|---|
| D-SIGSEGV | ~~6 fichiers blanchis~~ -> **0 SIGSEGV** (3 réintégrés : `test_bigint`, `test_heaven_eval_prims`, `test_mcp` ; 2 attribués à `D-RAWALLOC`, 1 `TestFailed` connu `test_bigint_d20`) | 3-5 sessions | Fermé / Reclassé | Fait |
| D-RAWALLOC | ~~Magic `raw_alloc` sans `raw_free` symétrique~~ -> **RÉSOLU** (`Engine.raw_buffers` libère les buffers vivants dans `deinit` ; `test_hashmap` et `test_lexer` réintégrés, 0 leak) | 2-3 sessions | Fermé | Fait |
| D-PIN | tree-sitter-c, tree-sitter-zig, libdatachannel non épinglés dans `build.sh` | 1 session | Moyenne (reproductibilité) | Cloner à tag précis, sha256 dans manifest |
| D-DOCGEN | ~~`test_files_count = 148`~~ -> **RÉSOLU** (`README.md` aligné sur 150 `.hvn` réels) | 30 min | Fermé | Fait |
| D-COVERAGE | ~~`DEBUG_SKIP_FILES` sans avertissement~~ -> **RÉSOLU** (log runtime + note `README.md` + retrait entrée fantôme) | 15 min | Fermé | Fait |

**Dettes fermées cette session (ne plus y revenir) :**
- `MissingDebugInfo` : causé par `.strip = true` inconditionnel
- Fuite bucket hash_map résiduelle : disparue après le fix class/instance,
  à reclasser comme non-reproductible si réapparaît
- `HEAVEN_SCC_FUSION` gate : commentaire réécrit, diagnostic rétracté
- Registre de vérité : reconstruit depuis 12 lignes à 319+ lignes

**Hypothèses rejetées pendant la session (à ne pas re-chasser) :**
- `cc` alias shell (FAUX : symlink gcc-toolchain-16.2.0)
- v2f comme chantier prioritaire (FAUX : unify.zig est kanren legacy)
- Contrôle de fuite par fichier (FAUX : par évaluation)
- Mismatch d'allocateur class/instance (FAUX : self.allocator == self.engine.allocator)
- 14 fuites = 14 allocs (FAUX : 56 allocations perdues sur 14 verdicts)

<!-- SKIPPED-FILES-RELEASEFAST-EVIDENCE 2026-11-17 -->
**Les 6 fichiers blanchis Debug passent en ReleaseFast (2026-11-17).**

Exécution manuelle en ReleaseFast (`zig build` sans `-Doptimize=Debug`) :

| Fichier | Résultat | Notes |
|---|---|---|
| test_bigint.hvn | ✅ 28/28 passed, 0 leaks | Aucun SIGSEGV |
| test_heaven_eval_prims.hvn | ✅ 16/16 passed, 0 leaks | Aucun SIGSEGV |
| test_mcp.hvn | ✅ 17/17 passed, 0 leaks | Aucun SIGSEGV |
| test_bigint_d20.hvn | ❌ error.NotDir | Bug de path (openDirZ), pas SIGSEGV |
| test_hashmap.hvn | ⚠️ MEMORY LEAK | raw_alloc:2020 sans libérateur |
| test_lexer.hvn | ⚠️ MEMORY LEAK | raw_alloc:2020 sans libérateur |

**D-SIGSEGV déclassé.** Le blanchiment Debug était justifié (SIGSEGV
intermittent), mais les fichiers sont exécutables en ReleaseFast.
La "dette runtime instable" est un problème **Debug-only**, pas un
défaut général. Prochaine action : relancer en Debug avec DWARF activé,
attribuer chaque crash à un site précis.

**D-RAWALLOC confirmé.** 2 des 6 fichiers blanchis fuient via
`engine_expr.zig:2020` (raw_alloc sans raw_free). Cohérent avec les 3
fuites mesurées plus tôt. Chantier de design : spec du magic + tracker.

**État final de la session :**
- 4 commits atterris sur main (1486238, cacfd8a, 3cdca7d, 302a511)
- Registre public : 319+ lignes, 7 blocs EVIDENCE, 5 dettes formalisées
- Suite Zig : 457/458 (1 skip : lower_test range)
- Suite Heaven : 96/98 steps (2 preexistants, pas introduits par nous)
- Fuites réelles : 3 (toutes raw_alloc, site 2020)
- Dettes restantes : 5 (D-SIGSEGV, D-RAWALLOC, D-PIN, D-DOCGEN, D-COVERAGE)
- Aucune nouvelle dette introduite

<!-- SESSION-2026-11-18-19 -->
Session 2026-11-18/19: double-free ferme (82c95e9, bbfbf56). MIR multi-clauses pas un verrou de correction (audit 2026-11-17 errone). Infixe unifie (5be0266). Parse collision ferme.

<!-- SESSION-2026-11-20 -->
## Session 2026-11-19/20 : fondations et soudure CI

| # | Affirmation | Réalité (mesurée) | Statut |
|---|---|---|---|
| T1 | Les fermetures capturent leur environnement | **Oui** : `closeFree` substitue les variables libres à l'évaluation d'un `.lambda` (K, S, flip, compose, trois niveaux, combinateur Z : `tests/test_closures.hvn`, 16 tests). Avant `1fd05af`, `.lambda => return id` : la capture échouait | ✅ Corrigé |
| T2 | Les backends natifs sont protégés des régressions silencieuses | **Oui, depuis la CI** : `tests/diff` (interpréteur vs QBE vs wasmtime, `REQUIRE_WASM=1`) et `reject.sh` tournent en CI. La régression `9d83aef` (QBE/WASM renvoyaient 0 partout) n'avait été attrapée que par ce harnais | ✅ En CI |
| T3 | Récursion profonde = erreur explicite | **Oui** (`d2dce28`) : `depth` repartait à 0 à chaque `evalFunction`, la garde `depth > 1000` ne voyait pas la récursion de fonctions ; la pile (64 Mo, frames Debug ~116 Ko) débordait vers 160 niveaux → SIGSEGV muet. Garde sur l'adresse de pile + pile 512 Mo : `sum_to 1200` OK, `sum_to 1000000` → `RecursionLimitExceeded` (`tests/depth_guard.sh`) | ✅ Corrigé |
| T4 | `test_bigint_d20` échoue sur main | Passe en Debug après T3 (mesuré) ; cause = pile, non analysée plus avant | ✅ Constaté |
| T5 | Pas de fuite à la redéfinition de `fn` | **Faux avant `2825280`** : `evalFnDef` dupliquait le nom à chaque `fn f` redéfini (`put` garde l'ancienne clé). Corrigé ; `tests/leak_guard.sh` (détecteur actif) | ✅ Corrigé |
| T6 | `:derive x^2 + 1` | **Faux avant `4f939f9`** : `splitExprVar` prenait `1` pour la variable (`expr="x^2 +"`). Corrigé, 8 cas testés | ✅ Corrigé |
| T7 | WASM gère le tas (`cons`, `pair`, ADT) | **Oui** (tas linéaire `a7754ab`, mesuré 2026-11-23) : `05-list`, `20-eq-adt-nary`, `21-builtin-heap` passent interpréteur = QBE = wasmtime. Un défaut silencieux subsistait : le tas WAT démarrait à 8 alors que le MIR distingue pointeur/constructeur nul par `>= 4096` → `20-eq-adt-nary` renvoyait 0 au lieu de 63 sans trap. Tas démarré à 4096 (`mir_wat.heap_base`), `WASM_UNSUPPORTED` vidé. Reste hors périmètre : `@puts` et les externs libc en WAT (trap explicite, exit 1) | ✅ Corrigé |
| T8 | Motifs sur chaînes (`f "ab" = 1`) compilés fidèlement | **Oui, interpréteur = QBE = wasmtime** (mesuré 2026-11-23, `tests/diff/23-str-pattern.hvn` = 321 : préfixes `"ab"`/`"abc"`/`""`/`"abd"`, chaîne passée en paramètre). QBE comparait déjà par contenu (`strcmp`, vérifié au désassemblage) via un désucrage textuel propre à `qbe_cmd` ; le désucrage MIR partagé ne les gérait pas, donc `compile-wasm` rejetait (`UnsupportedCall`). Désormais `(= (@strcmp arg "lit") 0)` dans `desugarClauses`, `const_str` en WAT = adresse d'un segment de données (tas après les données), `$__strcmp` en WAT. Hors périmètre : primitives `string_length`/`string_concat` (rejet explicite `UnsupportedExpr` en QBE et WASM), flottants (l'interpréteur refuse `1.5 + 2.5` : `TypeError`) | ✅ Corrigé / ❌ TODO primitives |
| T9 | La compilation multi-clauses passe à l'échelle | **Non avant le correctif** (mesuré 2026-11-23) : `desugarClauses` émettait un `(if test corps reste)` par test, donc le reste de la chaîne était dupliqué à chaque test et recompilé : taille du WAT ×4 par +2 clauses (k=14 : 1 049 463 lignes, k=4 : 1 911), `compile-wasm lib/heaven_parse.hvn` tué par OOM à 6 Go. Une seule condition 0/1 par clause et un seul `if` : k=40 → 3 511 lignes, linéaire. Tests `tests/diff/24-many-clauses` (30 clauses + garde) et `25-many-adt-clauses` (20 constructeurs), rouges avant (échec mémoire sous 3 Go), verts après | ✅ Corrigé |
| T10 | `compile-qbe`/`compile-wasm` compilent une source multi-lignes | **Oui** (mesuré 2026-11-23) : accumulation par indentation dans `parseLastExpr` de `qbe_cmd.zig` et `wasm_cmd.zig` (alignée sur `import.zig`), avec libération des clés/valeurs dupliquées (`pending`, `str_consts`, `stmt_buf`). Source multi-lignes validée en QBE (`42`) et WAT ; fichier sans expression rejeté par `NoExpression` | ✅ Corrigé |
| T11 | Le lexeur Heaven (`lib/heaven_parse.hvn`) se compile et s'exécute comme l'interpréteur | **Oui** (mesuré 2026-11-25) : `tests/selfhost_lexer.sh` compte les jetons de 4 entrées, interpréteur = QBE = wasmtime (ex. `"(+ 1 (* 22 3))"` → 9). Rendu possible par : `peek_byte`/`string_ptr`, `raw_alloc`/`raw_free`/`poke_byte`/`string_of_bytes` (QBE : malloc/free ; WAT : allocateur bump, `raw_free` no-op → fuite mémoire à long terme), `let nom val corps` sans parenthèses abaissé par le MIR (la forme parenthésée l'était déjà), et clauses sans `_` finale (T12) | ✅ Corrigé |
| T12 | Une fonction multi-clauses sans clause finale « attrape-tout » est compilable | **Oui depuis 2026-11-25**, politique modifiée : avant, rejet (règle « pas de valeur inventée »), ce qui bloquait les fonctions exhaustives naturelles (`toks_rev`, `zlen`). Désormais le désucrage termine la chaîne par `@abort` : si aucun motif ne correspond, QBE meurt (exit 134), WASM trappe (exit 1), sans rien imprimer, comme l'erreur de l'interpréteur. `reject.sh` vérifie cette mort bruyante (au lieu du rejet) ; test unitaire inversé ; `tests/diff/31-exhaustive-adt`. Hors périmètre : fonction à une seule clause avec garde (rejet explicite) | ✅ Corrigé (politique à valider) |
| T13 | L'assert intermittent « double-mapped pages » du DebugAllocator vient de la pile à 512 Mo | **Non** (mesuré 2026-11-25, machine de l'auteur et bac à sable) : relever `RLIMIT_STACK` à l'exec ne change rien (17/20 échecs), l'ajout d'un re-exec non plus (échec chez l'auteur). Le déclencheur est `retain_metadata = true` dans le `GeneralPurposeAllocator` de `main.zig` : `compile-qbe 02-fib`, 20 lancers, 13-17/20 échecs avec, 0/20 sans (ASLR ou non). Mécanisme exact non élucidé (code de l'allocateur non lu). Perte acceptée : diagnostic use-after-free des gros blocs libérés ; la détection de fuites reste active (`leak_guard.sh`) | ✅ Corrigé (`dfe4fea`) |
| T14 | Les motifs de constructeurs imbriqués (`b1e8bde`) sont compilés fidèlement | **Non avant correctif** (mesuré 2026-11-26) : `f (N (L 0) r) = 100 ; f (N l r) = 1` appelé sur `(N (L 5) (L 1))` donnait interp = 1, QBE = 100 (littéral imbriqué jamais testé) ; chargements de champs avant le test pointeur/tag (crash sur ctor nullaire) ; profondeur 3 acceptée puis ignorée. **Oui après** : tests en étapes ordonnées, profondeur max 2 (au-delà : rejet), sonde 40 cas interp = QBE = wasmtime, `tests/diff/32-nested-ctor`, `reject.sh nested_ctor3` | ✅ Corrigé |
| T15 | Les gardes sur fonctions multi-clauses sont exclues de la précompilation car MIR ne les combine pas aux motifs (`58c4fd7`) | **Faux pour les gardes scalaires** : 18-eq-guard et 24-many-clauses (compilés fidèlement avant) passaient au rouge. **Vrai pour une garde citant une variable de champ de ctor** (non liée → valeur inventée : interp 10, QBE/wasm 11, mesuré). Correctif : `wrapFieldBinds` lie les champs pour corps et garde, exclusion supprimée ; sonde g1-g9 et `tests/diff/33-guard-ctor` : interp = QBE = wasmtime | ✅ Corrigé |

**Méthode** : seuls les chiffres exécutés sont notés « mesuré » ; les builds sont Debug (temps pessimistes). Hypothèses rejetées : « l'environnement n'est pas capturé » (la cause était `.lambda => return id`) ; « grep `unreachable` ⇒ WASM non supporté » (le prélude en contient toujours).

<!-- SESSION-2026-11-25-MATH -->
Session 2026-11-25: :integrate/:solve first-class (magic (integrate expr), etc.)

Fixed:
- cmdIntegrate/cmdSolve splitExprVar bug (same as :derive before bf8637c)
- 3 magics added (integrate, solve, expand) alongside derive/simplify

Known bugs (in math module, not wrapper):
- :integrate x^2 = (* x^2 x) + C, missing the /(n+1) division.
  Expected (x ^ 3) / 3, got x^2 * x (= x^3). Algo bug.
- :integrate x*x panics index OOB 6674 / len 483.
  Real crash, not just wrong output. Site in math.integrate.
- :expand (x+1)*(x+2) = (x + (* 1) (x) + 2), malformed output.
  parse/format bug, not algorithm.

These are pre-existing math bugs, surfaced by making :integrate a
first-class primitive. Not introduced by this session.


## Session 2026-11-26 — vérifications

> Mesures réelles, pas des affirmations. HEAD 63113a1.

- Diff interp/QBE/wasmtime : **32/32 OK** (`tests/diff/run.sh`), dont 21-nested_deep (motifs imbriqués 2 niveaux).
- Zig : `zig build test` vert. Core : **98/98** (`core/test_suite.hvn`).
- A1 clone neuf : `/tmp/heaven-main` @ 35488c1, `build.sh` + tests verts (2026-11-26). Pins : QBE 1.2 tarball cache tracké, TCC `0fb5430`.
- Bug WAT `__raw_alloc` (mismatch i64/i32) : **corrigé** à ≥35488c1 (`__bump` i32 + wrap/extend ; `__strcat` ne passe plus i32 à `__raw_alloc`). Les échecs 24/32/33 observés plus tôt venaient d'un exe périmé, pas du code.
- Stub IA `_a1_qbe_integration.md` (pipeline QBE→C inventé) : **supprimé** (2ed7d00).
- TODO perf mémoire Goose : enregistré dans `_memory.md` + renvoi ROADMAP:147-158 (Goose exclut closures → non transposable tel quel).
- **Gaps MIR ouverts** (précompile ; non bloquants pour les diff, bloquants self-hosting) : `raw_syscall6`, `poke_int64`, `force` (UnsupportedExpr), `smap_e_val` (UnsupportedOp).
