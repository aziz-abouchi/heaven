# lib/json_rpc.hvn -- WIP (2026-10-21)

## Probleme
Les 7-niveaux de `string_concat` imbriques sont fragiles (parens
desequilibrees au moindre edit). Le module crash au chargement
(TypeError / InvalidSyntax).

## Limitation decouverte
`"a" + "b"` -> TypeError. **Seul** `string_concat a b` marche pour
concatener des strings. A documenter dans _session_continuity.

## Tentatives
1. Avec escapes \" -- parser refuse (InvalidSyntax)
2. Sans escapes, `@char_string 34` pour le quote -- marche pour `q _`
   mais crash dans les concatenations complexes
3. Tests structurels sans litteraux `{` `}` -- passent 3/4 puis crash

## Piste pour session dediee
- Simplifier: ne PAS produire du JSON via concat. Utiliser `stdlib/json/build.hvn`
  (existe, a verifier ses primitives)
- Ou definir un type `Json` en .hvn avec des ctor, puis `to_string` recursif
- Ou ajouter `+` pour strings (fix .zig evalCmp, 5 lignes) -- debloque
  toute concatenation lisible

## Effort
1 session .zig (fix `+` strings) ou 1 session .hvn (Json type + to_string).
Priorite BASSE -- `stdlib/json/build.hvn` existe deja.

## Non-objectif
Faire du LSP/MCP sans JSON serialisation solide.
