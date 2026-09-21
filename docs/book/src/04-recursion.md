# Chapitre 4 — Hello, Recursion!

> *« Pour comprendre la récursion, il faut d'abord comprendre la
> récursion. »*
>
> — Anonyme, mais probablement un étudiant en informatique.

La récursion est partout en programmation fonctionnelle. Pas parce
qu'elle est élégante (elle l'est), pas parce qu'elle est rapide (pas
toujours), mais parce qu'elle *correspond à la structure des données*.
Une liste est soit vide, soit un élément suivi d'une liste. Une
fonction qui traite une liste doit traiter ces deux cas. C'est tout.

## Le cas de base et le cas récursif

Toute fonction récursive a deux parties :

1. **Un cas de base** : quand s'arrêter.
2. **Un cas récursif** : comment progresser.

Prenons la factorielle, le classique. En mathématiques :

    n! = 1                si n = 0
    n! = n * (n-1)!       sinon

En Heaven, avec les entiers natifs :

    heaven> fact 0 = 1
    ✓ clause enregistrée pour 'fact'
    heaven> fact n = n * fact (n - 1)
    ✓ clause enregistrée pour 'fact'
    heaven> fact 5
    120

Heaven essaie la première clause. Si `n` vaut 0, elle s'applique et
rend 1. Sinon, il essaie la seconde, qui rappelle `fact` avec `n - 1`.

Vous remarquez ? La deuxième clause s'appelle elle-même. C'est la
récursion. La première clause est le **cas de base**.

## Ce qui se passe à l'exécution

Déroulons `fact 3` à la main :

    fact 3
    = 3 * fact 2
    = 3 * (2 * fact 1)
    = 3 * (2 * (1 * fact 0))
    = 3 * (2 * (1 * 1))
    = 3 * (2 * 1)
    = 3 * 2
    = 6

Heaven empile les appels jusqu'à atteindre le cas de base, puis
dépile en multipliant. C'est exactement ce que fait votre processeur,
sauf que Heaven le fait avec des **équations**, pas avec des
instructions.

## Récursion sur les listes

La factorielle est un exemple un peu scolaire. Voici du vrai code :

    heaven> sum Empty = 0
    heaven> sum (Cons x reste) = x + sum reste
    heaven> sum (Cons 1 (Cons 2 (Cons 3 Empty)))
    6

Deux clauses. La première dit : « si la liste est vide, la somme est
zéro ». La seconde : « si la liste commence par `x` et continue par
`reste`, la somme est `x + somme reste` ».

Regardez la structure. Le cas de base correspond à `Empty`. Le cas
récursif correspond à `Cons x reste`. Ce n'est pas un hasard : la
fonction a la **même forme** que le type.

C'est le principe fondamental. Quand vous écrivez une fonction sur un
type de données, vous écrivez une clause par constructeur. Le cas
récursif appelle la fonction sur les sous-parties. C'est presque
mécanique.

## Quelques fonctions classiques

La longueur :

    heaven> length Empty = 0
    heaven> length (Cons x reste) = 1 + length reste

L'inverse :

    heaven> reverse xs = reverseAux xs Empty
    heaven> reverseAux Empty acc = acc
    heaven> reverseAux (Cons x reste) acc = reverseAux reste (Cons x acc)

Cette version utilise un **accumulateur** : un argument supplémentaire
qui porte le résultat partiel. On verra pourquoi à la fin de ce
chapitre.

La concaténation :

    heaven> concat Empty ys = ys
    heaven> concat (Cons x xs) ys = Cons x (concat xs ys)

Trois fonctions, trois fois la même structure. Vous commencez à voir
le motif ?

## Le piège de la pile

Récursion, c'est bien. Mais chaque appel consomme de la mémoire. Pour
`fact 10000`, Heaven empile 10000 appels avant de commencer à
dépiler. La pile explose.

C'est là que la **récursion terminale** entre en jeu. Une fonction est
terminale si son appel récursif est la *dernière* chose qu'elle fait.
Regardez :

    heaven> fact n = n * fact (n - 1)

