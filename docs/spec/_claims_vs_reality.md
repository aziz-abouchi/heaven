# Affirmations vs réalité — Heaven

> Registre des affirmations du livre / de la spec confrontées au code
> réel. But : éviter de confondre la **vision cible** avec l'**état du
> binaire**. Mis à jour au 2026-10-29.

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
| 5 | TCO O(1) mutuelle | TCO directe OK, mutuelle limitée par SCC dans MIR (STATUS.md:303) | ⚠️ Partiel |
| 6 | Versioning v0.5 / v0.6 « ACTUEL » | Binaire `v0.1.0` | ❌ Décalage |
| 7 | MPST généralisé | Runtime seul pour acteurs (`protocol.hvn`). Streams, réseau, UI : 0 % | ⚠️ Acteurs seulement |
| 8 | HKT Rank 1 (`Strategy ∀h`) | ✅ Implémenté et testé (O2.2) | ✅ |
| 9 | HIT Rank 1 (Interval, S¹, ‖A‖) | Kernel : rien. Spec : seulement | ❌ Spec |
| 10 | `run` multi-message fiable | 1 message fiable (STATUS.md:303). `dispatch_from` = contournement documenté | ❌ Bug |
| 11 | Actor mailbox natif | Bloqué par `run` multi-message + thunks top-level | ❌ Bug |
| 12 | Backpressure (mailbox bornée, streams) | 0 %. Mailbox illimitée. Streams sans push/pull | ❌ Absent |
| 13 | Erreurs pédagogiques (expected/found/suggestion) | `check-v1` : arity + literal + lambda. Messages clairs sur 3 cas, cryptiques ailleurs | ⚠️ Partiel |
| 14 | `heaven check` = typechecker | Dump AST tree-sitter, pas de vérification sémantique | ❌ Stub |
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
