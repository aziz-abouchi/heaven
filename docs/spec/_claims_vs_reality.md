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
| 5 | TCO O(1) mutuelle | **Détection + fusion prouvées** : `findTailSCCs` regroupe {even, odd}, `fuseTailSCCs` produit un scc_sym unique (`src/core/mir_tco_test.zig`, commit d1ceb7c). **Exécution équivalente : bloquée** par bug `cloneFunction` (mir.zig:1475-1497, ne propage pas `fn_defs`). TCO compilé (QBE) : non testé. | ⚠️ Partiel (1+2 prouvés, 3 bloqué) |
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
| S5 | Multi-clauses `dispatch 0=0 \| ...` | exclu de `precompileUserFns` ; appel → `error.UnsupportedCall` (rejet explicite depuis `31b5ba1`) | G.25 |
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
Update 2 (2026-11-13): cloneFunction fix landed (4a483f7).
Pre-fusion execution works (even(10)=1, fac(5)=120 via executeLegacy).
Post-fusion execute crashes on uninitialized register — fuseTailSCCs
emits QBE-only ABI (tag@reg0, params@reg4+), incompatible with
executeLegacy. Level 3a blocked; level 3b (QBE run) untested.
Claim status: detection+fusion proven (1+2), execution blocked (3a/3b).
Preuves exécutables: `src/core/mir_tco_test.zig` (2 tests actifs, 1 neutralisé). Build: 425/426 pass. Bug kernel: `cloneFunction` ne propage pas `fn_defs`. Ticket séparé pour fix.<!-- HOLES-EVIDENCE 2026-11-13 -->

Claim #4 - three strata, two implemented:
  STRATUM 1 (SOLID): hole_runtime.zig inferHoleType arith->Int cmp->Bool
  STRATUM 2 (OK): HoleState.refine stores hole->expr mapping
  STRATUM 3 (ABSENT): no AST rewrite, @hole still yields -1 after refine
  Workaround: refine_tdd identity in core/std/tdd.hvn:6
  Status: PARTIAL (recording OK, substitution 0%).

