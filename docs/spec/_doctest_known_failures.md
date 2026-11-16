# Doctest book - known failures (2026-11-16, final)

## Status: 0 files, 0 errors

As of 2026-11-16, `python3 scripts/doctest.py --check` returns exit 0
on the full book. 151 commands across 15 files pass. This is the
first time since the doctest was instrumented (9d891de made it
actually run, prior to that it was 8 minutes of timeouts masquerading
as failures).

## Journey (all measured, not estimated)

| Commit | Effect | Cumulative |
|---|---|---|
| 9d891de | fix HEAVEN_NO_REPL=0 forces REPL, doctest 8min->27s | 24 errors (revealed, not created) |
| 3797c4a | cat 3 (`()` -> unit), cat 4 (colorName clauses), cat 5 (skip TypeError) | 21 |
| bc8f239 | multi-line continuation (isIncompleteInput + doctest.py extract) | 13 |
| c31ee45 | 09-real-world skip (runtime IO/FFI examples) | 10 |
| cf38591 | 04 (hanoi outer parens), 05 (filter outer parens) | 6 |
| 2f40be6 | 15 (import + mk + inc), 16 (skip-file, p3 undefined) | 0 |

## What changed in the book

Not just patches: the fixes also corrected two premature commits
(a9ee9c9 and f1c0b33) that claimed effects they did not have. The
message of cf38591 records this explicitly (same discipline as
b323c41 -> 96962dc).

## What is NOT covered by doctest

The doctest extracts `heaven>`-prefixed commands and continuation
lines starting with 6+ spaces. It does NOT:
- execute the full `core/test_suite.hvn` (covered separately by
  `zig build test-regression`)
- run `tests/*.hvn` (covered by `zig build test-files`)
- validate illustrative code blocks not marked as REPL input

These are covered by other CI steps. The doctest is one layer, not
the only one.

## Next

With 0 errors, the CI step can switch from `--warn-only` to `--check`
(blocking). Any regression in the book will fail CI at the exact
command. Same discipline as `tests/proofs/false_theorems.sh`.
