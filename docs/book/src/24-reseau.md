# Chapitre 24 — Réseau : parler au monde

Jusqu'ici, Heaven vivait seul. Il calculait, prouvait, mais ne
parlait à personne. Ce chapitre change cela : le langage sort
de sa bulle.

## 1. Le saut conceptuel

Un langage qui ne parle pas au réseau n'est pas un langage. C'est
un calculateur. Dès qu'il peut ouvrir une socket, résoudre un nom,
envoyer un octet, il devient un **outil**.

Heaven V0 sait maintenant :

- **TCP client** — se connecter à un serveur.
- **UDP** — envoyer des datagrammes.
- **Bitstrings non alignés** — parser des en-têtes binaires.

## 2. TCP client

    net_connect cap ip port =
      @net_connect cap ip port

    fd = net_connect cap "1.1.1.1" 80

Le file descriptor retourné est un entier >= 0. `-1` signifie
échec. Aucune dépendance Zig : le syscall `connect` est appelé
directement (D-SH4).

**Test** : `test_http.hvn` valide 13 cas. Le client parle à
Cloudflare (`1.1.1.1:80`) en sortie Internet.

## 3. UDP

    net_socket_udp cap = @net_socket_udp cap
    net_sendto cap fd ip port data = @net_sendto fd ip port data

UDP est **sans connexion**. Pas de handshake. Idéal pour DNS
(port 53), NTP, QUIC, etc.

## 4. Bitstrings non alignés

Le vrai déblocage. Un en-tête DNS fait 12 octets avec des champs
non alignés :

    <<id:16, flags:16, qdcount:16, ancount:16, nscount:16, arcount:16>> = header

Un en-tête IPv4 :

    <<version:4, ihl:4, tos:8, total_len:16, ...rest:bits>> = ip_packet

Le parser génère des shifts et des masques pour chaque segment.
74 tests valident les cas non alignés (3+5+8, 12+4, 4 nibbles),
l'endianness (`/little`), et `rest:bits`.

## 5. La cible : DNS pur Heaven

L'objectif final : résoudre `"google.com"` en une IP, en pur
Heaven.

    dns_resolve "google.com"  -- -> "142.250.75.14"

Cela demande :
- construire une query (header + QNAME + QTYPE)
- envoyer via UDP à 8.8.8.8:53
- recevoir la réponse
- parser avec bitstrings

**État** : UDP socket opérationnel. Constructeur bloqué par
l'absence d'escape `\x` dans les strings (voir
`docs/spec/_string_escape_gap.md`). Workaround : `poke_byte`.

## 6. Zéro dépendance Zig (D-SH4)

Règle structurante : **le code portable n'utilise pas `std.posix`**.
Tout passe par `raw_syscall` ou `std.os.linux.syscall`. Pourquoi ?
Parce que ces appels seront un jour portés en Heaven pur. Si on
utilise `std.posix.socket`, on ne peut pas.

Les wrappers Zig std sont autorisés pour le **host** (terminal,
allocator, FFI C comme OpenSSL).

## Ce qu'on a appris

- Un langage sans réseau n'est qu'un calculateur.
- TCP client = `socket` + `connect` + `read`/`write`.
- UDP = `socket` + `sendto`/`recvfrom`, sans connexion.
- Les **bitstrings non alignés** sont la clé des protocoles binaires.
- **Zéro Zig std** dans le code portable : le futur self-hosting
  dépend de cette discipline.

*Vérifiable : N1 5/5, HTTP 13/13, UDP 2/2, P3 74/74.*
