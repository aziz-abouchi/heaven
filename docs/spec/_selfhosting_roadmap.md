<!-- SESSION 2026-10-30 (soir) : 9 tags selfhost poussés -->

> **Mise à jour 2026-10-30 (soir).** Le selfhost natif **fonctionne**
> : `bin/heaven.hvn` → ELF x86_64 (QBE), affiche du texte via glibc
> puts, lit `@argv` (ABI SysV), dispatch CLI via `@strcmp`. 9 tags
> poussés (`qbe-main-fix` → `selfhost-dispatch-v0`). Voir
> `docs/book/src/39-selfhosting.md` et l'annexe G (G.25 → G.34).
> Prochains chantiers : G.33 (argv fn user), G.34 (strcmp fn user),
> multi-clauses merge, mir_wat (WASM selfhost), heaven_eval.hvn.

---

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

### N4bis -- clarification (2026-10-15)

**Fausse dette** : les 4 copies du desugar bitstring ne sont PAS
4 fois la meme chose.

| Fichier | Rôle |
|---|---|
| heaven_expr.zig:621 | **Destructuration** (P1/P3) |
| commands/defs.zig:159 | **Destructuration** (P1/P3) |
| parse.zig:51 | **Construction** (P2) |
| expr_parser.zig:46 | **Construction** (P2) |

Seule la **destructuration** a besoin de `/little` et
`rest:bits`. Les 2 copies de construction sont OK telles quelles.

**Feature différée** : construction avec `/little`
(`<<0x12:16/little>>` → `0x3412`). Non-spécifiée, non testée,
non-bloquante. À traiter si un protocole l'exige.

**Dette restante** : les 2 copies de destructuration sont
identiques (heaven_expr + commands/defs). À centraliser en
helper partagé. Effort : 30 min. Priorité : basse.

### N2 -- DNS partiel (2026-10-16)

**Livre** :
- stdlib/dns.hvn : dns_build_header (12 bytes), dns_qname_a_com
  (7 bytes), dns_qtype_class (4 bytes), dns_build_query (23
  bytes), dns_resolve_a_com.
- Magic @net_set_timeout (SO_RCVTIMEO).
- Tests : query 23 bytes OK, DNS response timeout.

**Bloque par l'environnement** : sandbox Guix bloque UDP entrant.
Verification : Python sendto OK, recvfrom TIMEOUT sur 8.8.8.8:53
et 1.1.1.1:53. Notre code est correct (meme comportement que
Python).

**Tests futurs** : sur un VPS sans sandbox, dns_resolve_a_com
devrait recevoir la reponse. Parser la reponse est l'etape V1.

