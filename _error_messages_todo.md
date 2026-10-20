# Messages d'erreur a ameliorer (2026-10-20)

## Problemes constates en session

1. `[eval error] error.TypeError` -- ne dit ni ou, ni quel type, ni quelle
   expression. Ex : `(print (R.rand_os_linux 0))` -> TypeError sans contexte.
2. `[eval error] error.RecursionLimitExceeded` -- ne dit pas quelle fonction
   recurse, ni la profondeur, ni la trace. Ex : print inline d'un int issu
   d'un syscall.
3. `error.ArityMismatch` -- ne dit pas combien d'args attendus vs recus,
   ni la fonction concernee.
4. `false != true` dans les tests -- ne dit pas *quelle* expression a
   produit `false`.

## Proposition (1-2 sessions .zig, plus tard)

Enrichir `error.X` en `EvalError{ kind: ErrorKind, expr_id: Id,
location: Span, message: []const u8 }`. Puis dans le dispatcher,
formatter `at <file>:<line>:<col>: <kind>: <message> | <expr>`.

Impact DX : enorme. Effort : 1-2 sessions.

## Priorite

Basse. Le workaround actuel (`print` intermediaires, tests unitaires
un par un) marche. A faire apres les bugs Vague 1 (QTT, TLS, leak).
