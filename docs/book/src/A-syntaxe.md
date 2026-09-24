# Annexe A — Syntaxe complète

Référence rapide de la syntaxe Heaven. Utile quand on cherche un
détail précis.

## Commentaires

    -- commentaire sur une ligne
    # commentaire à l'ancienne (accepté)
    ;; aussi accepté
    // aussi accepté

## Nombres

    42              -- entier
    3.14            -- flottant
    -7              -- négatif (unaire)

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

## let

    let x = 5 in x + 1

Liaison locale. Le nom est visible dans la partie après `in`.

## if

    if cond then a else b          -- forme native (roadmap)
    (if cond a b)                  -- forme préfixe (actuelle)

La forme préfixe est la seule garantie aujourd'hui.

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
    sign 0 = "nul"
    sign x = "négatif"

Une clause peut avoir plusieurs gardes :

    classifie x | x < 0 = "négatif"
                | x == 0 = "nul"
                | x > 0 = "positif"

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

### Logique (miniKanren)

    fact name arg1 arg2 ...             -- assert un fait
    query name arg1 arg2 ...            -- solutions
    rules                                -- KB (règles) comme valeur

### Logique (Prolog)

    ?- goal                              -- requête Prolog

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
