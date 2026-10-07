# Annexe B — Erreurs courantes

Cette annexe recense les erreurs que renvoie Heaven, ce qu'elles
signifient, et comment les corriger.

## Erreurs d'evaluation

### `error.ArityMismatch`

Le nombre d'arguments ne correspond pas a la definition.

    (f 1 2 3)   -- f attend 2 args

**Causes** : appel avec le mauvais nombre d'args, constructeur
applique avec un arite differente, magic appele sans ses arguments.

**Correctif** : verifier `:info <nom>` ou la definition.

### `error.UnknownSymbol`

Un symbole (nom) n'est pas defini : ni dans le prelude, ni dans le
code, ni dans l'environnement.

    (foo 5)   -- foo non defini

**Causes** : typo, nom oublie, mauvais module.

**Correctif** : `:defs` pour lister les noms disponibles, ou
importer le module concerne.

### `error.TypeError`

Le type de l'argument est incompatible avec l'operation.

    (+ 1 "hello")   -- addition entre int et string

**Causes** : arguments de types differents, comparaison
incompatible.

**Correctif** : verifier les types avec `:t <expr>`.

### `error.UnboundVariable`

Une variable liee dans une expression n'est pas dans l'environnement.

    (let x 5 (y 1))   -- y n'existe pas

**Causes** : `let` mal utilise, variable non liee, scope mal ferme.

**Correctif** : verifier les niveaux de `let`.

### `error.InvalidInput`

L'entree est mal formee (chemin, handle, bytecode).

    (io_read 9999999 0 10)   -- handle invalide

**Correctif** : verifier la source (fd, fichier, ...).

### `error.RecursionLimitExceeded`

Limite de profondeur (1000 frames par defaut) atteinte.

**Cause** : recursion non tail sans cas de base, donnees cycliques.

**Correctif** : cas de base manquant, TCO (self-tail-call).

### `error.SuspendRequested`

Safepoint : budget de reductions epuise. Interne (utilise par
`evalWithBudget`).

## Panics (bugs de l'interpreteur)

Si vous voyez un panic, c'est un bug de Heaven, pas de votre code.

### `integer overflow` sur `depth -= 1`

Sur `)` orpheline. Corrige en 2026-10-07 par guard `if (depth > 0)`.

### `poison Id at evaluate entry`

`0xAAAAAAAA` a ete passe comme Id. Bug interne.

## Erreurs du runner de test

### `'==' manquant`

Le runner de test exige un operateur `==` explicite dans le body.

    test "x": (> 3 0)              -- ✗ '==' manquant
    test "x": (> 3 0) == true      -- ✓

### `':' manquant apres le nom`

Format attendu : `test "nom": expr`. Deux-points **colle** au nom.

    test "foo" : expr   -- ✗ (espace avant ':')
    test "foo": expr    -- ✓

### `operateur '==' manquant`

Identique a `'==' manquant`, message different.

## Quirks du parser

### `-100` tokenise en `-` + `100`

Les litteraux negatifs doivent s'ecrire `(- 0 100)`, pas `-100`.

    (raw_syscall 257 -100 0 0 0 0 0)   -- ✗
    (raw_syscall 257 (- 0 100) 0 0 0 0 0)   -- ✓

### `/` dans les chemins

`"/tmp/foo.txt"` en clair est lu comme `(/ (/ " tmp) foo.txt")`.

**Correctif** : utiliser un chemin relatif (`"foo.txt"`) ou quoter
le chemin (`(quote "/tmp/foo.txt")`).

### `(let x "string" x)` affiche verbatim

Un `let` dont la valeur est une chaine est renvoye tel quel (bug
parser). Workaround : lier la chaine a un symbole.

### `let ... in` multi-lignes

Le body d'une equation doit etre sur **une seule ligne** ou etre
un S-expr parenthese.

    read_all u =
      let fd = io_open "f" in     -- ✗ multi-lignes
      ...

    read_all u = (let fd (io_open "f") (io_read fd buf 16))   -- ✓

## Voir aussi

- `docs/spec/_syntax_gaps.md` : liste detaillee des gaps parser.
- `docs/DECISIONS.md` : decisions structurantes.
