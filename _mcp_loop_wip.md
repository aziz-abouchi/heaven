# MCP loop WIP (2026-10-21)

## Fait (single-shot)
- lib/mcp/server.hvn : serve_once (1 requete, 1 reponse) E2E OK
- 4 methodes : initialize, tools/list, tools/call echo, tools/call time_now

## Bloque : loop multi-frame
Objectif : lire tout stdin (2+ frames) et repondre a chacune.

Diagnostic :
- read_stdin 8192 : OK, lit tout le buffer d'un coup
- parse_len_from / find_sep_from : OK (testes isolement)
- Le bug est dans process_frame_* : chaine let + appels recursifs

Combinaisons qui cassent (pièges documentés) :
1. `let _w = write(...) in process_frame buf (off+1)` = let + recursion
2. `let buf = read(...) in process_frame buf 0` = let + appel (peut-être)

Workaround tenté (split en helpers) : KO. Il faut 1 session .zig
pour fixer les combinatoires let + appel.

## Piste session fraîche
1. Tester isolément `let buf = X in process buf 0` (lettre simple)
2. Si KO : fix .zig let-chain + appel (débloque aussi QTT)
3. Sinon : instrumenter process_frame_write avec platform.dbg

## Alternative immédiate
Libérer un `--serve` mode côté .zig (run.zig) qui boucle read/dispatch/write
en .zig au lieu de .hvn. Contourne le bug, sacrifie "100% .hvn".

## Non-objectif
Loop parfait sans fix .zig. Preuve de concept single-shot est suffisante
pour MCP.
