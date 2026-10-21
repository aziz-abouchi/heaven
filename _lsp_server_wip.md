# LSP server status (2026-10-21)

## RESOLU : workaround wrapper local

Bug : `if m == "x" then M.foo i else ...` (qualifié direct) = ExecutionFailed.
Fix : wrapper local `w i = M.foo i` puis `if m == "x" then w i else ...`.

Test :
    w_init i = M.init_body i
    d m i = if m == 1 then w_init i else "none"
    -- OK

## Fait
- lib/lsp/server.hvn : dispatch 4 branches (initialize, shutdown, didSave, didOpen)
- lib/mcp/server.hvn : dispatch 3 branches (initialize, tools/list, tools/call)
- 3 tests E2E pipe OK (MCP init, MCP list, LSP init)

## Reste
- Loop serve (read_stdin bloque, EOF detect)
- Fix .zig dispatch qualifié (cosmétique, workaround marche)
