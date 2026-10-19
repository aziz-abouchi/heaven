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

![HKT : type vers type](images/20-hkt-functor.svg)

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

## 3. Classes de types : V1 (2026-10-19)

### V1a — déclaratif

    class Functor f
    instance Functor List
    instance Functor Maybe

`class` et `instance` sont enregistrés (`engine.class_names`,
`engine.instance_pairs`). Magics `@class_count`, `@instance_count`.
Pas encore de dispatch.

### V1b — dispatch structurel (matching explicite)

Deux magics :

    (@resolve_instance "Functor" "List" "fmap")       -- -> "fmap_List"
    (@resolve_instance "Functor" "Int" "fmap")        -- -> ""
    (@dispatch_instance "Functor" "List" "fmap" f xs) -- -> fmap_List f xs

Le type `T` est passé en argument **string**. Pas d'inférence de
type. Écriture typique :

    fmap T f xs = (@dispatch_instance "Functor" T "fmap" f xs)
    fmap "List" inc (HCons 1 HNil)   -- -> (HCons 2 HNil)

Testé sur `List` (empty/one/multi). Voir
`tests/test_hkt_v1b_step2.hvn`.

### Ce qui manque encore

- **V1b pas 3** : dispatch sur `List` sans quotes (accès au nom
  d'un nœud `.sym`). ~1 bloc.
- **V1c** : contraintes `fmap : Functor f => ...` vérifiées. Un
  checker simple après pas 3.
- **Instances multiples** : `Int` Monoid+ vs Monoid*. Nécessite
  `newtype`.

### Quantification universelle explicite

En Haskell : `id :: forall a. a -> a`. En Heaven, la quantification
est implicite. Le `forall` explicite viendra plus tard (rank-2).

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
- Heaven accepte `sig wrap : (f : Type) -> ...` (15/15 tests).
- Les **classes de types** sont livrées en V1a (déclaratif) et
  V1b (dispatch structurel). Les contraintes `Functor f =>`
  arrivent en V1c.
- Les HKT sont **l'outil** des algèbres : une `map` pour tous les
  `Functor`.
- On emprunte ici à **Fantasy Land** (McKenna) et à **Haskell**.
