# MCP status (2026-10-21) -- COMPLET

## Fait (fonctionnel E2E)
- lib/mcp/handlers.hvn : init, tools_list (5 tools), tool_call
- lib/mcp/tools.hvn : echo, time_now, time_ms, fs_read, count_chars
- lib/mcp/server.hvn : dispatch 3 methodes (precalcul+pick)

## 5 tools (tous verifies E2E)
- echo           : retourne le "text" recu
- time_now       : timestamp Unix (secondes)
- time_ms        : timestamp Unix (millisecondes)
- fs_read        : lit fichier via @fs_read (ex /etc/hostname -> "devilHope")
- count_chars    : longueur du "text"

## Pattern "precalcul + pick" (debloque dispatch)
EvaluER toutes les branches AVANT le if, puis pick par methode.
Zero appel qualifie dans le if (bug see _lsp_server_wip.md).

## E2E verifies
- initialize    -> capabilities
- tools/list    -> 5 tools, 483 chars JSON
- tools/call echo "hi"        -> "hi"
- tools/call count_chars      -> "5"
- tools/call fs_read /etc/... -> "devilHope"
- tools/call time_now         -> "1792..."

## Reste
- Loop multi-frame (voir _mcp_loop_wip.md, bloque .zig)
- Plus de tools (parse_hvn, eval_expr, ...)
- LSP : appliquer precalcul+pick pour 4 methodes
