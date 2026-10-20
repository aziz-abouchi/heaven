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
| `string_ends_with s suffix` | `1` si `s` finit par `suffix`, `0` sinon. ⚠️ SIGSEGV en condition d'`if` dans helper local (voir B-erreurs) |
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

---

## `http_server.hvn` (racine, E4)

Serveur HTTP multi-client en `.hvn` pur, avec routing (v1, 2026-10-20).

- `@net_listen` + loop récursive + `@net_accept` + `@net_read` + `@net_write` + `@net_close`.
- v1 : routing `"/"` -> index.html, `/foo.css` -> text/css, etc.
  Statiques lus dans `src/vessel/public/` via `FS.fs_read_public`.
- Lancement : `./zig-out/bin/heaven run http_server.hvn`
- Test : `curl http://127.0.0.1:8080/` → `hi`

Routing (v1) en cours : voir `_http_fullstack_plan.md` section "E4-D2bis".
NB : GitHub Pages n'utilise PAS ce serveur (statique).

---

## `stdlib/option.hvn`

`data Maybe = None | Some Int`. Payload Int (HKT-V1c nécessaire pour
polymorphisme paramétrique).

- `maybe_or d m` : extrait ou défaut
- `maybe_map f m` : Functor
- `maybe_bind m f` : Monad

## `stdlib/fantasy_land.hvn`

**Spec Fantasy Land (McKenna)** en `.hvn` pur via HKT V1b
(dispatch explicite). 13/13 tests.

10 classes instanciées pour `List` et `Maybe` :

| Classe | Op | Test |
|---|---|---|
| Setoid | `equals T a b` | 2 |
| Ord | `lte T a b` | (Int) |
| Semigroup | `concat T a b` | 1 |
| Monoid | `empty T` | 1 |
| Functor | `map T f xs` | 2 |
| Apply | `ap T fs xs` | 1 |
| Applicative | `of T x` | 2 |
| Chain | `chain T m f` | 2 |
| Monad | (Applicative + Chain) | — |
| Foldable | `reduce T f acc xs` | 1 |

Sans HKT : `fmap_List`, `fmap_Maybe`, `concat_List`... une par type.
Avec V1b : `map "List" f xs`, `chain "Maybe" m f`, dispatch explicite
par tag string.

## `stdlib/optics.hvn`

**Lens, Prism, Iso** (Kmett simplifié). 12/12 tests.

    data Lens s a = MkLens (s -> a) (a -> s -> s)
    data Prism s a = MkPrism (s -> Maybe_a) (a -> s)

- `view`, `set`, `over`, `lens_compose`
- `preview`, `review`, `iso`

Piège : lens = 0-arg def (fonction), donc `(name_lens unit)`.

Non implémenté : profunctor encoding (Kmett), rank-2 vérifié.
Voir `_hkt_rank2_plan.md`.

## `stdlib/free.hvn`

**Free monad tag-encoded** (Lonsdorf). 6/6 tests.

    data Free = FPure Int | FFree String Int

- `free_pure x`, `free_bind m f`, `free_map tag f m`, `free_fold handler m`

Tag string pour dispatch fmap (V1b). `Free f a` générique = rank-2.

## `stdlib/transformers.hvn`

**MaybeT** (Wilson). 6/6 tests.

    data MaybeT = MT_Maybe Maybe | MT_List (List Maybe)

- `mt_just tag x`, `mt_nothing`, `mt_run`, `mt_bind`

StateT : stub.

## `stdlib/profunctor.hvn`

**Profunctor partiel** (Kmett). Partiel.

    data Profunctor = MkProfunctor (Int -> Int) (Int -> Int)

- `dimap f g p`, `lmap f p`, `rmap g p`, `pcompose p q`, `pid`

Limit : capture de fonction dans lambda imbriquée SIGSEGV sur un
cas résiduel (ctor pattern 2-arg + ctor body). Voir
`_closure_capture_bug.md` §2.

## `stdlib/ontology.hvn`

**RDF/KB en `.hvn` pur**. 14/14 tests.

    data Triple = MkTriple String String String
    data Kb = Knil | Kcons Triple Kb

| Fonction | Semantique |
|---|---|
| `subject t` | `s` de `MkTriple s p o` |
| `predicate t` | `p` |
| `object t` | `o` |
| `kb_size kb` | nombre de triples |
| `filter_subj s kb` | sous-KB avec sujet `s` |
| `filter_pred p kb` | sous-KB avec predicat `p` |
| `kb_query kb s p` | premier objet pour `(s, p)`, `""` sinon |
| `kb_count kb s p` | nombre d'objets pour `(s, p)` |
| `kb_has kb s p o` | `true` si le triple existe |

**Mots reserves** : `query`, `count` sont des mots du pipeline kanren.
On prefixe par `kb_` (`kb_query`, `kb_count`) pour eviter la collision
silencieuse.

**Contraintes parser** : voir B-erreurs (if imbrique, pattern non-unifiant).

**Exemple** : `examples/ontology/socrates.hvn` (10 triples, 3 queries).

