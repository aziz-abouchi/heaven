# Heaven — Bibliothèque standard

**État au 2026-10-19.** Document de référence pour `stdlib/`.
Organisé par domaine. Chaque module a une responsabilité unique.

Légende : ✅ stable (testé) · ⚠️ V0 (limites documentées) · 🚧 en chantier.

---

## `stdlib/string.hvn`

Helpers string partagés. ✅

| Fonction | Sémantique |
|---|---|
| `string_matches_at s i sep` | `true` si `sep` commence à `s[i]` |
| `string_split s sep` | split sur `sep` → `List String` |
| `string_split_from s sep start i` | boucle interne de `string_split` |
| `string_eq a b` | égalité byte-à-byte |
| `string_eq_from a b i` | boucle interne de `string_eq` |

Tests : implicites via `test_http_body`, `test_json_parse`.

---

## `stdlib/fs.hvn`

Accès fichier avec capabilities. ⚠️ V0 : `fs_read_public` restreint à `src/vessel/public/`.

| Fonction | Sémantique |
|---|---|
| `fs_read cap path` | lit un fichier (via magic `@fs_read`) |
| `fs_write cap path content` | écrit (via `@fs_write`) |
| `fs_read_public path` | wrapper `fs_read` sur `src/vessel/public/` |

---

## `stdlib/json/`

### `build.hvn` — construction JSON ✅
`json_obj pairs`, `json_arr items`, `json_str s`, `json_int n`, `json_pair k v`.
Aucun test dédié (couvert via usages).

### `parse.hvn` — parseur JSON ✅ V0+V1
- ✅ V0 : `num`, `bool`, `null`, `ws` (`json_parse`, `json_as_int_s`, `json_as_bool_s`, `json_as_null_s`).
- ✅ V1 arrays : `json_parse_arr`, `json_as_arr_s`, `jv_len`, `jv_get`, `jv_as_int`, `jv_as_str`.
- ✅ V1 objects : parse `{k:v, ...}`, lookup `json_obj_get`.
  H1/H2 clos 2026-10-19 (`_json_object_bug.md`) : le "bug" était
  un artefact de construction de string dans les tests (`\"` reste
  littéral). Parser OK, lookup OK.
- ❌ Pas de : URL-decode, échappements `\uXXXX`, floats.

**Piège construction** : `"{\"a\":1}"` ne contient pas ce qu'on
croit. Utiliser `poke_byte` + `string_of_bytes` pour les tests
objects (cf. `tests/test_json_v1.hvn::mk_obj`).

Tests : `test_json_parse` (11), `test_json_v1` (12).

---

## `stdlib/http_body.hvn`

Parser POST body form-encoded. ⚠️ V0 : pas de URL-decode, pas de multipart.

| Fonction | Sémantique |
|---|---|
| `body_parse s` | `"a=1&b=2"` → `Body` |
| `body_get body k` | valeur associée à `k`, ou `""` |

Tests : `test_http_body` (10).

---

## `stdlib/net/ip.hvn`

Utilitaires IPv4 (int big-endian ↔ string). ✅

| Fonction | Sémantique |
|---|---|
| `ip_octet ip shift` | octet à `shift` (0/8/16/24) |
| `ip_to_string ip` | `"a.b.c.d"` |

⚠️ Pas de `ip_from_string` (V1).

Tests : `test_ip` (5).

---

## `stdlib/net/udp.hvn`

Wrappers UDP sur magics `@net_*_udp`. ✅

| Fonction | Magic |
|---|---|
| `udp_socket cap` | `@net_socket_udp` |
| `udp_set_timeout cap fd secs` | `@net_set_timeout` |
| `udp_sendto cap fd ip port data` | `@net_sendto` |
| `udp_recvfrom cap fd` | `@net_recvfrom` |

Convention : l'appelant acquiert les capabilities.

---

## `stdlib/net/tcp.hvn`

Wrappers TCP (serveur + client). ✅

| Fonction | Magic |
|---|---|
| `net_listen cap port` | `@net_listen` |
| `net_accept cap fd` | `@net_accept` |
| `net_read cap fd` | `@net_read` |
| `net_write cap fd str` | `@net_write` |
| `net_close cap fd` | `@net_close` |
| `net_socket cap` | `@net_socket` |
| `net_connect cap ip port` | `@net_connect` |

Type : `Fd = Int`.

---

## `stdlib/net/dns.hvn` + `dns_parse.hvn`

DNS client (V0 + V1 parseur). ⚠️ Réseau non testable en sandbox.

### `dns.hvn`
| Fonction | Sémantique |
|---|---|
| `dns_build_query _` | query UDP "a.com A" (23 bytes) |
| `dns_resolve_a_com _` | envoie + reçoit (via `udp.*`) |
| `dns_resolve_a_com_parsed _` | résout + parse + `ip_to_string` |

### `dns_parse.hvn` (pur, testable)
| Fonction | Sémantique |
|---|---|
| `dns_id/flags/qdcount/ancount s` | header (big-endian) |
| `dns_qname_end ptr off` | scan label (récursif) |
| `dns_question_end s` | fin question |
| `dns_answer_rdata_off s` | offset RDATA |
| `dns_first_a_ip s` | IP int de la 1re answer A |

Tests : `test_dns_v1` (8).

---

## `stdlib/net/http.hvn` (helpers serveur)

Parse/format HTTP côté serveur. ⚠️ V0.

| Fonction | Sémantique |
|---|---|
| `parse_request raw` | première ligne → `(method, (path, nil))` |
| `req_method/path/headers` | accesseurs |
| `resp_status/body/headers` | accesseurs |
| `format_response r` | `(status, (body, _))` → HTTP/1.1 string |

Consommé par `core/http_server.hvn`.

---

## `stdlib/net/http_client.hvn`

HTTP client V0. ⚠️ Réseau non testé, parse testable.

| Fonction | Sémantique |
|---|---|
| `http_parse_status raw` | `200`, `404`, `500`… |
| `http_parse_body raw` | body après `\r\n\r\n` |
| `http_build_get host path` | requête GET |
| `http_get host port path` | connect + write + read + close (réseau requis) |

❌ Pas de : redirect, chunked, TLS, POST.

Tests : `test_http_client` (7).

---

## Voir aussi

- `docs/spec/_stdlib_roadmap.md` — phases du refactor.
- `docs/spec/_json_object_bug.md` — H1/H2/H3 (JSON objects).
- `docs/spec/_metacircularite_chantier.md` — self-hosting Heaven.
