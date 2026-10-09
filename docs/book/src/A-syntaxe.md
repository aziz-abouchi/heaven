# Annexe A — Syntaxe complète

Référence rapide de la syntaxe Heaven. Utile quand on cherche un
détail précis.

## Commentaires

    -- commentaire sur une ligne
    # commentaire à l'ancienne (accepté)
    ;; aussi accepté
    // aussi accepté

## Nombres

    42              -- entier décimal
    0xFF            -- entier hexadécimal (255)
    0x10            -- hexadécimal (16)
    3.14            -- flottant
    -7              -- négatif (unaire)

Le préfixe `0x` (ou `0X`) marque un littéral hexadécimal. Les chiffres
`0-9`, `a-f`, `A-F` sont acceptés après le préfixe.

Les nombres négatifs doivent être parenthésés en position d'argument :
`(- 3)`, pas `- 3`.

## Chaînes

    "bonjour"
    "avec \"échappement\""
    "multi
    ligne"

## Booléens et Unit

    true
    false
    ()              -- Unit, l'unique valeur de son type

## Symboles

Un symbole est un nom. Les identifiants commencent par une lettre ou
un `_`, et peuvent contenir des chiffres :

    x
    maVariable
    _interne
    add2

Les symboles se résolvent dans l'environnement (voir `let`) ou
restent symboles nus.

## Opérateurs infixes

    +    -    *    /    %       -- arithmétique
    ==   !=   <    >    <=  >=  -- comparaison
    ^                            -- puissance
    >>>                          -- composition de fonctions

Précédence, du plus faible au plus fort :

1. `>>>`
2. `+` `-`
3. `*` `/` `%`
4. `^`
5. application (juxtaposition)

L'application lie plus fort que tout. `f x + 1` se lit `(f x) + 1`.

## Application

    f x             -- application simple
    f x y           -- f appliqué à x puis au résultat à y
    f(x)            -- forme parenthésée (équivalente)
    f(x, y)         -- forme multi-arguments

Les trois notations sont équivalentes. Choisissez celle qui est la
plus lisible dans votre contexte.

## Lambda

    \x -> x + 1
    λx.x + 1
    lambda x -> x + 1

