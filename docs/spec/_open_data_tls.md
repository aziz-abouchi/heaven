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

## RESOLU 2026-10-20 (TLS livre)

**`src/platform/tls.zig`** : wrappers OpenSSL FFI (SSL_CTX_new,
SSL_new, SSL_set_fd, SSL_connect, SSL_read, SSL_write, SSL_shutdown).
2 tests linkage passent (`TLS_client_method`, `SSL_CTX_new`).

**4 magics** dans `engine_expr.zig` :
- `@tls_connect fd host` -> handle (pointer TlsConn)
- `@tls_write handle data` -> n bytes
- `@tls_read handle` -> response string (max 64KB)
- `@tls_close handle`

**Linkage** : `build.zig` lie `libssl` + `libcrypto` (Nix/Guix store,
pkg-config). `tls_mod.link_libc = true`.

**Test end-to-end** : TLS sur `query.wikidata.org:443` via
`@net_connect` (IPv4) + `@tls_connect` + `@tls_write` + `@tls_read`.
La reponse brute recue : `HTTP/1.1 400 Bad request ... server:
HAProxy` (requete mal formee, mais **TLS fonctionne**).

## Ce qui reste

- **DNS `.hvn`** : `@net_connect` prend une IP, pas un hostname.
  Il faut `dns_resolve` (stdlib/net/dns.hvn) pour resoudre avant.
  Ou passer `host` a `@tls_connect` (SNI, fait) mais connect via IP.
- **Requete Wikidata 400** : path `/sparql?query=...` trop long ou
  User-Agent mal formate. Debug en session dediee.
- **`http_get_https`** : wrapper dans `stdlib/net/http_client.hvn`
  qui combine dns_resolve + net_connect + tls_connect + write + read.
- **Tests offline** : fixture `"{\"a\":1}"` toujours fragile
  (backslash-quote litteral). `poke_byte` reste le workaround.

## Baseline

ReleaseFast `--run-tests` = 0 fail apres TLS. wasm x2 = 0
(les magics TLS sont exclus du freestanding).

## Niveau 1 livre (2026-10-20) : @tls_read dynamique

`@tls_read` cap 16MB (chunks 16KB). TLS lit des reponses > 64KB
(Wikidata entity data, HTML, gros JSON).

## Niveau 3 (stream pur .hvn) -- TODO

`@tls_read_chunk handle` -> un chunk, + `stream_map`/`stream_filter`
en .hvn. Effort : 2 sessions. Debloque SSE, HTML parsing
incremental, book ch. 7 (streams).

## sexy_ontology -- KO (3 bugs cumules)

Pattern cible : Wikidata Q42 -> JSON -> Kb -> query "Douglas Adams".
Marche partiellement (13/15 tests). 3 bugs a resoudre :

1. `req_of qid` (helper dynamique) retourne vide, alors que la
   requete inline dans `wikidata_live.hvn` marche. Suspect :
   concat profonde avec `qid` variable.
2. `body_of` via `_find_json` cherche `{` brut dans les headers.
   `User-Agent: heaven-ontology/0.1` n'en contient pas, mais le
   pattern est fragile. Chercher `\r\n\r\n` d'abord.
3. `wbgetentities` endpoint (plus petit que entity data) retourne
   `labels:{}` vide. Parametres a ajuster : `props=labels` sans
   `languages` separe, ou `formatversion=2`.

