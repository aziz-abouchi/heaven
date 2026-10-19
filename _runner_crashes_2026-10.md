# Runner --run-tests : 3 crashes silencieux (2026-10-19)

## Constat

HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests
produit 3 CRASH/FAIL (Signal) silencieux : pas de TestFailed,
pas de Total pour ces fichiers. Le runner continue (fork par
fichier, test_runner.zig:318).

  tests/test_parser.hvn     -- crash apres 5 tests passes
  tests/test_hashmap.hvn    -- crash apres 6 tests passes
  tests/test_bigint_d20.hvn -- crash avant tout test

## Statut

- Pre-existant : confirme sur HEAD e65dc66 stashe (memes
  3 lignes, memes fichiers). Non cause par E3a (0bdc6e9).
- Contredit l'annonce '0 fail' du prompt de continuite
  2026-10-19. Regression silencieuse entre la derniere session
  verte et 7123886/e65dc66, ou baseline jamais re-verifiee.

## Hypotheses (non verifiees)

1. Parse silencieux : TestFailed sans Total (piege connu).
2. Signal (segfault/timeout) dans un test, catch par le fork.
3. let ... in a profondeur 0 dans test 'nom': (piege
   recidivant, cf. prompt continuite).
4. Regression exprStructuralEq sur les 3 fichiers (Sym qualifie,
   recidive 4x, H1).

## Action

Session dediee runner-triage. Un fichier a la fois :

  HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests \
    tests/test_parser.hvn 2>&1 | tail -30

Reproduire en isolation, capturer le signal (dmesg / exit code),
patcher ou documenter.

