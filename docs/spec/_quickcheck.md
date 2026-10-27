# Quickchecker — design

**Date** : 2026-10-27
**Statut** : v1 livrée (PRNG pur + `check` minimal), v2 backlog.

## V1 — Property-based testing minimaliste

`core/std/quickcheck.hvn` fournit :

- `next seed` : PRNG pur (Lehmer MINSTD, a=16807, m=2^31-1).
- `gen_int seed` : entier dans [0, 2^31-2].
- `gen_bool seed` : Bool.
- `gen_range lo hi seed` : entier dans [lo, hi].
- `check prop gen n` : exécute `prop` sur `n` valeurs générées.

Aucune ligne Zig. Déterministe (seed initial = 1). Reproductible.

## Exemple

    test "x + 0 = x":
      (check (lambda x -> (= (+ x 0) x)) (lambda s -> (gen_int s)) 100) == true

## Limites v1

- Pas de shrinking : en cas d'échec, `check` retourne `false`, sans
  dire quelle valeur a échoué.
- Seed non configurable : `check` démarre toujours à 1.
- Pas d'intégration avec les lois (`tests/test_laws.hvn`).
- PRNG Lehmer : suffisant pour du test, pas pour la crypto.

## V2 (backlog)

- `check_debug` : retourne (Bool, valeur_fautive).
- Shrinking automatique (logique pure Heaven).
- Générateurs de structures : `gen_list`, `gen_option`, `gen_pair`.
- Seed configurable.
- Intégration `tests/test_laws.hvn`.

## Lien avec Smocker

Même philosophie : 100% Heaven, minimal, honnête sur les limites,
v2 planifiée comme chantier séparé. Voir `docs/spec/_smocker.md`.
