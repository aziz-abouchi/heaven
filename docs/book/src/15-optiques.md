# Chapitre 15 — Optiques : lire et écrire en profondeur

> *« Un champ, c'est un nom qui sait lire et écrire. Une optique,
> c'est la même idée, mais composable. »*

Au chapitre 14, on a factorisé la **récursion**. Il reste un autre
genre de boilerplate dans nos programmes : l'accès aux structures
imbriquées. Pour lire le fond d'un `Pair (Pair a b) c`, on écrit
`(fst (fst p))`. Pour modifier cette valeur, il faut démonter,
changer, remonter :

    set_pp_fst v p =
      let inner = (fst p) in
      (pair (pair v (snd inner)) (snd p))

Sur un seul niveau, ça va. Sur cinq, ça devient illisible. Et chaque
nouvelle forme de structure demande une nouvelle paire de fonctions.

Les **optiques** formalisent cet accès. Ce chapitre les présente
et les implémente en Heaven.

## L'idée : séparer lire de écrire

Une **lens** est un couple : un *getter* et un *setter*.

    get : s -> a          -- extrait la valeur cible
    set : a -> s -> s     -- remplace la valeur, rend la source modifiée

Ces deux fonctions vivent ensemble. Un exemple pour `Pair` :

    lens_fst = (pair fst set_fst)

Une fois qu'on a une lens, on peut :

- **Lire** : `view l s` applique le getter.
- **Écrire** : `set_via l v s` applique le setter.
- **Modifier** : `over l f s` combine les deux.

Le point clé : le setter **préserve le reste**. On ne touche qu'un
champ, tout le contexte autour survit intact.

## Implémentation en Heaven

Le module `core/std/lens.hvn` fait 32 lignes. Le voici en entier :

    module Lens

    lens get set = (pair get set)

    view l s = (fst l) s
    set_via l v s = (snd l) v s
    over l f s = (snd l) (f (view l s)) s

    set_fst v p = (pair v (snd p))
    set_snd v p = (pair (fst p) v)

    lens_fst _ = (lens fst set_fst)
    lens_snd _ = (lens snd set_snd)

    get_pp_fst p = (fst (fst p))
    set_pp_fst v p =
      let inner = (fst p) in
      (pair (pair v (snd inner)) (snd p))

    lens_pp_fst _ = (lens get_pp_fst set_pp_fst)

La construction `lens` met les deux fonctions dans un `Pair`. On
peut ensuite lire, écrire, modifier sur `Pair` simple, et aussi
sur `Pair` imbriqué. `view (lens_pp_fst 0) p` va chercher `(fst
(fst p))` en une seule opération.

Le module est enregistré dans `std_loader.zig`, donc les lenses
sont disponibles partout sans `import` explicite.

## Le bug qu'on a corrigé pour y arriver

L'implémentation ci-dessus **ne marchait pas** avant. Ce code :

    g x = (+ x 1)
    mkl _ = (pair g 0)
    ((fst (mkl 0)) 5)

devait rendre `6`. Il rendait autre chose. Pourtant, cette variante
marchait :

    (let f (fst (mkl 0)) (f 5))

Le problème était un **bug du tree-walker**, pas de la sémantique.
Quand on écrit `(apply expr args)`, l'évaluateur résout `expr`,
puis reconstruit un noeud `apply` avec la valeur résolue et **les
arguments d'origine** — y compris le premier argument qui était en
fait `expr` lui-même. Résultat : le noeud reconstruit se croyait
encore en position d'opérateur, et passait **deux** arguments à la
fonction extraite au lieu d'un.

Le fix tient en quelques lignes (commit `2810cc7`) : reconstruire
le noeud avec **seulement** les arguments, sans l'opérateur
d'origine. Ça a suffi à débloquer les fonctions stockées dans des
structures.

C'est un motif récurrent en informatique : les **fonctions comme
valeurs** (first-class functions) sont si fondamentales qu'on les
tient pour acquises. Quand elles manquent, on découvre le trou
non pas en écrivant du code qui les utilise, mais en écrivant du
code qui utilise *autre chose* — ici, une lens — qui **a besoin**
de les utiliser en interne.

## Limitations v0

Le module `core/std/lens.hvn` couvre le strict minimum. Il reste
des choses qu'on ne peut pas faire :

- **Composition générique** : en Haskell, deux lenses se
  composent en une seule avec l'opérateur `.` : `l1 . l2` cible
  le champ de `l2` dans `l1`. En Heaven v0, il faut écrire chaque
  composition à la main (`lens_pp_fst` ci-dessus). Pour aller plus
  loin, il faudrait que les setters soient eux-mêmes
  paramétrés par d'autres setters — ce qui demande des types plus
  riches que ce que le système supporte.

- **Prisms et traversals** : une lens cible exactement un élément.
  Un **prism** cible zéro ou un (utile pour `Maybe`, `Either`,
  les sum types). Un **traversal** cible zéro ou plusieurs
  (utile pour les listes, les arbres). Ces optiques existent en
  Haskell (`lens` de Kmett) mais pas dans Heaven v0.

- **Pas de records** : sans champs nommés, toutes les lenses sont
  des `fst`/`snd` ou des positions. Si Heaven ajoute un jour des
  records, `lens_fst` deviendra `lens_name` et tout le reste
  tiendra.

Ces limitations sont de surface, pas de fond. Le motif est là.
L'extension viendra quand les consommateurs apparaîtront.

## Pourquoi c'est utile malgré tout

Même sans composition générique, la lens apporte deux choses :

1. **Un nom.** `view lens_snd p` dit ce qu'on fait. `(snd p)` dit
   la même chose mais sans intention. Sur du code long, la
   différence compte.

2. **Un point d'extension.** Si demain on ajoute la composition ou
   les records, tout le code qui utilise `view`/`set_via`/`over`
   continuera de marcher. On n'aura changé que la **construction**
   des lenses.

C'est le principe des abstractions : l'interface tient, la
représentation peut bouger.

## Pour aller plus loin

- `core/std/lens.hvn` : le module (32 lignes).
- `tests/test_lens.hvn` : 12 tests qui couvrent view/set/over, sur
  `Pair` simple et `Pair` imbriqué, plus un test first-class
  explicite.
- Référence externe : la bibliothèque **`lens`** de l'écosystème
  Haskell (Edward Kmett) implémente la composition générique, les
  prisms, les traversals, et bien plus — le tout fondé sur une
  théorie catégorique de l'accès (`van Laarhoven lenses`,
  `profunctor optics`). Heaven s'en inspire, mais s'arrête à la
  version minimale.

---

Tu sais maintenant lire et écrire dans des structures imbriquées
proprement, et tu as vu comment une limitation du runtime peut
bloquer une abstraction entière — jusqu'à ce qu'un bug de dix
lignes la débloque. C'est ça, un langage en construction : les
concepts avancés ne sont pas toujours possibles tout de suite.

Il reste une autre abstraction de la même famille à explorer. Là
où les optiques accèdent à des **données**, les free monads
manipulent des **programmes**. Séparer le programme de son
interprétation est un motif qui revient partout. C'est le sujet du
prochain chapitre.
