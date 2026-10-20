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

### Préfixes réservés (BUG corrigé 2026-10-19)

Toute ligne commençant par `help`, `stats`, `theorems`, `rules`
(minuscule, sans espace) était traitée comme **commande REPL** et
non évaluée. Donc `helper _ = 42` silencieusement skippé.

**Corrigé** : match exact (`help`) ou préfixe avec espace
(`help ...`). Les fonctions `helper`, `statistics`, `rules_engine`
marchent maintenant.

**Noms encore réservés** (à éviter en début de ligne) : `type `,
`green ` (avec espace), `let ` (début de def), `import `,
`class `, `instance `, `sig `, `module `, `strict `, `theorem `,
`prove `, `skill `, `export `, `meta `.

### `let` chainé (B3, partiellement fixé 2026-10-19)

`let a = 1 in let b = 2 in body` **ne marchait pas** avant le
2026-10-19 (body brut non reconverti, AST non évalué).

**Fixé** : `heaven run script.hvn` avec let-chain 2-3 niveaux
(`66f0b32`, `normalizeLetChain`).

**Toujours cassé** :
- `.hvn` helper `f _ = (let a = 1 in let b = 2 in body)`.
- `let` en argument de S-expr : `(+ (let a 1 in a) (let b 2 in b))`.
- **Pattern `_` dans une def + `heaven run`** : `helper _ = 42`
  puis `(helper 0)` -> `ArityMismatch`. Bloque E4b (serveur HTTP
  en `.hvn`).

**Workarounds** :
- Écrire `fn` + `seq` : `fn f _ = (seq e1 (seq e2 e3))`.
- Ou S-expr nested : `(let a 1 (let b 2 body))`.
- Voir `docs/tutorials/no_let_chain.md` (tuto complet) et
  `docs/spec/_let_chain_bug.md` (diagnostic).

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

### `string_eq` en condition d'`if` dans helper local — SIGSEGV

Tout `if (string_eq a b) then ... else ...` dans un helper local
crashe par SIGSEGV (2026-10-19). Idem `S.string_eq` importé
qualifié, et `string_ends_with` en condition.

    f p = if (string_eq p "/") then "a" else "b"    -- ✗ SIGSEGV

**Workaround** : `==` infixe.

    f p = if p == "/" then "a" else "b"            -- ✓

**Autres contraintes parser** (mêmes symptômes) :
- `let` chain ≥ 3 niveaux dans helper → valeur fausse silencieuse.
- `let` chain 2 max.
- Helpers ordonnés (définition avant usage, pas de forward ref).

Voir `docs/spec/_http_fullstack_plan.md` section "E4-D2bis" pour
le diagnostic chirurgical complet.

### Mots reserves (collisions silencieuses)

Les identifiants suivants sont interceptes par le parser avant l'eval
de vos definitions. Une fonction du meme nom ne sera **jamais appelee**
(silencieusement) :

- `data`, `sig`, `theorem`, `prove`, `skill`, `module`, `import`,
  `strict`, `export`, `class`, `instance` : declarations.
- `type`, `green`, `help`, `stats`, `theorems`, `rules` : commandes REPL
  (mais match exact, donc `helper` marche depuis le fix 2026-10-19).
- `query` : pipeline kanren (heaven_expr.zig:1261). `query foo bar`
  ajoute une requete au KB, n'appelle pas votre fonction.
- `fact` : pipeline kanren. `fact 0 = 1` ajoute un fait, n'appelle pas
  votre fonction.
- `perform`, `handle`, `handle_rec`, `resume`, `yield` : effets.
- `let`, `if`, `then`, `else`, `in` : mots-cles.

**Workaround** : prefixer. `kb_query`, `my_fact`, `do_help`, etc.
Voir `stdlib/ontology.hvn` (prefixe `kb_`) et `04-recursion.md`
(`fac` au lieu de `fact`).

