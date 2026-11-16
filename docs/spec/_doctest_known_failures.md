# Doctest book - known failures (2026-11-16, corrected)

## Correction (2026-11-16)

Previous version of this file (2026-11-13) claimed 16 files failing with
timeouts. That was wrong on two counts:

1. **The "timeouts" were not failures.** All 16 files hit the 30s
   subprocess timeout because `main.zig` refused to enter REPL mode on
   non-TTY stdin (`is_interactive = no_repl_env == null and is_tty`).
   The whole doctest took 8min of pure `sleep()` calls, never ran any
   command. Fixed in 9d891de: `HEAVEN_NO_REPL=0` now forces REPL,
   `doctest.py` sets it. Full doctest now runs in 27s.

2. **Only 10 files, 24 errors, actually fail.** With the fix applied,
   152 commands run for real. 6 of the previously listed 16 files now
   pass (06-effects, 08-proofs, 10-modules, 14-recursion-schemes,
   21-cas, 26-qtt) — their "TIMEOUT" was only slowness. The remaining
   10 files have 24 genuine errors that must be investigated.

## Real failures (2026-11-16, after 9d891de)

| File | Errors |
|---|---|
| 01-starting-out.md | ? |
| 02-believe-the-type.md | ? |
| 03-syntax-in-functions.md | ? |
| 04-recursion.md | ? |
| 05-higher-order.md | ? |
| 07-streams.md | ? |
| 09-real-world.md | ? |
| 13-concurrency.md | ? |
| 15-optiques.md | ? |
| 16-free-monads.md | ? |

The per-file error counts are in `/tmp/doctest_full.log` from the
regenerating run. To get them reproducibly:

    python3 scripts/doctest.py --warn-only | tee /tmp/doctest_full.log
    grep '✗' /tmp/doctest_full.log

## Next steps

Each of the 24 errors is a book example that no longer produces the
shown output, or that crashes/times out individually. Diagnosis per
case:
- Example is outdated (Heaven evolved, book didn't) -> update book
- Example is broken (real bug) -> fix code or fix example
- Example is slow (>30s per file) -> raise timeout or split

Not this session (the fix 9d891de is the scope of this pass).

## Detailed failures

Per-file exact error messages and a working hypothesis (single parser
bug for the multi-line cases, 3 additional independent failures) are in
`_doctest_failures_detail.md`. Start there before touching any book file.
