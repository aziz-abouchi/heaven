# Segfault : parser metacirculaire HP.parse_file

**Date** : 2026-10-15
**Statut** : identifie, non corrige. Tests skippes.
**Impact** : test_diff_e.hvn, test_selfparse.hvn.

## Symptome

Les tests qui parsent des fichiers .hvn via `HP.parse_file`
(lib/heaven_parse.hvn, mode metacirculaire) provoquent un
SIGSEGV sur certaines entrees.

Stack trace (partial) :
    evalMagic (engine_expr.zig:1747)
    -> engine.evalFunction(env, op, args_snap)
    evaluate (engine_expr.zig:857)

## Reproduction

    ./zig-out/bin/heaven --run-test tests/test_selfparse.hvn
    -> Erreur de segmentation (exit 139)

## Contexte

- Le segfault n'apparait PAS avec le code de 6a2100c.
- Un revert de 3af063f (fold N-aire) le fait disparaitre
  temporairement, mais ne resout pas la cause racine.
- Le bug est dans la chaine HP.lex -> HP.parse_file, sur
  des fichiers .hvn complexes (test_array.hvn, ou le parser
  lui-meme).

## Piste

Stack overflow probable dans parse_file (recursion sur la
liste de tokens). Le parser recurse sans limite explicite.
Sur un fichier 21 lignes, la recursion devrait tenir ;
mais evalFunction peut empiler via TCO mal detecte.

## Fix propose

1. Reinstaurer un compteur de profondeur dans parse_file.
2. Ou decoupler evalFunction du engine TCO pour le mode
   bootstrap.
3. Ou augmenter la pile au lancement du binaire (ulimit).

## Palliatif actuel

Tests commentes dans :
- tests/test_diff_e.hvn (30 tests)
- tests/test_selfparse.hvn (a documenter)

Les hooks (import, read_file) sont conserves pour conserver
les imports.
