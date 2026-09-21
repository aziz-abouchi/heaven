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
    λx -> x + 1
    lambda x -> x + 1

Les trois formes sont acceptées. Le `\` est l'ASCII-friendly.

## let

    let x = 5 in x + 1

Liaison locale. Le nom est visible dans la partie après `in`.

## if

    if cond then a else b          -- forme native (à venir)
    (if cond a b)                  -- forme préfixe (actuelle)
    if (cond) (a) (b)              -- variante

La forme préfixe est la seule garantie aujourd'hui.

## data

    data Nom = C1 | C2 | C3
    data Nom a = C1 | C2 a | C3 a a
    data Nom a b = C1 a | C2 b

Déclare un type avec ses constructeurs. Le paramètre `a`, `b`, etc.
représente le type contenu.

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
    prove name by tactique

    axiom name : énoncé

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
    type expr       -- inférer le type
    simplify expr   -- simplifier
    derive expr     -- dériver
    integrate expr  -- intégrer
    latex expr      -- rendu LaTeX
