# Fuzzer — design et crashes trouvés

**Date** : 2026-10-27
**Statut** : v1 livrée (mutation-based bash), 3 crashes trouvés.

## V1 — `scripts/fuzz.sh`

Mutation-based, 0 ligne Zig. Mute un corpus valide
(`tests/test_arithmetic.hvn`) par insertion de 20 octets `/dev/urandom`
à une position aléatoire. Lance `heaven --eval-file`, capture rc>128
(signal).

Usage : `./scripts/fuzz.sh [N] [corpus]`

## Crashes trouvés (30 itérations, 3 crashes)

Corpus : `tests/fuzz_crashes/`

- `crash_15_rc139.hvn` (444 octets) : SIGSEGV (rc=139).
- `crash_24_rc134.hvn` (444 octets) : SIGABRT (rc=134, panic Zig).
- `crash_29_rc139.hvn` (444 octets) : SIGSEGV (rc=139).

Mécanisme : tous sont des mutations de `tests/test_arithmetic.hvn`
(424 octets) par insertion de 20 octets urandom à des positions
différentes. Reproductibles (même input → même crash).

## Fix 1 : depth guard (2026-10-27)

Cause racine trouvée (gdb backtrace) : récursion infinie
`parseExpression ↔ parseSExpr` sur des identifiants non-ASCII.
Exemple minimal : `f = a é(g 0)` — `é(g 0)` tokenize en `["é(g 0)"]`,
puis `parseSExpr` rappelle `parseExpression` qui rappelle
`parseSExpr`, etc. ~1300 frames → stack overflow.

Fix : `parse_depth: u32` dans `ExprParser`, garde à 500 (bien
au-delà de toute expression raisonnable). `parseExpression` et
`parseSExpr` incrémentent/décrémentent, retournent
`error.InvalidInput` au-delà.

Les 3 crashes fuzzer renvoient maintenant `error.InvalidInput`
(ou autre erreur) au lieu de SIGSEGV/SIGABRT.

## Analyse (backlog session dédiée)

- Minimiser chaque crash (retirer octets jusqu'au minimum qui crashe).
- Localiser le site : parser, évaluateur, allocator ?
- SIGABRT = panic Zig (assert/unreachable) → message dans le stderr.
- SIGSEGV = accès mémoire invalide → gdb/addr2line.

## V2 (backlog)

- Générateur de grammaire Heaven (`core/std/fuzz_gen.hvn`) pour
  explorer les chemins profonds.
- Corpus plus large (tous `tests/*.hvn`).
- Harness Zig dédié (au lieu de `--eval-file`) pour réduire le bruit.
- Intégration CI optionnelle (job nocturne).

## Lien

Le fuzzer est le 3e outil du backlog (`_smocker.md`, `_quickcheck.md`).
Smocker et Quickchecker sont 100% Heaven ; le Fuzzer est hybride
(driver bash/Zig + corpus valide généré en Heaven).
