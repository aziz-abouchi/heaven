# MCP tools -- web_lookup WIP (2026-10-21)

## Statut
5 tools verts (echo, time_now, time_ms, fs_read, count_chars).
`web_lookup` : **non integre**, tente et rollback.

## Tentative (bloc 16-30)
Ajout `w_web` + 7e arg dans `pick` (lib/mcp/tools.hvn).
Resultat : 14/18 (regression), TypeError sur web_lookup.

## Cause racine
Le pattern `precalc + pick` evalue **tous** les tools a chaque
`run_tool` (7 evaluations avant dispatch). Pour un tool a effet de
bord (reseau HTTPS), ca declenche :
- lookup DBpedia a chaque call, meme pour echo/time_now
- TypeError quand le body n'a pas de champ "text" (time_now)
- latence x7 (test web ~20s pour 1 call utile)

Guard dans `run_web` (`if extract_name == "web_lookup"`) ne suffit pas :
  a) soit l'appel `do_lookup (extract_text body)` dans une branche if
     est soumis au bug dispatch direct (_lsp_server_wip.md)
  b) soit le let-chain 7-args de precalc casse
On n'a pas tranche (cutoff diagnostic, 30 blocs).

## Fix propre (session Zig dediee, 2 bugs conjoints)
1. Fixer dispatch direct `if m then M.foo` (_lsp_server_wip.md)
2. Fixer let-in-if (SEGV parser)
Alors on pourra passer de precalc+pick a un dispatch direct :
  run_tool body = if (extract_name body) == "web_lookup"
                  then O.lookup_label (extract_text body)
                  else if ... 

## Contournement .hvn actuel
5 tools suffisent pour MCP standard. `web_lookup` reste accessible
via `lib/web/ontology.hvn` directement (test manuel vert).
Exposer comme tool MCP attendra fix .zig.

## Preuve lookup direct
`import "lib/web/ontology.hvn" as O` + `(O.lookup_label "Python")`
-> "Python" (HTTP DBpedia live, deja valide session 2026-10-20).
