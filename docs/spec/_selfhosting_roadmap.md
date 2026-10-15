# Self-hosting Heaven : roadmap

**Date** : 2026-10-15
**Statut** : audit A0 termine. Plan d'action trace.

## Objectif

Auto-heberger Heaven : que Heaven serve Heaven (site, API,
REPL web, base vectorielle, IA) sur un VPS public.

## Etat actuel (audit A0)

### Existant

| Composant | Fichier | Etat |
|---|---|---|
| Serveur HTTP statique | core/http.hvn (90 l.) | ✅ |
| Serveur HTTP complet | core/http_server.hvn (45 l.) | ✅ |
| Primitives reseau | stdlib/net.hvn, magics @net_* | ✅ |
| Syscalls bas niveau | core/io_stream.hvn | ✅ |
| FFI C (TCC) | build.zig + vendor/tcc | ✅ |
| Matrices | src/core/matrix.zig (665 l.) | ✅ |
| Bitstrings P1/P2 (alignes) | RFC-0002 | ✅ |

### Manquant

| Composant | Impact |
|---|---|
| TCP client (@net_connect) | Bloque tous les clients |
| DNS resolve | Bloque tout ce qui sort du localhost |
| TLS (OpenSSL FFI) | Bloque tout deploiement public |
| Bitstrings P3 (non aligne) | Bloque Diameter, AMQP, Cassandra |
| Persistance (Bitcask-like) | Bloque etat serveur |
| Multi-shot continuations (A-3b) | Bloque serveur concurrent |

## Decisions architecturales

### D-SH1 — TLS : OpenSSL via FFI

**Options** :
- A) OpenSSL FFI (libssl.so) — mature, standard, FFI simple
- B) TLS en Heaven pur — 6-12 mois
- C) Pas de TLS V0 — non-deployable en prod

**Decision** : A. Le build inclut deja TCC ; ajouter libssl est
meme ordre de complexite. Ecrire TLS est hors scope.

### D-SH2 — Persistance : Bitcask-like en Heaven

**Options** :
- A) Bitcask (append-only log + index RAM) — ~500 lignes
- B) SQLite via FFI — puissant mais moins Heaven-natif
- C) Cassandra auto-heberge — operationnellement lourd

**Decision** : A pour V0. Cassandra en V1+ si besoin.

### D-SH3 — IA embarquee : ONNX FFI + vector DB native

**Options** :
- A) ONNX Runtime FFI — mature, tous les modeles
- B) llama.cpp FFI — LLM specifiquement
- C) Heaven pur (MLP < 10M params)
- D) safetensors + ops Heaven

**Decision** : A (ONNX FFI) pour l'inference generale.
Base vectorielle (HNSW) en Heaven pur — utile meme sans IA.

## Plan en 9 etapes

### Bloc Reseau (fondations)

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **N1** | TCP client (@net_connect) | 1 session | rien |
| **N2** | DNS resolve | 1 session | N1 |
| **N3** | Sockets non-bloquants | 1 session | N1 |
| **N4** | Bitstrings P3 (non aligne) | 1-2 sessions | rien |

### Bloc TLS + HTTP

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **T1** | OpenSSL FFI (TLS_connect/read/write) | 2-3 sessions | N1, N2 |
| **T2** | HTTP client (GET/POST) | 1 session | T1 |
| **T3** | HTTP server v2 (routing, POST, WebSocket) | 2 sessions | N3 |

### Bloc Concurrence

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **C1** | A-3b (multi-shot continuations) | 2-3 sessions | rien |
| **C2** | Scheduler preemptif complet | 1 session | C1 |

### Bloc Donnees

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **P1** | Bitcask-like en Heaven | 1-2 sessions | N4 |
| **P2** | Vector DB (HNSW) | 2-3 sessions | P1 |
| **P3** | ONNX FFI + inférence | 2-3 sessions | T1 |

### Bloc Protocoles

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **M1** | Memcached client | 1 session | N1, N4 |
| **M2** | Diameter (base + AVP) | 2-3 sessions | N1, N4, T1 |
| **M3** | AMQP 0-9-1 (RabbitMQ) | 2-3 sessions | N1, N4, T1 |
| **M4** | Cassandra native protocol | 3-4 sessions | N1, N4, T1 |

### Bloc Bootstrap

| Etape | Livrable | Effort | Bloque par |
|---|---|---|---|
| **B1** | heaven_eval.hvn complet | 3-5 sessions | tout |

## Ordre recommande

1. **N1** (TCP client) — 1 session, debloque tout
2. **N2** (DNS) — 1 session
3. **T1** (TLS FFI) — 2-3 sessions
4. **T2** (HTTP client) — 1 session
5. **M1** (Memcached, plus simple) — 1 session
6. **N4** (bitstrings P3) — 1-2 sessions
7. **P1** (Bitcask) — 1-2 sessions
8. **M2-M4** (Diameter, AMQP, Cassandra) — 8-10 sessions
9. **P2-P3** (Vector DB + IA) — 4-6 sessions
10. **B1** (bootstrap) — 3-5 sessions

**Total estime** : 25-35 sessions.

## Non-objectifs V0

- TLS en Heaven pur (OpenSSL suffit)
- Cassandra auto-heberge (Bitcask d'abord)
- IA en Heaven pur (ONNX d'abord)
- Support Windows/macOS serveur (Linux seulement V0)

## Annexes : exemples en infixe

### N1 -- TCP client

    -- stdlib/net.hvn (infixe)
    net_connect host port =
      @net_connect (string_ptr host) port

    -- usage
    fd = net_connect "example.com" 80
    req = "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n"
    io_write fd (string_ptr req) (string_length req)
    resp = io_read fd buf 65536

### T2 -- HTTP client

    -- stdlib/http_client.hvn (infixe)
    http_get url =
      let host, path = parse_url url in
      let fd = tls_connect host 443 in
      let req = build_request "GET" path host in
      let _ = tls_write fd req in
      let resp = tls_read fd 65536 in
      parse_response resp

### M1 -- Memcached client

    -- stdlib/memcached.hvn (infixe)
    mc_get conn key =
      let _ = send conn ("get " + key + "\r\n") in
      recv_value conn

    mc_set conn key value =
      let _ = send conn ("set " + key + " 0 0 " + (length value) + "\r\n") in
      let _ = send conn (value + "\r\n") in
      recv_status conn

## Style

Tout le code de ce roadmap (et des futures implementations) est en
**notation infixe** quand l'operateur est binaire. Voir
`_style_infix.md`.

## D-SH4 — Pas de Zig std pour la metacircularite (2026-10-15)

**Regle** : `raw_syscall*` au lieu de `std.posix.*` pour tout code
portable en Heaven. Zig std reserve au host (alloc, debug, FFI C).

**Impact** :
- N1 : refactor `std.posix.socket/connect/read/write` -> `raw_syscall6`
- N2 : DNS pur Heaven (UDP + parse), pas `std.net.getAddressList`
- N4 (bitstrings P3) : prerequis pour N2
- T1 (TLS) : OpenSSL FFI accepte (C, pas Zig std)

Voir `DECISIONS.md` (D-SH4).
