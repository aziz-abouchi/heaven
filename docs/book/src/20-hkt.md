# Chapitre 20 — Types d'ordre supérieur

> *« En Haskell, `Maybe` n'est pas un type — c'est une fonction
>  sur les types. »*
> — Philip Wadler

Prenez `map`. Elle fonctionne sur les listes, mais aussi sur les
`Option`, les `Result`, les `Tree`, les `Stream`... Toutes ces
structures partagent une forme commune : elles **contiennent** des
valeurs. Comment écrire une seule `map` qui marche pour toutes ?

Heaven V0.5 accepte un constructeur de type en **position
d'argument** :

    sig wrap : (f : Type) -> (a : Type) -> f a -> f a

Ce `f` peut être `List`, `Maybe`, `Stream` — n'importe quel type
paramétré. C'est un **type d'ordre supérieur** (HKT).

## 1. Le cas proprement dit

    sig wrap : (f : Type) -> (a : Type) -> f a -> f a

- `f` est un type qui prend un type et en retourne un autre
  (`Type -> Type`).
- `f a` est l'application : `List Int`, `Maybe String`, etc.
- Le constructeur `f` apparaît en tête — c'est ça, un HKT.

Heaven V0.5 accepte cette signature. **15 tests verts** dans
`tests/test_hkt.hvn`.

## 2. Autres cas supportés

### Constructeur en argument sans `sig`

    id_t : (a : Type) -> a -> a

Ici `a` est un type ordinaire. C'est du polymorphisme paramétrique
classique, pas encore HKT — mais la syntaxe est prête.

### Type composé dans le domaine

    sig f_list : (a : Type) -> List a -> Int

Le domaine peut être une application de type paramétré.

## 3. Ce qui manque pour V1

### Classes de types

Ce qu'on aimerait écrire :

    class Functor f where
      map : (a -> b) -> f a -> f b

Heaven V0.5 n'a **pas** de classes. On peut seulement écrire une
signature HKT et l'instancier manuellement pour chaque type.

### Contraintes de type

Encore plus loin :

    map : Functor f => (a -> b) -> f a -> f b

Le `Functor f =>` dit : « `map` marche pour tout `f` qui est un
`Functor` ». Résolu en V1 par résolution d'instance.

### Quantification universelle explicite

En Haskell :

    id :: forall a. a -> a

En Heaven, la quantification est implicite. Le `forall` explicite
viendra en V1 pour les cas rank-2 (polymorphisme de rang supérieur).

### Instances multiples

`Int` peut être un `Monoid` de plusieurs façons (addition, produit,
minimum, maximum...). Résolu en V1 par `newtype`.

## 4. Lien avec les algèbres

Le chapitre 19 a présenté la hiérarchie Fantasy Land. Les HKT
sont **l'outil** qui rend possible l'écriture des classes :

    class Functor f where map : (a -> b) -> f a -> f b

Sans HKT, on écrirait `map_list`, `map_option`, `map_result` — une
par type. Avec, une seule `map`.

Heaven V0.5 est à mi-chemin : la syntaxe HKT est prête, la
résolution d'instance viendra.

## Ce qu'on a appris

- Un **HKT** est un type qui prend un type et en retourne un autre.
- Heaven V0.5 accepte `sig wrap : (f : Type) -> ...` (15/15 tests).
- Les **classes de types** et les **contraintes** arrivent en V1.
- Les HKT sont **l'outil** des algèbres : une `map` pour tous les
  `Functor`.
- On emprunte ici à **Fantasy Land** (McKenna) et à **Haskell**.