**V1** :
1. Generaliser a un nom variable (dns_encode_name).
2. Parser la reponse avec bitstrings P3 (extraire l'IP A).
3. Tests sur VPS.

**Pourquoi c'est OK** : le code est correct, la sandbox seule
bloque. N2 debloque quand on teste sur VPS.

## Notes Session 48 (2026-11-10)

### A1 — QBE/TCC CI (fermé `a2a929a`+)

- `HEAVEN_STRICT_QBE=1` active l'échec dur si QBE absent.
- `ci-preflight.sh` vérifie QBE avant build.
- Test clone frais confirmé : `build.sh` construit QBE (~5 min).

### A2 — matrice réelle des 4 `.skip` (Session 48, corrigé)

**Correction** : la note précédente (warn `0xDEADBEEF` masqué)
était erronée. `test_mir_qbe.zig:171` (`.name = 0xDEADBEEF`)
est un **test intentionnel** (`"qbe — rejet : call_user hors
fn_defs"`). Le warning est exigé par le test. À durcir sous
`HEAVEN_STRICT_QBE=1` en B3, **pas en A2**.

Matrice réelle mesurée (Session 48) :

| Cas | Interp | QBE | Verdict |
|---|---|---|---|
| `(pair 1 2)` | retourne `(pair 1 2)` | `855229088` (offset) | Cassé des deux côtés |
| `(string_concat "hello" "world")` | `"helloworld"` ✓ | `error.UnsupportedOp` | Interp OK, QBE unsupported |
| `(let f (lambda x (+ x 1)) (f 41))` | `(f := (lambda ...))` (bind non évalué) | `error.UnsupportedOp` | Interp cassé (let-chain) + QBE unsupported |
| `data Color = Red \| Green ; Green` | `Green` ✓ | `1` (+ warn sym=336 cosmétique) | ✓ enum OK des deux côtés |

**Enum Color fonctionne**, interp et QBE. Le warn `sym=336` est cosmétique (résultat correct). **A2b ne concerne que `pair`.**

**Révision d'estimation A2** (plan disait 1-2 sessions) :

| Sous-bloc | Effort réel |
|---|---|
| A2a Closures | **2-3 sessions** — interp `let-chain` cassé + QBE unsupported |
| A2b Ctors (pair + enum) | **1-2 sessions** — pair cassé des deux côtés |
| A2c String QBE | **0,5-1 session** — `string_concat` à implémenter |
| **Total A2** | **3-6 sessions** |

**Bug préalable à A2a** : `(let f (lambda …) (f 41))` retourne
`(f := …)` — le `let-chain` en S-expr n'est pas évalué. C'est le
bug documenté dans `status.json` (2026-10-19) : `normalizeLetChain`
fixe le top-level direct, pas la forme parenthésée.

**Ordre suggéré** (à valider par test enum) :
1. A2b (ctors, si enum OK en QBE) : 1 session
2. A2a-préalable (let-chain bug) : 0,5 session
3. A2a (closures) : 1-2 sessions
4. A2c (string QBE) : 0,5 session


---

## B1b — correction du diagnostic (2026-11-10, session 48 bis)

**Statut** : B1a fermé (`2d2c505`). B1b **cadré, non commencé**.

### Ce que B1a a livré

Wrapper `parse` : lex + parse_one + EOF check. Fonctionne sur les
S-expr purs. `(P.parse "(+ 1 2)")` → `(POk AST TNil)`.

### Erreur du plan B1b.1 (`parse_file` seul)

**Formulation erronée** dans la version initiale du plan :
« B1b.1 = parse_file, 30 min, fait passer 01/02/06 ».

Faux. Les 3 fichiers (01-arith, 02-fib, 06-mutual) ne sont **pas**
des suites d'expressions préfixes. Ils utilisent la syntaxe de
surface `fn sum_squares(n, acc) = ...` — arguments parenthésés
séparés par virgules, keyword `fn`, `=`. Un `parse_file` en boucle
naïve produirait `POk` avec un AST absurde (`fn`, `sum_squares`,
`(n, acc)`, `=` traités comme des expressions séparées), **sans
erreur**. Faux positif, pas jalon.

### Critère de sortie B1b (corrigé)

**Ne pas accepter `POk` comme preuve.** Le critère doit être
**égalité d'AST avec le parseur de référence Zig**.

Prérequis : un format de dump S-expr canonique stable. `heaven
parse` affiche un AST, mais il n'expose pas (à ce jour) de
sérialisation S-expr comparable. **Chantier préalable** : ajouter
`heaven parse --dump-sexpr` ou équivalent, côté Zig, pour servir
de référence.

### Ce que B1b représente réellement

Le parseur actuel (`lib/heaven_parse.hvn`) est un **parseur S-expr**,
pas un parseur de la syntaxe Heaven. `lib/heaven_parse.hvn` lui-même
contient 6 `data` et des multi-clauses — il **ne peut pas se parser
lui-même**. C'est un jalon révélateur : « le parseur Heaven analyse
son propre code » est la vraie cible.

Sous-ensembles manquants :

| Feature | Fichiers `lib/` concernés | Effort |
|---|---|---|
| `parse_file` (boucle multi-expr) | 0 (aucun lib n'est S-expr pur) | 30 min |
| `data X = A \| B` | 14/32 | 0,5-1 session |
| `import "path" as M` | 13/32 | 0,5 session |
| Multi-clauses (`f x = 1` / `f y = 2`) | 29/32 | 1 session |
| `fn name(a, b) = body` (surface) | 3 tests diff (01/02/06) | 1 session |
| **Total B1b réaliste** | | **3-5 sessions** |

**Correction d'estimation** : le plan `ROADMAP.md` disait
« B1 = 1-2 sessions ». C'est **bas**. `_selfhosting_roadmap.md`
disait « 3-5 sessions » — **correct**.

### Deux voies stratégiques à trancher

**Voie P (parseur de surface d'abord)** — plan actuel Phase B :
B1 (parseur complet) → B2 (eval) → B3 (MIR/QBE Heaven) → B4 (fixpoint).

- Avantage : fidèle à la feuille de route initiale.
- Coût : 3-5 sessions **avant** d'écrire la moindre ligne de
  génération de code en Heaven. Aucune preuve de capacité avant
  B3.

**Voie C (fin de chaîne d'abord)** — alternative :
1. Le parseur **Zig** continue de produire Core (6 primitives).
2. Écrire en Heaven le **MIR + émission QBE**, lisant le Core
   depuis un dump S-expr stable (à produire côté Zig).
3. Écrire ensuite l'**évaluateur** Heaven sur le même Core.
4. Écrire le **parseur de surface** en dernier.

- Avantage : la **preuve de capacité** (génération de code
  identique) est obtenue plus tôt. Un compilateur Heaven qui
  génère du QBE byte-identique au compilateur Zig est un
  jalon démontrable **avant** d'avoir un parseur de surface
  complet.
- Coût : ordre non-standard, mais `_selfhosting_roadmap.md`
  documentait déjà cette possibilité.

**La voie C exige le dump S-expr canonique** (même prérequis que
le critère de sortie B1b). **Ce dump est à construire en priorité**
avant B1b ou C — ~1h côté Zig.

### Décision

À trancher au démarrage de la session 49 :

- **P** : B1b complet (3-5 sessions). Suit le plan `181be95`.
- **C** : dump S-expr + B3 (MIR/QBE Heaven) d'abord. Preuve de
  capacité plus tôt, parseur de surface en dernier.

Le dump S-expr canonique est **commun aux deux voies**. À faire
en premier, quelle que soit la décision.

### Correction de cohérence `ROADMAP.md`

`181be95` a réordonné les priorités en mettant Phase A+B en tête,
mais `_selfhosting_roadmap.md` garde B1 à « 3-5 sessions » et
classe le bloc Bootstrap en dernier (#10/10). Les deux documents
doivent être alignés à la session 49 :

- `ROADMAP.md` doit refléter B1b = 3-5 sessions (pas 1-2).
- Le bloc « Bootstrap » (B4 fixpoint) doit être positionné
  cohéremment (fin de Phase B, pas #10).

