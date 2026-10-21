# MCP status (2026-10-21) -- COMPLET

## Fait (fonctionnel E2E)
- lib/mcp/handlers.hvn : init, tools_list, tool_call (17/17)
- lib/mcp/tools.hvn : echo, time_now (16/16)
- lib/mcp/server.hvn : dispatch 3 methodes (precalcul + pick)

## Pattern "precalcul + pick" (debloque dispatch)
Bug : `if m == "x" then M.foo i else ...` (qualifie direct) = KO.
Fix : evaluer TOUTES les branches AVANT le if, puis pick :
    build body =
      let r_init = M.init_body i in
      let r_list = M.tools_list_body i in
      let r_call = TT.handle_tools_call i body in
      pick m r_init r_list r_call
    pick m i l c =
      if m == "initialize" then i
      else if m == "tools/list" then l
      else if m == "tools/call" then c
      else ""
Zero appel qualifie dans le if.

## E2E verifies
- initialize -> Content-Length: 141 + JSON capabilities
- tools/list -> Content-Length: 213 + 2 tools (echo, time_now)
- tools/call echo -> "text":"hi"
- tools/call time_now -> "text":"1792597960"

## Reste
- Loop serve (read_stdin bloque)
- Plus de tools (fs_read, parse, etc.)
- LSP : appliquer precalcul+pick pour 4 methodes
