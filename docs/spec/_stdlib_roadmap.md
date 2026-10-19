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

### Phase 2 — split net.hvn (1h, risqué)

`stdlib/net/ip.hvn` : parse/format a.b.c.d (extrait de dns_parse)
`stdlib/net/udp.hvn` : sendto/recvfrom wrappers
`stdlib/net/tcp.hvn` : connect/listen/accept/read/write
`stdlib/net.hvn` : supprimé (contenu dispatché)

Risque : `core/http_server.hvn` importe `stdlib/net.hvn` -> à
mettre à jour vers les nouveaux fichiers.

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
