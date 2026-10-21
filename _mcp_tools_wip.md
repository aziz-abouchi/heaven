# MCP tools -- status (2026-10-21)

## Fait (5 tools E2E, COMMIT 7aebe51)
- echo, time_now, time_ms, fs_read, count_chars

## Tentative parse_hvn (KO, rollback)
`lib/heaven_parse.hvn` expose `lex` qui retourne un type `Toks`
(TNil | TCons Tok Toks), pas une API `parse`/`expr_count`.
Pas de tool simple sans écrire un wrapper qui compte les tokens.

## Piste future (parse_hvn)
    import "lib/heaven_parse.hvn" as HP
    toks_len TNil = 0
    toks_len (TCons _ rest) = 1 + toks_len rest
    -- parse_hvn body = int_to_string (toks_len (HP.lex (extract_text body)))

Necessite de matcher le constructeur `TCons` qui est dans HP (peut
necessiter `import "lib/heaven_parse.hvn"` sans alias pour acceder
aux constructeurs en pattern).

## Bloque : loop multi-frame, parse_hvn tool
- Loop : let+recursion .zig (voir _mcp_loop_wip.md)
- parse_hvn : API HP inadequat, wrapper 5+ lignes

## Next
Fix .zig let+recursion (debloque loop + QTT + plus)
