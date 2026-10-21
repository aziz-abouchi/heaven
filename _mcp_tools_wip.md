# MCP tools status (2026-10-21)

## Fonctionnels E2E (5 tools, MCP server)
echo, time_now, time_ms, fs_read, count_chars

## web_lookup : MODULE OK, MCP tool KO
- `lib/web/ontology.hvn` : lookup_label marche (Socrate/Platon/Paris E2E)
- `tests/test_web_ontology.hvn` : 13/13
- Integration MCP : KO (ArityMismatch) car `precalc` a maintenant 7
  let-chain, au-dela de la limite detectee (~5-6).

## Test manuel web_lookup (contourne MCP)
    import "lib/web/ontology.hvn" as WO
    q _ = @char_string 34
    (print (WO.lookup_label ((q 0) + "Socrate" + (q 0))))
    -> "Socrate"

## Pistes
- fix .zig let-chain + arity (debloque 6e tool et loop)
- Ou dispatch alternatif (pas de precalc, dispatch direct avec fix qualifie)
- Ou MCP server tools/call specialise par sous-process

## Autres
- DNS .hvn `dns_resolve_a_com` : UDP timeout / Type Error, a fixer (session dediee)
- Pour l'instant `resolve_host` = mapping hardcode pour dbpedia/wikidata
