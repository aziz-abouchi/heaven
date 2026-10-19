<!-- HEAVEN:mpst-plan -->
# MPST — Multiparty Session Types (plan)

## V0 livré (2026-10-19, commit à venir)

`stdlib/mpst.hvn` (52 l.) : algèbre + checker, sans runtime.

| Élément | Sémantique |
|---|---|
| `STEnd` | fin de session |
| `STSend l rest` | émission du label `l` |
| `STRecv l rest` | réception du label `l` |
| `STSeq a b` | séquence |
| `STChoice a b` | choix (une des deux branches) |
| `dual st` | duale binaire (send↔recv) |
| `check st trace` | trace conforme au protocole ? |

Tests : `tests/test_mpst.hvn` (10 cas : dualité, involution,
check ok/bad/truncated, end, choice).

## V0 — limites

- **Binaire seulement** (2 parties). Pas de multipartite (>2).
- **Pas de récursion** (pas de `μX. ... X`).
- **Pas de runtime mailbox** : `send`/`recv` ne sont pas des primitives
  du scheduler (qui n'a que `add_task`/`yield`/`state` partagé).
  Le checker valide une trace post-hoc, pas en ligne.

## V1 — nécessite un runtime mailbox

1. **Ajouter `send`/`recv`** au scheduler (mailbox par acteur).
2. **Instrumenter `send`/`recv`** pour produire une trace au runtime.
3. **Checker en ligne** : `check` appelé à chaque étape (fail-fast).
4. **Multipartite** : `STSendTo role label`, `STRecvFrom role label`,
   projection `project(P, role)`.
5. **Récursion** : `STMu`, `STVar`, `check` avec environnement.

Effort V1 : 2-3 sessions (mailbox + multipartite + recursion).

## Lien avec `_concurrency.md`

`_concurrency.md` mentionne MPST sans l'implémenter (sections
"protocole", "session"). Ce module est la **fondation algébrique**
avant que le scheduler ne fournisse le runtime.

## Cas d'usage

- Vérifier qu'un client HTTP respecte `!Req.?Resp.end`.
- Vérifier qu'un serveur respecte le dual.
- Base pour WebRTC (handshake SDP = protocole de session).
- Base pour Diameter (protocole multi-étapes).
