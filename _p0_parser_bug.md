# P0 = parser S-expr multi-appels sur meme ligne (2026-10-20)

## Faux P0 (6 blocs de tunnel)
Je cherchais un bug dans `perform`/`evaluate`/`toStringInfix`. Tout
etait correct. La cause reelle est ailleurs.

## Vrai bug

Deux S-expr **colles sur la meme ligne** sont mal parses :
    (print "h:")(print (h 0))
    -- ^ 2eme (print ...) silencieusement ignore

## Preuves (avec HEAVEN_DEBUG=1)
- `print (h 0)` infixe ligne 2 -> [P0] / [H] Print s='42' OK
- `(print (h 0))` S-expr ligne 2 -> OK
- `(print "h:")(print (h 0))` -> 2eme print absent de la trace

## Detection facile
HEAVEN_DEBUG=1 + instrumentation `platform.dbg` dans
engine_expr.zig:2466 (last_val) et io_handler.zig:23 (Print entry).
Rien n'apparait pour le 2eme print.

## Bug annexe detecte
`[std_loader] core/std/base.hvn '. (> n 10)) (' failed: error.InvalidSyntax`
Quelque part dans core/std/base.hvn, un meme probleme (2 appels colles
ou multi-ligne casse). Erreur avalee silencieusement en ReleaseFast.

## Fix propose (session parser dediee)
1. `src/core/parse.zig` ou `heaven_expr.zig` : le split par ligne
   doit detecter les `)(` contigus et les traiter comme fin d'un
   S-expr + debut d'un autre.
2. Alternative : exiger `\n` entre S-exprs.
3. Tester `core/std/base.hvn` + un cas minimal.

## Workaround immediat
Un appel par ligne, ou infixe (`print (h 0)` sans parens externes).

## Impact
- Tous les exemples multi-print sur une ligne echouent silencieusement
- `core/std/base.hvn` partiellement charge (mais l'erreur est avalee)
- Pas critique pour les tests unitaires (un test = une ligne)
