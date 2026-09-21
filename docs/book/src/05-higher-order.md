# Chapitre 5 — Higher-Order Functions

> *« Une fonction qui prend une fonction est une fonction qui comprend
> ce que vous voulez vraiment dire. »*

Jusqu'ici, on a passé des nombres et des listes à nos fonctions. Mais
en fonctionnel, on peut aussi passer des **fonctions** elles-mêmes.
C'est ce qu'on appelle les fonctions d'ordre supérieur, et c'est là
que le style devient vraiment concis.

## Une fonction, c'est une valeur

Rappelez-vous le chapitre 2 :

    heaven> inc x = x + 1
    ✓ clause enregistrée pour 'inc'
    heaven> type inc
    Int -> Int

`inc` est une fonction. Mais c'est aussi une **valeur**. On peut la
passer à une autre fonction :

    heaven> apply f x = f x
    heaven> apply inc 5
    6

`applique` prend deux arguments : une fonction `f` et une valeur `x`,
et rend `f x`. On dit que `applique` est d'**ordre supérieur** parce
qu'elle prend une fonction en argument.

C'est aussi simple que ça. Une fonction qui prend une fonction est
une fonction d'ordre supérieur. Voilà toute la définition.

## map : transformer chaque élément

Prenons une liste :

    heaven> data Stream a = Cons a (Stream a) | End
    heaven> maListe = Cons 1 (Cons 2 (Cons 3 End))

On veut doubler chaque élément. On pourrait écrire :

    heaven> doubleAll End = End
    heaven> doubleAll (Cons x reste) = Cons (x * 2) (doubleAll reste)

Ça marche. Mais si on veut tripler, il faut tout réécrire. Et si on
veut ajouter 10 ? C'est pénible.

`map` résout ça. Elle prend une fonction et l'applique à chaque
élément :

    heaven> map f End = End
    heaven> map f (Cons x reste) = Cons (f x) (map f reste)

    heaven> map inc (Cons 1 (Cons 2 End))
    (Cons 2 (Cons 3 End))
    heaven> map dbl (Cons 1 (Cons 2 End))
    (Cons 2 (Cons 4 End))

`map` est *générique* : elle ne sait pas ce que fait `f`, et elle n'a
pas besoin de le savoir. Elle traverse la liste, applique `f`, et
reconstruit. C'est ça, l'abstraction.

## filter : garder ce qui compte

`filter` prend un **prédicat** (une fonction qui rend `true` ou
`false`) et ne garde que les éléments qui passent :

    heaven> filter p End = End
    heaven> filter p (Cons x reste) = if (p x) (Cons x (filter p reste)) (filter p reste)

    heaven> isBig x = x > 1
    heaven> filter isBig (Cons 1 (Cons 2 (Cons 3 End)))
    (Cons 2 (Cons 3 End))

Encore une fois, `filter` ne sait pas ce que `isBig` teste. Elle
appelle, regarde le résultat, décide.

## fold : résumer une liste en une valeur

`map` transforme, `filter` sélectionne. `fold` **résume**. Elle prend
une fonction binaire, une valeur initiale, et une liste :

    heaven> fold f acc End = acc
    heaven> fold f acc (Cons x reste) = fold f (f acc x) reste

Avec elle, on peut écrire `somme` en une ligne :

    heaven> sum xs = fold add 0 xs
    heaven> sum (Cons 1 (Cons 2 (Cons 3 End)))
    6

Ou `longueur` :

    heaven> length xs = fold (acc x = acc + 1) 0 xs

(On reviendra sur cette syntaxe de lambda raccourcie — pour l'instant,
retenez que `fold` est l'outil universel pour réduire une liste.)

## Composition avec >>>

Vous avez déjà rencontré `>>>` au chapitre 1. C'est l'opérateur de
**composition** : `f >>> g` crée une nouvelle fonction qui applique
`f` puis `g`.

    heaven> inc x = x + 1
    heaven> dbl x = x * 2
    heaven> incPuisDbl = inc >>> dbl
    heaven> incPuisDbl 3
    8

Déroulons : `inc 3 = 4`, puis `dbl 4 = 8`. La composition rend une
**fonction**, pas un résultat. C'est pour ça qu'on peut la passer à
`map` :

    heaven> map (inc >>> dbl) (Cons 1 (Cons 2 End))
    (Cons 4 (Cons 6 End))

Chaque élément est incrémenté puis doublé. `1` devient `4`, `2` devient
`6`. En une ligne.

## Pourquoi c'est puissant

Regardez la différence entre ces deux programmes :

Sans ordre supérieur :

    doublerPuisFiltrer End = End
    doublerPuisFiltrer (Cons x reste) =
      if (x * 2 > 2) (Cons (x * 2) (doublerPuisFiltrer reste)) (doublerPuisFiltrer reste)

Avec :

    doublerPuisFiltrer xs = filter isBig (map dbl xs)

Le second est plus court, plus lisible, et surtout : chaque morceau
est réutilisable. `map dbl` marche sur n'importe quelle liste. `filter
isBig` aussi. On les assemble, on obtient une nouvelle fonction.

C'est ça, la programmation fonctionnelle. Vous ne dites pas *comment*
parcourir la liste, vous dites *ce que* vous voulez faire. Le
parcours, c'est l'affaire de `map`, `filter`, `fold`.

## Les pipelines

Dans le monde réel, on assemble beaucoup de transformations :

    heaven> pipeline = filter isBig >>> map inc >>> map dbl
    heaven> pipeline (Cons 1 (Cons 2 (Cons 3 End)))
    (Cons 6 (Cons 8 End))

`traitement` est une fonction comme une autre. Elle filtre, puis
incrémente, puis double. Chaque étape est indépendante. On peut
réordonner, tester, remplacer.

C'est exactement le style d'astra-core, un DSL de pipelines qu'on
verra en détail au chapitre 7.

## La curryfication

Un dernier concept, un peu subtil. Regardez :

    heaven> ajoute x y = x + y
    heaven> ajoute 3 4
    7

Mais aussi :

    heaven> ajoute3 = ajoute 3
    heaven> ajoute3 4
    7

Comment ça marche ? Heaven voit que `ajoute` prend **deux** arguments,
mais on ne lui en donne qu'**un**. Il rend une fonction qui attend le
second. C'est ce qu'on appelle la **curryfication**.

Pratiquement : `ajoute 3` est une fonction `Int -> Int`. On peut la
passer à `map` :

    heaven> map (ajoute 3) (Cons 1 (Cons 2 End))
    (Cons 4 (Cons 5 End))

C'est la même chose que `ajoute 3` appliqué à chaque élément. Pas
besoin d'une lambda.

## Récapitulatif

- Une fonction qui prend une fonction est d'**ordre supérieur**.
- `map` transforme, `filter` sélectionne, `fold` résume.
- `>>>` compose deux fonctions.
- Les pipelines assemblent plusieurs étapes.
- La **curryfication** permet de passer des fonctions partiellement
  appliquées.

Au chapitre suivant, on parle d'**effets algébriques** : comment
écrire du code qui fait des choses (lire, écrire, logger) sans
polluer le reste du programme.
