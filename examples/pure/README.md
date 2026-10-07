# examples/pure — Heaven pur

Exemples **qui fonctionnent** avec les features actuelles de Heaven.

## Ce qui marche (utilise ici)

- `data Name = C1 | C2 arg` : types et constructeurs.
- Équations multi-clauses : `f C1 x = ...` / `f C2 x = ...`.
- Constructeurs 0-arity comme patterns (`Linux`, `OpWrite`).
- Wildcard `_` en pattern.
- Import qualified : `import "x.hvn" as M` puis `M.ctor`, `M.fn`.

## Ce qui NE marche PAS (et n'est donc pas ici)

- `match x with | A => B` : n'existe pas. Utiliser équations.
- `inline_qbe "..."` : n'existe pas. Pas d'assembly inline.
- `@syscall(...)`, `@extern("c", ...)` : n'existent pas.
- Types `Ptr`, `Fd`, `Buf` : n'existent pas.
- `linear` en argument : non supporté.

Voir `examples/vision/` pour les specimens de la direction
architecturale (features manquantes documentées).

## Tester

    ./zig-out/bin/heaven run examples/pure/demo.hvn

Doit afficher `1` (syscall WRITE sur Linux x86_64).
