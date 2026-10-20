# Open data TLS -- blocage (2026-10-20)

## Symptome

Les API open data (Wikidata, OpenLibrary, DBpedia) sont en HTTPS.
`http_get` V0 (`stdlib/net/http_client.hvn`) ne fait **pas** TLS.

## Ce qui marche

- **Parseur JSON** : `json_as_obj_s`, `json_obj_get`, `jv_get`,
  `jv_as_str`, `jv_as_int` (12/12 tests test_json_v1, test_json_parse).
- **urlencode** : `stdlib/net/urlencode.hvn` (9/9).
- **Pattern complet** : `examples/open_data/openlibrary.hvn`,
  `wikidata.hvn`, `dbpedia.hvn` (code cible).
- **DBpedia HTTP** : `dbpedia.org:80` peut marcher sur binaire natif.

## Ce qui bloque

- **TLS** : `H.http_get host 443 path` ne fait pas de handshake.
  `@net_connect` V0 ne supporte pas TLS.
- **User-Agent** : `http_build_get` n'en met pas. Wikidata renvoie 403
  sans UA.
- **Fixture offline avec `\"`** : les litteraux `"{\"a\":1}"` ne
  contiennent pas ce qu'on croit (`\"` reste litteral, cf.
  `_syntax_gaps.md`). Pour tester offline, utiliser `poke_byte` +
  `string_of_bytes` (cf. `tests/test_json_v1.hvn::mk_obj`).

## Plan TLS

Voir `DECISIONS.md` D-SH1 (OpenSSL via FFI). Effort :

- **OpenSSL FFI** : 2 sessions (`@tls_connect`, `@tls_read`,
  `@tls_write`, `@tls_close` wrappers + `http_get_https`).
- **User-Agent** : 1 bloc (`http_build_get_ua`).
- **Test online** : avec les 2, `examples/open_data/*.hvn` marchent.

Hors scope court terme : D-SH1 est une session dediee.

## Workaround offline

Pour tester le pattern sans reseau, construire la fixture via
`poke_byte` (cf. `mk_obj`). C'est verbeux mais fiable.

Exemple pour `{"docs":[{"title":"X"}]}` (23 bytes) :
- b[0] = 123 ( `{` )
- b[1] = 34 ( `"` ), b[2] = 100 ( `d` ), ...
- ... 23 poke_byte au total.

A eviter si `http_get` peut tester online (binaire natif, HTTP).
