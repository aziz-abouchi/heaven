# Reseau : decoupage OSI

**Date** : 2026-10-15
**Statut** : analyse. Aucune implementation.

## Couches couvertes

| Couche OSI | Protocole | Etat Heaven |
|---|---|---|
| 7 Application | HTTP | ✅ core/http.hvn, _http.md |
| 7 Application | WebSocket | Planifie |
| 4 Transport | TCP | ✅ via syscalls |
| 4 Transport | UDP | Planifie |
| 3 Reseau | IP | Planifie |
| 2 Liaison | Ethernet | Hors scope |

## Bitstrings (RFC-0002)

Les en-tetes IP (20 octets, champs non alignes) sont le cas
d'usage principal des bitstrings. Voir RFC-0002.md.

## Plan

1. P3 bitstrings (non aligne) debloque IP.
2. Parser IP en Heaven (stdlib/ip.hvn).
3. Parser TCP/UDP (stdlib/tcp.hvn).
4. HTTP/2 frames (bitstrings).
