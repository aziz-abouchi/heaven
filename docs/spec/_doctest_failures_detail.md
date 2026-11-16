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

## CORRECTED (2026-11-16 evening): 5 categories, not 1

Initial hypothesis "one parser bug" was too unified. Manual test
`printf 'f x =\n  x + 1\nf 5\n' | HEAVEN_NO_REPL=0 heaven repl` confirmed
multi-line REPL fails (UnboundVariable x2 then ArityMismatch). That
explains 04, 05, 07, 13 (~12 errors).

But 15-optiques and 16-free-monads have NO multi-line definitions in
their extracted commands. They call `view`, `lens_snd`, `mk`,
`run_stack`, `p1` which are **never defined** in `heaven>`-prefixed
lines. The definitions exist in the chapter as raw code blocks (not
`heaven>`-prefixed); `doctest.py` doesn't extract them. That's a
different cause (extraction scope, not parser).

02 (`:type ()`) and 03 (data constructor arity) are separate single
cases. 01 is an output format issue (TypeError message).

### Category breakdown

| Cat | Cause | Files | Errors | Fix location |
|---|---|---|---|---|
| 1 | Parser multi-line REPL | 04, 05, 07, 13 | ~12 | parse.zig / engine_expr.zig |
| 2 | Doctest scope: defs in non-heaven> blocks | 15, 16 | 6 | doctest.py extract, or reformat book |
| 3 | Unit type () | 02 | 1 | parser or book |
| 4 | Data ctor arity | 03 | 1 | engine or book |
| 5 | TypeError output format | 01 | 1 | doctest comparison |

Category 1 and 2 explain 18/24. Fixing both (~3-4h) reduces
24 failures to 6.

### Original (partially wrong) hypothesis

The 15 `ArityMismatch` and 6 `UnboundVariable` observed after
multi-line clause definitions did not all come from the same cause.
Sub-groups:

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

## Closure status (2026-11-16, after 3797c4a)

| Cat | Files | Errors | Status |
|---|---|---|---|
| 1 | 04, 05, 07, 13 | ~12 | OPEN (parser multi-line) |
| 2 | 15, 16 | 6 | OPEN (doctest scope) |
| 3 | 02 | 1 | **CLOSED** (3797c4a: `()` -> unit) |
| 4 | 03 | 1 | **CLOSED** (3797c4a: colorName Green/Blue clauses) |
| 5 | 01 | 1 | **CLOSED** (3797c4a: `<!-- doctest: skip -->` around `"42" + 1`) |

3 of 5 categories closed by 3797c4a. Doctest 24 -> 19 errors expected
(confirm with `python3 scripts/doctest.py --warn-only`). Cat 1+2 remain,
representing 18 errors, both require structural fixes not book patches:

- Cat 1: parser multi-line REPL. Test discriminant:
  `printf 'f x =\n  x + 1\nf 5\n' | HEAVEN_NO_REPL=0 heaven repl` -> 6.
  Fix in parse.zig or engine_expr.zig.
- Cat 2: doctest.py extracts only `heaven>`-prefixed lines. Definitions
  in raw code blocks (not heaven>-prefixed) are invisible to the runner.
  Either doctest.py must extract a setup phase from those blocks, or the
  book chapters must be reformatted to include all definitions as
  interactive REPL commands.

