# Runner --run-tests : 3 crashes Debug-only (2026-10-19)

## Constat

HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests
en build DEBUG (zig build sans -Doptimize) produit 3 crashes
CRASH/FAIL (Signal) silencieux : pas de TestFailed, pas de
Total pour ces fichiers. Le runner continue (fork par fichier,
test_runner.zig:318). Reproduits en isolation avec --run-test :

  tests/test_parser.hvn     -- SIGSEGV apres 8 tests (exit 139)
  tests/test_hashmap.hvn    -- SIGSEGV apres 8 tests (exit 139)
  tests/test_bigint_d20.hvn -- SIGSEGV avant tout test (exit 139)

## Statut (CORRIGE)

- Debug-only : zig build -Doptimize=ReleaseFast + --run-tests
  tests = 0 fail. Le prompt de continuite 2026-10-19 annoncait
  '0 fail' -- c'etait vrai en ReleaseFast, faux en Debug.
- Non causé par E3a (0bdc6e9) : vrai, mais trompeur. E3a n'y
  est pour rien du tout -- Debug crashait deja sur e65dc66.
- Cause racine non identifiee. Suspects : UB en Debug (pointeur
  non initialise, index hors borne non checke en ReleaseFast par
  hasard), ou alignement/stack. Commit suspect : 82b7835
  'bigint Debug-only + test-files ReleaseFast' -- le titre
  suggere que Debug est deja connu pour casser sur bigint.

## Regle de baseline (a rappeler)

Les 4 commandes du prompt de continuite sont a lancer en
ReleaseFast pour --run-tests :

  zig build -Doptimize=ReleaseFast           # 0
  zig build test                              # 0
  zig build -Doptimize=ReleaseFast
  HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests
                                              # fails=0
  zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall  # 0
  zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall          # 0

Noter : 'zig build test' est en Debug (tests Zig unitaires) et
doit rester vert en Debug. Seul --run-tests (runner Heaven) est
un baseline ReleaseFast.

## Action (optionnelle, hors chemin critique)

Triage Debug-only si priorise. Un fichier a la fois :

  zig build  # Debug
  HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-test \
    tests/test_bigint_d20.hvn

Ou : valgrind / ASan si dispo, sinon bisect sur 82b7835.
Priorite basse : ReleaseFast est la cible de prod et de CI.

## Extension 2026-10-20 : test_bigint_d20 crash aussi en ReleaseFast

`tests/test_bigint_d20.hvn` crashe (SIGSEGV) en `--run-test` isole
en ReleaseFast, sur HEAD **et** sur `10816ce` (avant `@tls_read`
dynamique). C'est **pre-existant**, pas une regression TLS.

Le fichier dit : "forte consommation memoire (175 Mo pour 2 tests),
le runner cree un subprocess par fichier -> budget memoire frais".
Voir `docs/spec/_bigint_d20_stack.md` (D20).

Les 3 crashes Debug-only connus (`test_parser`, `test_hashmap`,
`test_bigint_d20`) s'etalent donc a 4 en ReleaseFast isole pour
`test_bigint_d20`. A investiguer en session `runner-triage` :
- stack overflow (bdiv/bmod recursif profond) ?
- ulimit memoire du shell ?
- OOM ?

Workaround CI : `--run-tests tests` sur l'ensemble passe (le runner
fork par fichier, un crash n'arrete pas la suite). En RF, total
visible = 1 fail (test_bigint_d20) mais le reste passe.

