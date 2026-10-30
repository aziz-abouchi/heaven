# Tooling — Introspection runtime

> `@runtime_stats` retourne processes + process_mem.

## API

    (@runtime_stats "x")
    -- → "{\"mem_kb\": X, \"processes\": Y, \"process_mem\": Z}"

- `processes` : `engine.processes.count()`
- `process_mem` : `@sizeOf(Process) + mailbox.capacity + trace + links`
- `mem_kb` : `process_mem / 1024`

## Remplace un stub

Avant 2026-10-30, `@runtime_stats` retournait :

    const stats = "{\"mem_kb\": 1024, \"egraph_nodes\": 42}";

Toute métrique basée dessus était fausse.

## Limites

- `range` n'existe pas (G.6) → benchmarks manuels
- Peak mem (heaven test) = RSS OS, pas les allocations
- Pas de `@mailbox_size pid`

## Comparaison Erlang (théorique)

| Aspect | Heaven | Erlang |
|---|---|---|
| Process struct | ~96-120 o | ~2.6 KB |
| Heap par process | Non (Id → Store) | Oui |
| Stack par process | Non | Oui |
| Total estimé | ~120-150 o | ~2.6 KB |

Théoriquement 15-20× plus léger, non vérifié (range absent).
