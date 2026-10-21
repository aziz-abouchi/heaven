# LSP server status (2026-10-21)

## RESOLU : pattern "precalcul + pick" (voir _mcp_wip.md)

Test : dispatch multi-branches OK si tous les appels evalues AVANT if.

## Fait
- lib/lsp/server.hvn : MVP initialize (dispatch simple)
- lib/mcp/server.hvn : dispatch 3 methodes (precalcul+pick, E2E complet)

## Reste
- Appliquer precalcul+pick dans lib/lsp/server.hvn (4 methodes)
- Loop serve (read_stdin bloque)
- didOpen avec vrai parsing (linter)
