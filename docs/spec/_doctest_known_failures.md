# Doctest book - known failures (2026-11-13)

The CI step `Doctest book` runs `python3 scripts/doctest.py --warn-only`.
It emits exit 0 regardless of individual timeouts, but the step name
historically claimed "6 residus connus" while the real count is 16.

Local run (2026-11-13, guix, 8m00 wall, 23s CPU total - timeouts not
compute):

| File | Failing commands |
|---|---|
| 01-starting-out.md | - |
| 02-believe-the-type.md | - |
| 03-syntax-in-functions.md | - |
| 04-recursion.md | - |
| 05-higher-order.md | - |
| 06-effects.md | - |
| 07-streams.md | - |
| 08-proofs.md | - |
| 09-real-world.md | - |
| 10-modules.md | - |
| 13-concurrency.md | TIMEOUT (7 cmd) |
| 14-recursion-schemes.md | TIMEOUT (16 cmd) |
| 15-optiques.md | TIMEOUT (3 cmd) |
| 16-free-monads.md | TIMEOUT (3 cmd) |
| 21-cas.md | TIMEOUT (3 cmd) |
| 26-qtt.md | TIMEOUT (3 cmd) |

Total: 152 commandes, 16 fichiers en echec.

## Why this is not `--warn-only` friendly

The `--warn-only` flag exists so the CI does not fail on preexisting
doctest timeouts. That is fine. What is not fine is the step name
claiming "6 residus" when there are 16 - a false diagnostic in the
same class as `_claims_vs_reality.md` Update 2/3/5 corrections.

## Next steps (not this session)

- Diagnose which of the 16 are slow (timeout too low) vs broken (code
  actually failing). Not equivalent: slow means bump timeout, broken
  means fix the chapter.
- Once diagnosed, reduce the 16 to a smaller honest count.
- Do not enable `--fail-on-error` until the count reaches 0.

## Do not

- Do not change `--warn-only` to `--fail-on-error` before the 16 are
  resolved - it would make CI red for legitimate reasons.
- Do not delete the failing chapters - they document real features
  that the doctest runner may not yet support (guards, effects, QTT
  multiplicities). The code may be correct but unsupported by the
  current doctest harness.
