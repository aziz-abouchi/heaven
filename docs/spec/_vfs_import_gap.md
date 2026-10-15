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

## Tests REPL supplementaires (2026-10-15 16h45)

| Commande | Resultat |
|---|---|
| :import core/std/list.hvn as L | UnboundVariable |
| :load core/std/list.hvn as L | UnboundVariable |
| :i core/std/list.hvn as L | UnboundVariable |

**Conclusion definitive** : aucune syntaxe REPL ne permet
l'import. Le dispatch REPL n'expose pas `import` comme commande.
C'est un MANQUE, pas un bug.

## Fix recommande (session dediee)

Ajouter dans src/core/commands/dispatch.zig une commande `:load` :

    :load <path> as <Name>

Qui appelle le meme code que le parser fichier :
1. Lit le fichier via platform.fs.cwd().readFileAlloc (VFS).
2. Parse via heaven_parse.
3. Lie le resultat sous <Name> dans l'env global.

Effort : 30 min.

Alternative minimale : documenter que l'import se fait par
fichier .hvn, pas dans le REPL web. Le REPL reste utile pour
evaluer des expressions.
