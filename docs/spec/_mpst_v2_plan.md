<!-- HEAVEN:mpst-v2-plan -->
# MPST V2 — multipartite (plan 2026-10-19)

## État

V0+V1-runtime commités :
- `stdlib/mpst.hvn` : dualité + checker binaire (10 tests).
- `mpst_trace(pid)` (magic engine) : trace des labels runtime.
- `trace_of_string` : parse la trace.
- Bout-en-bout testé : `check(proto_client, trace_of_string(mpst_trace(pid)))`.

## Ce que V2 demande

1. **Multipartite** : `protocol P = A -> B : Msg. B -> C : Msg2. end`
   (plus de 2 parties). Projection `project(P, role)` pour
   extraire le protocole local de chaque participant.
2. **Rôles explicites** : `send role msg` / `recv role` au lieu de
   `tell pid msg` / `recv pid`. Le scheduler n'a pas de notion de
   rôle aujourd'hui.
3. **Checker en ligne** : brancher `check` sur les transitions
   runtime (au lieu de post-hoc). Nécessite un hook `send`/`recv`
   qui vérifie le label contre le protocole courant.
4. **Récursion** : `μX. ... X` (boucles de protocole).

## Effort

- V2a (multipartite + projection) : 2 sessions.
- V2b (checker en ligne + rôles) : 1-2 sessions.
- V2c (récursion) : 1 session.

**Total : 4-5 sessions.**

## Ordre recommandé

1. **V2a** : étendre `stdlib/mpst.hvn` (ST multipartite +
   `project`). 100% Heaven, testable sur fixtures.
2. **V2b** : ajouter `send`/`recv` au scheduler avec rôle. Nécessite
   `_concurrency.md` (C1-C5) stabilisé, donc après effects-consolidation.
3. **V2c** : récursion.

## Prérequis
- effects-consolidation (sémantique perform/handle cohérente).
- C1-C5 de `_concurrency.md` tranchées (stackful vs stackless,
  migration Store, préemption reprenable).