Les trois formes sont acceptées. Le `\` est l'ASCII-friendly.

## Bitstrings

Un **bitstring** décrit une séquence de bits comme une suite de
segments `nom:taille`. Deux usages : destructuration (extraire des
champs d'un entier) et construction (assembler des champs en entier).

**Destructuration** — un pattern en position de paramètre :

    version <<ver:4, _:28>> = ver
    ipv4 <<ver:4, ihl:4, _tos:8, _len:16>> = (bor (shl ver 4) ihl)

`ver:4` extrait les 4 bits de poids fort de l'entier, `_:28` ignore
les 28 bits restants. Le désucrage se fait en `band`/`shr`/`shl`/`bor`.

**Construction** — une expression qui assemble des champs :

    <<4:4, 5:4>>          -- 0x45 = 69
    mkv v = <<v:4, 0:28>> -- réinjecte v dans les 4 bits de poids fort

**Contraintes v0** :
- Alignement octet uniquement, taille totale ≤ 64 bits.
- Pas d'endianness (`/little`, `/big`) — prévu v0.3.
- Pas de `rest:bits` (dernier segment de longueur variable) — prévu v0.3.

Référence : RFC-0002 (`RFC-0002.md`), chapitre 14-15 du book pour les
cas d'usage (parsing de protocoles).

## let

    let x = 5 in x + 1

Liaison locale. Le nom est visible dans la partie après `in`.

## if

    if cond then a else b          -- forme infixe
    (if cond a b)                  -- forme prefixe

Les deux formes sont acceptees et equivalentes. La forme infixe
`if cond then a else b` est la plus lisible pour les expressions
courantes ; la forme prefixe reste utile pour les cas imbriques.

## data

    data Nom = C1 | C2 | C3
    data Nom a = C1 | C2 a | C3 a a
    data Nom a b = C1 a | C2 b

Déclare un type avec ses constructeurs. Le paramètre `a`, `b`, etc.
représente le type contenu.

Un paramètre peut être **typé** (types dépendants) :

    data Vec (n : Nat) = Nil | Cons a (Vec n)
    data Fin (n : Nat) = Fz | Fs (Fin n)

Un paramètre peut aussi être **implicite** (non typé) :

    data Maybe a = Nothing | Just a

Les deux formes se combinent :

    data Pair a b = Pair a b
    data Wrap (n : Nat) a = Wrap a (Vec n)

### Signatures

    sig head : (n : Nat) -> Vec (succ n) -> a
    sig map  : (a -> b) -> List a -> List b

`sig` déclare le **type** d'une fonction sans son corps. Utilisé pour
la vérification structurelle des clauses (arité, kind, base/step).

## Définitions de fonction

Deux syntaxes équivalentes :

    inc x = x + 1                  -- syntaxe équationnelle
    fn inc(x) = x + 1              -- syntaxe "fn"

La syntaxe équationnelle gère plusieurs clauses :

    add zero n = n
    add (succ n) m = succ (add n m)

## Gardes

    sign x | x > 0 = "positif"

`otherwise` est un alias vers `true` (clause par defaut). `==` est
legal en garde. Les gardes s'evaluent apres le match, captures
visibles ; refus = clause suivante (ordre lineaire).

Forme alignee -- une ligne commencant par `|` continue la clause
precedente (memes nom/patterns, nouvelle garde) :

    classifie x | x < 0 = "negatif"
                | x == 0 = "nul"
                | otherwise = "positif"
    sign 0 = "nul"
    sign x = "négatif"

Une clause peut avoir plusieurs gardes :

    classifie x | x < 0 = "négatif"
                | x == 0 = "nul"
                | x > 0 = "positif"

## Compréhensions

    (for (x <- xs) E)              -- map
    (for (x <- xs) (when P) E)      -- filter puis map

Désucrage : `(map (λx. E) xs)` et
`(map (λx. E) (filter (λx. (P x)) xs))`. Grammaire : `ForExpr`
(GRAMMAR.md). La forme carrée `[E | x <- xs, P]` est en phase B.

## Assertions et tests

    assert_eq expr == expr
    assert_err expr

    test "name": lhs == rhs
    test "name": assert_err expr

`assert_eq` et `assert_err` sont évalués au moment où ils sont lus.
`test` est un bloc nommé.

## Théorèmes

    theorem name : énoncé
    prove name by tactique            -- tactique unique
    prove name by { t1; t2; t3 }      -- bloc composable

    axiom name : énoncé

Tactiques disponibles : `simplify`, `reflexivity`, `assumption`,
`auto`, `exact h`, `induction x`, `cases x`, `rewrite H`, `apply H`,
`seq`, `try`, `repeat`.

Bloc interactif (REPL) :

    prove t by {
      simplify;
      reflexivity
    }

### Modules

    module M                            -- ouvre un namespace
    import "path.hvn" [as Name]         -- charge un fichier
    import Name                         -- cherche core/std/ puis core/
    export foo                          -- marque un nom exporté
    strict on | off                     -- mode strict (opt-in)

### Mots réservés

Ces identifiants sont interceptés par le dispatch du REPL avant
l'évaluation normale. Ils ne peuvent pas être utilisés comme noms
de fonction ou de variable :

| Catégorie | Mots-clés |
|---|---|
| Définitions | `data`, `sig`, `let`, `fn`, `type`, `theorem`, `prove` |
| Modules | `module`, `import`, `export`, `strict` |
| Effets | `perform`, `handle`, `bracket`, `local`, `catch` |
| Preuves (tactiques) | `simplify`, `derive`, `integrate`, `solve`, `expand`, `plot` |
| Logique (kanren) | `fact`, `query`, `rules`, `meta`, `?-` |
| Acteurs | `spawn`, `tell`, `send`, `state`, `recv`, `let actor`, `let macro` |
| Outils | `help`, `stats`, `theorems`, `green`, `latex`, `skill`, `ai` |
| Tests | `test`, `assert_eq`, `assert_err` |
| Divers | `diff lower` |

**Cas notable** : `fact` est réservé par le pipeline kanren.
Pour une factorielle, utilisez `fac` (voir chapitre 4).

### Logique (miniKanren)

    fact name arg1 arg2 ...             -- assert un fait
    query name arg1 arg2 ...            -- solutions
    rules                                -- KB (règles) comme valeur

### Logique (Prolog)

    :p-fact pred(arg1, arg2)             -- ajoute un fait
    :p-rule head(args) :- b1, b2         -- ajoute une regle Horn
    ?- goal                              -- requete Prolog

### Agent IA

    ai "prompt"                          -- envoie un prompt

## Effets

    perform "Label" valeur
    handle expr handler

`perform` émet un signal. `handle` l'intercepte.

## Acteurs

    fn name(state, msg) = nouvel_état
    let Nom = état_initial with handler
    send(Nom, message)
    state(Nom)

## Commandes du REPL

    :q              -- quitter
    :h              -- aide
    :stats          -- statistiques du moteur
    :theorems       -- théorèmes et axiomes
    :hole [id]      -- trous
    :refine <id> <expr>   -- raffiner un trou
    :io on|off|status     -- handler IO
    :rules          -- KB (règles de réécriture)
    :skill <name>   -- applique une skill

    type expr       -- inférer le type
    simplify expr   -- simplifier
    derive expr     -- dériver
    integrate expr  -- intégrer
    latex expr      -- rendu LaTeX

CAS, forme parenthésée canonique (utilisable dans une expression) :

    (simplify e)
    (derive e)
    (integrate e)
    (solve e)
    (expand e)
    (plot e)
    (latex e)
