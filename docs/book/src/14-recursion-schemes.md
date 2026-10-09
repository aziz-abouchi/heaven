# Chapitre 14 — Schémas de récursion

> *« La récursion est partout. Autant lui donner un nom. »*

Jusqu'ici, chaque fois qu'on a voulu parcourir une liste, on a écrit
une fonction récursive ad hoc : une clause pour `nil`, une clause
pour `cons`, et une reconstruction à la main. C'est correct, mais
c'est répétitif. Et quand on a cinq structures de données, on écrit
cinq fois le même squelette.

Les **schémas de récursion** formalisent ce squelette. L'idée :
séparer *ce qu'on fait à chaque étape* de *la manière dont on
parcourt la structure*. Le parcours devient une fonction générique,
réutilisable, qu'on paramètre par la logique métier.

Heaven n'a pas de `Fix` ni de types récursifs génériques en v0.
Mais sur les listes — qui sont la structure la plus courante — on
peut déjà construire quatre schémas fondamentaux. Ce chapitre les
présente. Le module vit dans `core/std/recursion.hvn`.

## cata : consommer une structure

`cata` (pour *catamorphisme*) est l'ancêtre de `foldr`. On l'écrit :

    cata _ z nil = z
    cata f z (cons x xs) = f x (cata f z xs)

Lisez-le à voix haute :

- Sur `nil`, on retourne `z` — la **graine** (zéro, liste vide,
  unité selon le contexte).
- Sur `cons x xs`, on calcule d'abord `cata f z xs` (le résultat
  sur la queue), puis on combine avec `x` via `f`.

La somme d'une liste :

    sum_f x acc = (+ x acc)
    sum xs = (cata sum_f 0 xs)

La longueur :

    length_f _ acc = (+ acc 1)
    length xs = (cata length_f 0 xs)

Le produit :

    product_f x acc = (* x acc)
    product xs = (cata product_f 1 xs)

Trois fonctions. Un seul squelette. C'est ça, l'intérêt.


## ana : générer une structure

`cata` consomme. Son dual, `ana` (pour *anamorphisme*), **génère**.
On lui donne une graine et une fonction d'étape qui, à chaque tour,
décide soit de s'arrêter, soit de produire un élément et une
nouvelle graine.

En Heaven, la décision se prend avec `Option` :

    ana f seed = ana_step f (f seed)

    ana_step _ none = nil
    ana_step f (some (pair x next)) = cons x (ana f next)

`f` a donc le type informel `seed -> Option (élément, seed')`. On
itère tant que `f` renvoie `some`, on s'arrête au premier `none`.

Exemple : générer les entiers de 0 à 2.

    gen n = (if (< n 3) (some (pair n (+ n 1))) none)
    maListe = (ana gen 0)    -- [0, 1, 2]

C'est l'inverse exact de `cata`. Là où `cata` plie une liste en une
valeur, `ana` déplie une valeur en une liste.

## hylo : les deux ensemble

Souvent, on génère une structure pour la consommer immédiatement.
Écrire `(cata f z (ana g s))` fonctionne, mais matérialise la liste
intermédiaire. Le schéma `hylo` (pour *hylomorphisme*) encapsule ce
motif :

    hylo g z f seed = cata g z (ana f seed)

Le premier argument de `hylo` est la fonction de combinaison de
`cata`, le dernier est la fonction d'étape de `ana`. Le résultat
est directement la valeur finale.

Exemple : la somme des entiers de 0 à 4.

    gen n = (if (< n 5) (some (pair n (+ n 1))) none)
    sum_f x acc = (+ x acc)
    resultat = (hylo sum_f 0 gen 0)   -- 0+1+2+3+4 = 10

**Note v0** : dans un langage avec fusion automatique (comme GHC),
`hylo` peut éviter de construire la liste intermédiaire. Heaven ne
fait pas encore cette optimisation — la liste est bel et bien créée.
Mais le schéma reste utile conceptuellement : il capture l'idée que
*produire puis consommer* est une seule opération.

## para : voir la sous-structure

Parfois, `cata` ne suffit pas. On a besoin non seulement du
* résultat * du parcours de la queue, mais aussi de la *queue
elle-même*. C'est le rôle de `para` (pour *paramorphisme*) :

    para _ z nil = z
    para f z (cons x xs) = f x xs (para f z xs)

La différence avec `cata` : `f` reçoit **trois** arguments au lieu
de deux — l'élément `x`, la queue `xs`, et le résultat récursif
`para f z xs`.

Pourquoi c'est utile ? Prenons `splitAt`, qui coupe une liste en
deux à une position donnée. Avec `cata`, on ne peut pas, car on
n'a pas accès à la queue. Avec `para` :

    split_f _ xs _ = xs   -- simplifié : on garde juste la queue

Un autre exemple : `dropWhile` (retirer le préfixe qui satisfait un
prédicat) a besoin de la queue *telle quelle* quand le prédicat
devient faux. `para` le permet, `cata` non.

## Limitations v0

Le module `core/std/recursion.hvn` est un **pilote**. Il couvre les
listes — la structure récursive la plus courante — mais s'arrête là.

- **Pas de `Fix`** : on ne peut pas définir un schéma générique qui
  marche pour *toutes* les structures récursives (arbres, `Maybe`,
  types utilisateur). Chaque structure aurait besoin de sa propre
  famille de fonctions.
- **Pas de fusion automatique** : `hylo` compose `ana` et `cata`,
  mais ne défait pas la liste intermédiaire. Un vrai hylomorphisme
  fusionné (deforestation) demanderait une passe du compilateur.
- **Lambdas inline non supportées** : les exemples utilisent des
  fonctions nommées (`sum_f`, `length_f`) parce que le parser
  infixe actuel ne gère pas encore les lambdas dans les arguments
  de fonctions. C'est une limitation de surface, pas de fond.

Malgré ces limites, les quatre schémas suffisent à éliminer
beaucoup de boilerplate. `sum`, `length`, `product`, `map`, `filter`,
`take`, `drop` — tous s'écrivent en une ligne au-dessus de `cata`
ou `para`.

## Pour aller plus loin

- `core/std/recursion.hvn` : le module complet (32 lignes).
- `tests/test_recursion.hvn` : 22 tests qui couvrent les quatre
  schémas.
- `core/std/list.hvn` : les versions spécialisées (`foldl`,
  `foldr`) — équivalentes à `cata` mais dans l'autre sens.
- Référence externe : la bibliothèque **`recursion-schemes`** de
  l'écosystème Haskell (Edward Kmett) généralise ces schémas à
  toutes les structures récursives via des foncteurs. Heaven s'en
  inspire, mais s'arrête pour l'instant aux listes.

---

Tu as maintenant quatre schémas qui éliminent le boilerplate
récursif sur les listes. Un autre genre de boilerplate attend :
l'accès aux structures imbriquées. Pour lire `(fst (fst p))`, on
écrit une fonction de reconstruction à chaque fois — et ça devient
vite pénible. Le prochain chapitre présente une réponse
conceptuelle : les **optiques**, et en particulier les **lenses**.
