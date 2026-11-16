# Doctest book - 24 failures detail (2026-11-16)

Companion to `_doctest_known_failures.md`. Captures the exact error
messages for the 24 real failures revealed by the REPL fix (9d891de).

## Distribution

| Error | Count | Files |
|---|---|---|
| `error.ArityMismatch` | 15 | 03, 05, 07, 09, 13, 15, 16 |
| `error.UnboundVariable` | 6 | 04, 05, 07, 13, 15 |
| `error.TypeError` | 1 | 01 |
| `error.InvalidSyntax` | 1 | 02 |

## Hypothesis: single parser bug (multi-line clauses)

All 15 `ArityMismatch` and 6 `UnboundVariable` failures occur after
multi-line clause definitions in the chapters:

- 04-recursion: `hanoi n from to via =` (body on next lines)
- 05-higher-order: `filter p (cons x xs) =` (body on next lines)
- 07-streams: `streamTake` (defined across multiple lines)
- 13-concurrency: `body` spawn form
- 15-optiques, 16-free-monads: complex nested definitions

Single-line definitions (`inc x = x + 1`, `add a b = a + b`) pass.
Multi-line (`filter p (cons x xs) =\n  if p x then ...`) fail.

If confirmed, this is ONE parser regression, not 24 independent bugs.
Not confirmed this session (would need parser unit tests).

## Individual failures (per file)

### 01-starting-out.md (1 error)
Command: `"42" + 1` -> expected TypeError, but observed `[EVAL ERROR] error.TypeError` (message format probably differs from book expectation).
Possibly: the doctest compares output lines and the book expects a specific error format.

### 02-believe-the-type.md (1 error)
Command: `:type ()` (unit) -> `error.InvalidSyntax`.
Possibly: unit type literal `()` no longer parses.

### 03-syntax-in-functions.md (1 error)
After `colorName` definition (data constructor + pattern match), next command fails with `ArityMismatch`.
Possibly: data constructor application broken.

### 04-recursion.md (1 error)
After `hanoi` multi-line definition, next command -> `UnboundVariable`.
Multi-line clause hypothesis.

### 05-higher-order.md (2 errors)
After `filter` multi-line clause and after compose example.
Multi-line hypothesis + possibly compose `(inc >>> dbl)` syntax.

### 07-streams.md (4 errors)
`streamTake` multi-line. Recurring `UnboundVariable` + `ArityMismatch` after definitions.

### 09-real-world.md (4 errors)
All 4 commands fail with `ArityMismatch`. Chapter has 6 commands total.
Commands are HTTP/IO related; possibly `spawn`/`recv` runtime broken.

### 13-concurrency.md (4 errors)
Same pattern as 09: 4/7 fail with mixed UnboundVariable/ArityMismatch.
`body` spawn form implicated.

### 15-optiques.md (3/3 fail)
All commands fail. Features (Lens/Prism) may have been removed/renamed.

### 16-free-monads.md (3/3 fail)
All commands fail. `free` / `Free` may have been renamed.

## To reproduce

    python3 scripts/doctest.py --warn-only docs/book/src/04-recursion.md 2>&1
    # or all files:
    python3 scripts/doctest.py --warn-only 2>&1

## Next steps (session dediee)

1. **Parser multi-line**: add unit tests in `src/core/parse.zig` for
   `f x =\n  body` (with newline). If broken, one fix resolves ~21.
2. **Data constructor arity**: test 03 case `Red`, `colorName Blue`.
3. **Unit type** `()`: test 02 case.
4. **HTTP/spawn runtime**: test 09/13 cases - possibly unrelated to
   parser (runtime issue).
5. **Optics/free-monads**: verify feature exists, update book or code.

Estimated effort once hypothesis confirmed: 2-4h for parser + data,
potentially 4-8h if runtime is also broken.