Ici, l'appel à `fact` n'est pas terminal : il y a une multiplication
qui attend. Heaven doit empiler. Comparez avec :

    heaven> factAux 0 acc = acc
    heaven> factAux n acc = factAux (n - 1) (n * acc)
    heaven> fact n = factAux n 1

Cette fois, l'appel récursif est la dernière chose. Rien n'attend
après. Heaven peut **réutiliser** le même cadre de pile au lieu d'en
empiler un nouveau. C'est ce qu'on appelle l'**optimisation d'appel
terminal**.

Heaven ne l'implémente pas encore (c'est dans le backlog), mais il
faut écrire vos fonctions comme si c'était le cas. C'est une
discipline, pas une contrainte.

## La récursion mutuelle

Parfois deux fonctions s'appellent l'une l'autre. Par exemple, une
fonction qui vérifie si un nombre est pair, et une autre s'il est
impair :

    heaven> isEven 0 = true
    heaven> isEven n = isOdd (n - 1)
    heaven> isOdd 0 = false
    heaven> isOdd n = isEven (n - 1)

    heaven> isEven 4
    true
    heaven> isOdd 4
    false

C'est la **récursion mutuelle**. Heaven n'a aucun problème avec ça :
les deux fonctions sont dans le même espace de noms, chacune peut
appeler l'autre.

## La récursion sur les arbres

Les listes sont linéaires. Les arbres ont deux branches. Prenons :

    heaven> data Tree a = Leaf | Node (Tree a) a (Tree a)

Un arbre est soit une feuille, soit un nœud avec un sous-arbre gauche,
une valeur, et un sous-arbre droit.

Compter les nœuds :

    heaven> size Leaf = 0
    heaven> size (Node g x d) = 1 + size g + size d

La fonction a deux clauses, comme le type a deux constructeurs. Le
cas récursif appelle la fonction sur les deux sous-arbres. C'est
encore le même principe.

## Récursion et preuves

Les fonctions récursives ont une propriété : elles **terminent**.
C'est important en Heaven parce que le noyau de preuve doit pouvoir
vérifier ça. Une fonction qui ne termine pas n'est pas une fonction
mathématique, c'est un calcul qui tourne.

Heaven ne vous demande pas de prouver la terminaison à chaque fois,
mais il utilise le même schéma que vous : les types de données
récursifs sont **bien fondés** (on ne peut pas les construire à
l'infini), et les fonctions récursives sur ces types terminent
naturellement.

C'est pour ça que le pattern matching est si important. Une fonction
qui matche chaque constructeur et rappelle sur les sous-parties
*termine toujours*. Une fonction qui se rappelle avec un argument plus
grand peut ne jamais terminer. Heaven ne fera pas la différence à la
compilation, mais la discipline compte.

## Le piège du pattern matching partiel

Souvenez-vous du chapitre 3 : une fonction peut ne pas avoir de clause
pour tous les cas. Exemple :

    heaven> head (Cons x reste) = x
    heaven> head (Cons 5 Empty)
    5
    heaven> head Empty
    eval error: error.ArityMismatch

Heaven refuse. Ce n'est pas un bug, c'est une **fonction partielle**.
Vous avez oublié de traiter `Empty`.

En pratique, on évite les fonctions partielles en utilisant `Maybe` :

    heaven> head Empty = Nothing
    heaven> head (Cons x reste) = Just x

Cette fois, `head Empty` rend `Nothing`, ce qui est explicite. Le
programme ne plante pas, il dit « pas de résultat ».

On verra les types dépendants plus tard, qui permettent d'exprimer
« cette fonction ne peut être appelée que sur une liste non vide ».
Pour l'instant, `Maybe` est votre ami.

## Récapitulatif

- Une fonction récursive a un **cas de base** et un **cas récursif**.
- La structure de la fonction correspond à la structure du type.
- La **récursion terminale** économise la pile.
- La **récursion mutuelle** est permise.
- Les arbres se traitent comme les listes, avec deux appels.
- Une fonction **partielle** échoue sur les cas non traités. Utilisez
  `Maybe` pour être explicite.

Au chapitre suivant, on parle de **fonctions d'ordre supérieur** :
`map`, `filter`, et la composition `>>>`. C'est là que le code
fonctionnel devient vraiment concis.
