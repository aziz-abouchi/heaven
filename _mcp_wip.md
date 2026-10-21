# MCP status (2026-10-21)

## Fait (complet MVP)
- lib/mcp/handlers.hvn : init, tools_list, tool_call (17/17)
- lib/mcp/server.hvn : dispatch 3 branches (wrapper workaround)

## E2E
- initialize -> Content-Length: 141 + JSON capabilities
- tools/list -> Content-Length: 213 + JSON 2 tools (echo, time_now)
- tools/call -> (a tester avec vrai body, wrapper pret)

## Reste
- lib/mcp/tools.hvn : vrais outils (echo, time_now, fs_read)
- Loop serve (bloque, read_stdin)
