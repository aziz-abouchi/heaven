# Bug parser : magics 0-arg en RHS de let

**Date** : 2026-10-15

## Symptome

`(@net_socket_udp)` seul (0-arg) est strippe en symbole, pas
evalue comme appel. Marche uniquement en argument direct.

## Workaround

Donner 1 argument dummy ignore : `(@net_socket_udp 0)`.

## Fix propre (dette)

evaluate(.sym) : si magic 0-arg, evaluer le handler directement.
Effort : 30-60 min. Basse priorite (workaround OK).
