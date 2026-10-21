# MCP status (2026-10-21)

## Fait
- lib/mcp/handlers.hvn : init_body, tools_list_body, tool_call_body
  (17/17 tests structurels)
- lib/mcp/server.hvn : serve_once (initialize via pipe, E2E OK)
- Réutilise lib/lsp/{stdio,frame}.hvn + lib/json_rpc.hvn

## Bloqué
Dispatch multi-branches avec appels handler magics KO
(voir _lsp_server_wip.md). MVP : initialize seulement.

## Next
- tools/list + tools/call via serve_once (dispatch 2 branches, à tester)
- Ou fix .zig dispatch (1 session)
- Loop serve : nécessite read_stdin non-bloquant ou EOF-detect

## Test E2E
    printf 'Content-Length: 53\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
      | ./zig-out/bin/heaven run /tmp/mcpsrv.hvn

Sortie : Content-Length: 141\r\n\r\n{"jsonrpc":"2.0","id":1,"result":
{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},
"serverInfo":{"name":"heaven","version":"0.1"}}}
