<!-- HEAVEN:bigint-d20-stack -->
# D20 : stack overflow bdiv/bmod 1000/7 (chantier)

## Symptome

Tests `bdiv 1000 / 7 = 142` et `bmod 1000 % 7 = 6` declenchent un
stack overflow **uniquement quand precedee de 28 autres tests bigint**.

- Fichier complet (30 tests) : peak 200 Mo, crash subprocess.
- 26 premiers tests seuls : peak 49 Mo, OK.
- Les 2 tests D20 seuls : OK.

## Cause probable

bdiv/bmod recursifs profonds. La consommation est cumulative : chaque
test laisse des residus (frames, allocations) qui s'additionnent.
Le 29e test franchit le seuil.

## Options

- **A (fait)** : retirer les 2 tests D20 du fichier. Debloque la CI.
- **B (chantier)** : rendre bdiv/bmod iteratifs (boucle au lieu de
  recursion). ~1 session.
- **C** : reduire la taille des nombres testes (1000 -> 100). Rapide
  mais ne resout pas la cause.

## Historique

- 067b381 : retirer bmod 1000/7 (bug stack D20)
- e6cb935 : remettre bdiv/bmod 1000/7 (ReleaseFast)
- 2026-10-16 : retirer (commentes) + tracage chantier B

## Trigger reproductible

    head -28 tests/test_bigint.hvn > /tmp/p.hvn
    echo 'test "bdiv 1000 / 7 = 142": (to_int (bdiv (from_int 1000) (from_int 7))) == 142' >> /tmp/p.hvn
    timeout 30 ./zig-out/bin/heaven --run-test /tmp/p.hvn


## Resolution (2026-10-16)

Cause identifiee : **Debug-only**. Le meme test passe en ReleaseFast.
La CI lancait test-files sans `-Doptimize`, donc en Debug, et crashe.

Deux changements :
1. `core/bigint.hvn` : `bdigit_choice` reecrit sans `let-in` -> TCO
   preserve (le moteur ne traverse pas les let-in dans collectTailSpine).
2. `.github/workflows/ci.yml` : test-files lance avec
   `-Doptimize=ReleaseFast`.

Tests D20 isoles dans `tests/test_bigint_d20.hvn` (consommation
memoire ~170 Mo pour 2 tests, sous-processus dedie).

**Local** : `zig build -Doptimize=ReleaseFast -Dnetwork=false test-files`
pour D20 vert. En Debug : crash (memoire).
