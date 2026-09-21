# Chapitre 3 — Syntax in Functions

> *« Une fonction qui ne prend qu'une seule forme de donnée est une
> fonction qui n'a rien vu du monde. »*

Au chapitre précédent, on a vu que Heaven infère les types. Maintenant
on va voir comment écrire des fonctions qui prennent *vraiment* de la
donnée structurée, et pas seulement des nombres.

## Retour sur le pattern matching

Vous avez déjà vu ceci :

    heaven> add zero n = n
    ✓ clause enregistrée pour 'add'
    heaven> add (succ n) m = succ (add n m)
    ✓ clause enregistrée pour 'add'

Deux équations. La première dit : « si le premier argument est `zero`,
rends le second ». La seconde dit : « si le premier argument est
`succ n`, rends `succ (add n m)` ». Heaven essaie dans l'ordre. C'est
le **filtrage par motif** (*pattern matching*).

On peut utiliser plusieurs motifs dans la même clause :

    heaven> pairUp x y = (x, y)

Mais le filtrage par motif devient vraiment intéressant quand on
définit ses propres types de données.

## Définir ses propres types

Le mot-clé est `data`. Prenons le plus simple : un type qui vaut soit
une chose, soit une autre.

    heaven> data Color = Red | Green | Blue
    ✓ data type registered (3 constructors)

`Color` est un type. `Red`, `Green`, `Blue` sont ses trois
**constructeurs**. On les utilise comme n'importe quelle valeur :

    heaven> Red
    Red
    heaven> type Red
    Color

Vous voyez ? `Red` n'est pas un mot réservé. C'est une valeur
ordinaire, du type `Color`.

## Le filtrage par motif sur nos types

Écrivons une fonction qui traduit une couleur en français :

    heaven> name Red = "rouge"
    heaven> name Green = "vert"
    heaven> name Blue = "bleu"

Trois clauses. Une par constructeur. Heaven essaie dans l'ordre. On
peut l'utiliser :

    heaven> name Green
    "vert"
    heaven> name Blue
    "bleu"

Que se passe-t-il si on oublie un cas ?

    heaven> name Inconnu
    eval error: error.UnknownSymbol

Heaven ne connaît pas `Inconnu`. Mais si on ajoute un quatrième
constructeur :

    heaven> data Color = Red | Green | Blue | Yellow

puis qu'on essaie `nom Jaune`, Heaven n'a pas de clause pour `Jaune`.
Il retourne... rien. La fonction est **partielle**. On y reviendra.

## Des types avec contenu

Les constructeurs simples, c'est bien. Mais la vraie puissance vient
des constructeurs qui prennent des arguments :

    heaven> data Maybe a = Nothing | Just a
    ✓ data type registered (2 constructors)

`Just` prend un argument. `Nothing` n'en prend aucun. On peut écrire :

    heaven> Just 42
    (Just 42)
    heaven> type Just 42
    Maybe Int
    heaven> Nothing
    Nothing

Le filtrage par motif peut extraire le contenu :

    heaven> fromMaybe Nothing default = default
    heaven> fromMaybe (Just x) default = x

Si on a un `Just`, on rend le contenu. Sinon, on rend la valeur par
défaut.

    heaven> fromMaybe (Just 42) 0
    42
    heaven> fromMaybe Nothing 0
    0

## Les gardes

Parfois un motif ne suffit pas. On veut tester une condition sur les
valeurs. On ajoute une **garde**, séparée par une barre verticale.

    heaven> sign x | x > 0 = "positif"
    heaven> sign 0 = "nul"
    heaven> sign x = "négatif"

La première clause a une garde : elle ne s'applique que si `x > 0`.
La deuxième clause n'a pas de garde. La troisième non plus. Heaven
les essaie dans l'ordre, avec les gardes.

    heaven> sign 5
    "positif"
    heaven> sign 0
    "nul"
    heaven> sign (-3)
    "négatif"

Attention à la syntaxe de `(-3)` : le `-` unaire doit être parenthésé.
Sinon Heaven croit que vous voulez faire une soustraction.

## Les constructeurs récursifs

Le vrai intérêt de `data`, c'est la récursion. Prenons une liste
chaînée minimale :

    heaven> data Liste a = Vide | Cellule a (Liste a)
    ✓ data type registered (2 constructors)

`Vide` est la liste vide. `Cellule x reste` est une cellule qui
contient `x` et pointe vers `reste`. On peut construire :

    heaven> Cellule 1 (Cellule 2 (Cellule 3 Vide))
    (Cellule 1 (Cellule 2 (Cellule 3 Vide)))

Et écrire une fonction qui calcule la longueur :

    heaven> length Vide = 0
    heaven> length (Cellule x reste) = 1 + length reste

    heaven> length (Cellule 1 (Cellule 2 (Cellule 3 Vide)))
    3

C'est ça, le cœur du fonctionnel. Un type qui se contient lui-même,
une fonction qui se rappelle elle-même.

## Une liste un peu plus riche

Le langage a déjà une notion de liste avec `Nil` et `Cons`. Mais
définissons-la nous-mêmes pour comprendre :

    heaven> data MyList a = Empty | Cons a (MyList a)

C'est la même structure que `Liste`, juste avec d'autres noms. Le nom
n'a pas d'importance, la *forme* en a.

    heaven> sum Empty = 0
    heaven> sum (Cons x reste) = x + sum reste

    heaven> sum (Cons 1 (Cons 2 (Cons 3 Empty)))
    6

## Le pattern matching imbriqué

On peut imbriquer les motifs. Par exemple, écrire `head` qui rend le
premier élément d'une liste, ou `Empty` si elle est vide :

    heaven> head (Cons x reste) = x
    heaven> head Empty = Empty

Mais ce n'est pas très utile : `head Fin` rend `Empty`, et `head` est
censée rendre un élément. Le problème, c'est qu'on ne peut pas
toujours garantir qu'une liste n'est pas vide. On verra comment
exprimer ça avec les types au chapitre 8 (types dépendants), mais pour
l'instant, acceptons l'imperfection.

## Les alias de type

Parfois un type est long à écrire. On peut lui donner un nom court :

    heaven> type Nom = String
    ✓ Nom défini

Mais ce n'est pas un nouveau type : c'est un synonyme. `Nom` et
`String` sont interchangeables. Utile pour la lisibilité, pas pour la
sûreté.

## Récapitulatif

- **`data`** définit un type avec ses constructeurs.
- Les constructeurs peuvent prendre des arguments.
- Le **filtrage par motif** dans les équations sélectionne la bonne
  clause.
- Les **gardes** ajoutent des conditions.
- On peut définir des types **récursifs** (`Liste`, `Stream`, etc.).
- Un type avec plusieurs cas **sans clause pour tous les cas** est dit
  *partiel*. Heaven ne le signale pas encore, mais c'est un point à
  garder en tête.

Au chapitre suivant, on plonge dans la **récursion** : comment écrire
des fonctions qui se rappellent elles-mêmes sans se perdre, et
pourquoi c'est le cœur du paradigme fonctionnel.
