# Bug : segfault dans test_diff_e.hvn

**Date** : 2026-10-15
**Statut** : identifie, non corrige. Test skippe.
**Impact** : test_diff_e.hvn (30 cas de parsing recursif).

## Symptome

`./zig-out/bin/heaven --run-test tests/test_diff_e.hvn`
-> SIGSEGV (exit 139) apres ~2 tests reussis.

Stack trace (partielle) :

    evalMagic (engine_expr.zig:1747)
    -> engine.evalFunction(env, op, args_snap)
    evaluate (engine_expr.zig:857)
    -> evalMagic(...)
    evaluateExpr (heaven_expr.zig:2990)
    interpForAssert (heaven_expr.zig:3237)
    evalAssertionNative (heaven_expr.zig:3494)
    eval (heaven_expr.zig:1060)
    runTestFile (test_runner.zig:144)

Le crash se produit dans evalFunction, probablement sur un
fichier de test specifique que HP.parse_file ne digere pas.

## Reproduction

Test avant nos commits du 15 oct : segfault identique.
Ce n'est PAS une regression de C3, wasm, ou bug-plus.

## Piste

Le test parse des fichiers .hvn via HP (heaven_parse.hvn, mode
metacirculaire). Un des fichiers contient probablement une forme
que HP.lex ou HP.parse_file traite avec un pointeur invalide
(array out-of-bounds, ou string_of_bytes sur n = -1).

Fichiers candidats :
- tests/test_prompt_depth.hvn (magics @prompt, @throw)
- tests/test_continuations.hvn (handle_rec, magics)
- tests/test_effects_rec*.hvn (continuations)

## Fix propose

Session dediee :
1. Reduire le test a 1 fichier a la fois pour isoler le coupable.
2. Instrumenter HP.parse_file avec prints sur chaque etape.
3. Corriger bounds check ou pointeur invalide.

## Palliatif actuel

Les 30 tests `DIFF` sont commentes dans tests/test_diff_e.hvn
(commit 9bdea65). Les hooks (read_file, import) sont conserves.
