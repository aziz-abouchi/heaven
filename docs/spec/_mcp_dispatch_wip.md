# MCP dispatch direct -- WIP (2026-10-23)

## Resultat

Dispatch direct via helpers dans `if` fonctionne (5 tools MCP OK 18/18).
`web_lookup` reste bloque par 2 bugs runtime distincts.

## Bug 1 : import O casse le module
`import lib/web/ontology.hvn as O` dans tools.hvn -> echo (qui marchait) renvoie UnboundVariable.

## Bug 2 : O.foo dans fonction = panic Zig
`f x = O.lookup_label x` -> panic: reached unreachable code (std/debug.zig:559).
Marche au top-level, pas dans une fonction.

## Ce qui marche
Dispatch direct via helpers dans if (5 tools, 18/18).
if lazy (verifie). Helper non-qualifie dans if OK.
O.lookup_label au top-level OK.

## Fix propre (session Zig dediee)
1. Investiguer pourquoi import ajoute casse UnboundVariable.
2. Investiguer appel qualifie dans fonction (assert std/debug.zig:559).
web_lookup contourne via lib/web/ontology.hvn direct.

## Bug 3 (decouvert apres coup) : tools.hvn en --eval-file
import tools.hvn = OK ("loaded"), mais handle_tools_call -> UnboundVariable.
Marche en --run-test (18/18), casse en --eval-file.
Bug mode-dependant, pre-existant au patch dispatch direct.

Impact : dispatch direct neutral (18/18 run-test, KO eval-file).
Revert commit 4614730 (garde precalc+pick).
Piste session Zig : comparer eval_file vs run_test dans test_runner.zig
(resolution des imports/qualifies differente).
