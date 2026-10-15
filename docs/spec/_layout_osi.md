# Reseau : decomposition OSI en couches .hvn

**Date** : 2026-10-15
**Statut** : analyse. Implementation progressive.

## Couche 7 (Application)
- core/http.hvn — serveur HTTP statique natif (D30)
- core/http_server.hvn — serveur HTTP complet
- stdlib/websocket.hvn (planifie)
- stdlib/dns.hvn (planifie)

## Couche 5-6 (Session / Presentation)
- core/tls.hvn (planifie)
- Serialization : Bitstrings RFC-0002 (voir _syntax_gaps.md)

## Couche 4 (Transport)
- stdlib/net.hvn — primitives @net_* (syscalls bas niveau)
- stdlib/tcp.hvn (planifie)
- stdlib/udp.hvn (planifie)

## Couche 3 (Reseau)
- stdlib/ip.hvn (planifie) — debloque par bitstrings P3
  (en-tetes IP 20 octets, champs non alignes)

## Couche 2 (Liaison)
- stdlib/ethernet.hvn — hors scope V0

## Mapping avec l'existant

| Fichier | Couche |
|---|---|
| core/io_stream.hvn | abstraction fd (4-7) |
| core/http.hvn | 7 |
| core/http_server.hvn | 7 |
| stdlib/net.hvn | 4 (syscalls) |
| stdlib/fs.hvn | hors OSI (stockage local) |
| stdlib/json.hvn | 6 (presentation) |

## Plan

1. Spec (ce document).
2. Bitstrings P3 (non aligne) -> debloque IP.
3. stdlib/ip.hvn, stdlib/tcp.hvn, stdlib/udp.hvn.
4. stdlib/websocket.hvn, stdlib/dns.hvn.

## Decision

Ne PAS mettre tout le reseau dans un seul fichier. Une couche
= un fichier, avec API claire en entree/sortie.
