# LSP server WIP (2026-10-21)

## Fait (MVP)
- lib/lsp/server.hvn : serve_once (read frame -> extract_id -> H.init_body -> write frame)
- Marche pour "initialize" seul.

## Bloque : dispatch multi-branches
T3 test :
    d m i = if m == "a" then 10 else H.shutdown_resp i
    -> ExecutionFailed

Patterns qui marchent :
- if branch with literals (Int/Int, String/String)
- if branch with single param return

Patterns qui cassent :
- if branch appelle H.init_body/H.shutdown_resp (magic @char_string + concatenation)
- dispatch avec 2+ appels de handler dans des branches

Hypothese : appels de fonction qui utilisent magics 0-arg (@char_string)
dans les branches de if cassent le engine.

## Piste
- Inliner les handlers dans dispatch (pas d'appel module)
- Ou ajouter `--method` parametre et pas de dispatch (1 method par run)
- Ou fix .zig sur eval .if avec appels magics

## Next session
Investigation eval.if + magic dispatch. 1 session .zig.
