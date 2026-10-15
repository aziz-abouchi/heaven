# VFS + import REPL : ecart identifie

**Date** : 2026-10-15
**Statut** : VFS fonctionnel, syntaxe import REPL differente.

## Ce qui marche

- vfs.js charge 85 fichiers .hvn (log "[vfs] 85 fichiers charges").
- platform.fs.readFileAlloc ET Dir.readFileAlloc branches sur VFS.
- Au demarrage, bootstrap lit core/bootstrap.hvn, core/io.hvn, etc.
- REPL evalue les expressions : `(+ 1 2)` -> 3.

## Ce qui ne marche pas

Dans le REPL :
    heaven> import "core/std/list.hvn" as L
    eval error: error.UnboundVariable

Mais `import` est reconnu (test `import list` -> ArityMismatch).

## Diagnostic

| Commande REPL | Resultat |
|---|---|
| (+ 1 2) | 3 |
| (import "core/std/list.hvn") | ArityMismatch |
| import list | ArityMismatch |
| import core/std/list.hvn | UnboundVariable |
| import "..." as L | UnboundVariable |

**Conclusion** : dans un fichier .hvn, `import "..." as L` est
parse par le parser de fichiers. Dans le REPL, `import` est
traite comme une commande (dispatch cmd/args), et la syntaxe
`as L` n'est pas supportee.

## Piste fix

Deux options :
1. Etendre le parser REPL pour supporter `import "path" as L`
   (probablement dans src/core/commands/dispatch.zig).
2. Ou documenter une commande REPL dediee : `:load path as L`.

La deuxieme option est plus simple et explicite. Elle peut
reutiliser le code du parser fichier sans toucher au dispatch.

## Effort

- Option 2 : 30 min.
- Option 1 : 1-2h (parsing plus complexe).

## Voir

- src/vessel/public/vfs.js
- src/platform/wasm32_freestanding.zig (Dir.readFileAlloc)
- src/core/commands/dispatch.zig
