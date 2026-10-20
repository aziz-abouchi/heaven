# Ecosystem .hvn (2026-10-20)

## Feasibilite par outil

| Outil | Feasible ? | Effort | Note |
|---|---|---|---|
| `lib/random.hvn` | OUI | 1 bloc | LCG sur magics +,*,% |
| `lib/time.hvn` | OUI si clock magic | 1 bloc | Sinon .zig add |
| `lib/json_rpc.hvn` | OUI | 1 bloc | Sur `stdlib/json/parse.hvn` |
| `lib/lsp/` | OUI | 2-3 sessions | stdio + JSON-RPC + protocole |
| `lib/mcp/` | OUI | 2 sessions | Partage transport avec LSP |
| `lib/linter.hvn` | OUI | 1-2 sessions | Via `lib/heaven_parse.hvn` |
| `lib/fmt.hvn` | OUI | 2 sessions | Parse + pretty-print |
| compiler/transpiler | RFC d'abord | non promis | Multi-semaines |

## Primitives utiles (verifiees)
- IO : `print`, `read_line` (core/io.hvn, auto)
- JSON : `stdlib/json/parse.hvn` (jv_get, jv_len, json_obj_get)
- Regex : N/A (parse manuel)
- Process : `@fs_read`, `raw_syscall`

## Non-objectifs court terme
- LSP semantic tokens / inlay hints : 5+ sessions
- Formatter idempotent parfait : +2 sessions
- Compiler WebAssembly : chantier dedie
