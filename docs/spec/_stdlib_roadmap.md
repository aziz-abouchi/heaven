<!-- HEAVEN:stdlib-roadmap -->
# Refactor stdlib — organisation par domaine (2026-10-19)

## Objectif

Organiser `stdlib/` en sous-dossiers thématiques, comme le suggère
le chantier : `net/ip.hvn`, `net/tcp.hvn`, `net/udp.hvn`,
`net/dns.hvn`, `net/dhcp.hvn`, `json/parse.hvn`, etc.

## Phases

### Phase 0 ✅ (commit 07ab375)

`stdlib/string.hvn` extrait de `net.hvn` (string_matches_at,
string_split, string_split_from). Fix VFS deploy (stdlib ajouté
au find).

### Phase 1 (en cours) — DNS sous stdlib/net/

`git mv stdlib/dns_v1.hvn stdlib/net/dns_parse.hvn`
`git mv stdlib/dns.hvn stdlib/net/dns.hvn`
Imports mis à jour.

### Phase 2 ✅ (commit à venir) — split net.hvn

Plan initial (ip/udp/tcp) ERRONÉ : net.hvn n'avait ni ip ni udp.
Contenu réel :
`stdlib/net/tcp.hvn` : net_listen/accept/read/write/close/socket/
  connect + Fd (magics @net_*).
`stdlib/net/http.hvn` : parse_request, req_*/resp_*,
  format_response, _list_head/_list_nth.
`stdlib/string.hvn` : +string_eq, string_eq_from.
`stdlib/net.hvn` supprimé. `core/http_server.hvn` migré.

### Phase 3 — json sous stdlib/json/

`git mv stdlib/json.hvn stdlib/json/build.hvn`
`git mv stdlib/json_parse.hvn stdlib/json/parse.hvn`
Tests et manifest mis à jour.

### Phase 4 — nouveau : stdlib/net/dhcp.hvn

DHCP client V0 (DISCOVER/OFFER/REQUEST/ACK). Nécessite Phase 2
(udp.hvn) + Phase 1 (dns.hvn comme modèle).

### Phase 5 — nouveau : stdlib/net/http.hvn (client)

GET/POST client, importe tcp.hvn. `core/http.hvn` reste un serveur
de test dans core/ (pas client).

## Règle

Chaque phase = 1-2 commits, `test-files 0 fail` avant push.


### Phase 6 — documenter la stdlib

`docs/STDLIB.md` : référence technique (fait 2026-10-19).
`docs/spec/_stdlib_todo_book.md` : plan du chapitre livre.

Chapitre `12-stdlib.md` (ou intégré dans `10-modules.md`).
Effort : 1 session. Priorité moyenne.

### Phase 7 — DHCP (ex-phase 4, dépendances prêtes)

`stdlib/net/dhcp.hvn` : DISCOVER/OFFER/REQUEST/ACK.
Prérequis : udp.hvn (fait), ip.hvn (fait), string_split (fait).
Effort : 1-2 sessions. Nouveau code réseau, testable sur fixture
binaire (pas de réseau sandbox).

## État final 2026-10-19

Modules stdlib : 12 (string, fs, http_body, json/{build,parse},
net/{ip,udp,tcp,dns,dns_parse,http,http_client}).

Phases faites : 0, 1, 2, 3, 5 + udp + ip.
Phases restantes : 4 (dhcp), 6 (doc livre), 7 (dhcp fusionné avec 4).
