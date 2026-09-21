# Annexe B — Erreurs courantes

Un catalogue des erreurs qu'on rencontre le plus souvent, avec leurs
causes et leurs solutions.

## `error.ArityMismatch`

**Message** :

    eval error: error.ArityMismatch

**Cause** : une fonction attend un certain nombre d'arguments, on lui
en donne un autre.

**Exemple** :

    heaven> add 1
    eval error: error.ArityMismatch

`add` attend 2 arguments. On n'en donne qu'un. Heaven ne curryfie pas
encore automatiquement dans tous les cas.

**Solution** : donner tous les arguments. Si vous voulez
l'application partielle, définissez la fonction en curryfié
explicitement :

    add x = \y -> x + y
    add 3         -- rend une fonction
    add 3 4       -- rend 7

## `error.UnknownSymbol`

**Message** :

    eval error: error.UnknownSymbol

**Cause** : un symbole n'est pas défini dans l'environnement, ou n'est
pas reconnu comme fonction.

**Exemple** :

    heaven> inconnu 42
    eval error: error.UnknownSymbol

`inconnu` n'existe pas.

**Solution** : définir le symbole avant de l'utiliser.

    heaven> inconnu x = x + 1
    ✓ clause enregistrée
    heaven> inconnu 42
    43

## `error.TypeError`

**Message** :

    eval error: error.TypeError

**Cause** : une opération attend un type, en reçoit un autre.

**Exemple** :

    heaven> 1 + true
    eval error: error.TypeError

`+` attend deux entiers, `true` n'en est pas un.

**Solution** : vérifier le type des arguments avec `type`.

## `error.InvalidExpr`

**Message** :

    eval error: error.InvalidExpr

**Cause** : une expression contient un trou (`_` ou `?`) non résolu.

Un trou n'est pas une erreur en soi : c'est une **question posée au
système**. L'erreur vient quand on essaie d'**exécuter** une expression
qui contient encore un trou.

**Exemple** :

    heaven> f x = _ + 1
    ✓ clause enregistrée
    heaven> f 3
    eval error: error.InvalidExpr

**Solution** : raffiner le trou avant d'exécuter (voir chapitre 8 sur
le type-driven development).

## `error.InvalidSyntax`

**Message** :

    error: error.InvalidSyntax

**Cause** : la syntaxe n'est pas reconnue par le parseur. Souvent une
parenthèse manquante.

**Exemple** :

    heaven> (2 + 3
    error: error.InvalidSyntax

**Solution** : vérifier les parenthèses. Le REPL indique souvent le
premier token qu'il a reconnu, ce qui aide à localiser.

## Poison `0xAAAAAAAA`

**Message** :

    [GET BUG] id=2863311530 >= len=432 — STACK TRACE MANQUANT
    panic: invalid Id access

**Cause** : bug interne. Un `Id` non initialisé circule dans l'AST.
Souvent dû à une slice sur `pool.items` qui devient dangling après une
réallocation.

**Solution** : c'est un bug de Heaven, pas de votre code. Signalez-le
sur GitHub avec le fichier `.hvn` qui le reproduit.

## `UnknownSymbol` sur un constructeur

**Message** :

    heaven> Cons 1 End
    eval error: error.UnknownSymbol

**Cause** : le constructeur `Cons` n'est pas encore enregistré.

**Solution** : déclarer le type avant de l'utiliser.

    heaven> data Stream a = Cons a (Stream a) | End
    ✓ data type registered (2 constructors)
    heaven> Cons 1 End
    (Cons 1 End)

## `LinearViolation`

**Message** :

    eval error: error.LinearViolation

**Cause** : une variable déclarée `linear` n'est pas utilisée
exactement une fois.

**Exemple** :

    heaven> let linear x = 5 in x + x
    eval error: error.LinearViolation

**Solution** : utiliser la variable exactement une fois, ou changer
la multiplicité.

    heaven> let linear x = 5 in x + 1
    6
    heaven> let many x = 5 in x + x
    10

## Division par zéro

**Message** :

    eval error: error.DivisionByzero

**Cause** : division par zéro.

**Exemple** :

    heaven> 5 / 0
    eval error: error.DivisionByzero

**Solution** : vérifier le diviseur avant.

## Erreurs du noyau

**Message** :

    error.NotAType
    error.DomainMismatch
    error.TypeError

**Cause** : le noyau a refusé une preuve.

**Exemple** :

    theorem fausse : 1 = 2
    prove fausse by simplify
    error: not provable

**Solution** : la preuve est fausse. Vérifiez chaque étape manuellement.

## `Memory leak detected`

**Message** :

    error(gpa): memory address 0x... leaked
    ⚠️ MEMORY LEAK DETECTED!

**Cause** : une allocation n'a pas été libérée. Souvent dans le code
de Heaven lui-même, pas dans votre code.

**Solution** : signalez-le. La stack trace indique où la fuite a eu
lieu.
