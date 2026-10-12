# Specification -- Algebres (Fantasy Land pour Heaven)

**Statut** : V1 (roadmap)
**Reference** : https://github.com/fantasyland/fantasy-land
**Version Heaven cible** : V1 (HKT + type classes)

---

## 1. Objectif

Heaven V1 doit supporter les structures algebriques communes
(foncteurs, monades, monoides, etc.) avec les memes lois que
Fantasy Land. Cette specification definit :

- La liste des algebres a implementer.
- Leurs lois mathematiques.
- Le mapping vers la syntaxe Heaven.
- L'ordre d'implementation (dependances).

---

## 2. Definition d'une algebre

> *« An algebra is a set of values, a set of operators that it
> is closed under and some laws it must obey. »*

Exemple : un **monoide** est un ensemble de valeurs muni d'une
operation `concat` associative et d'un element neutre `empty`.

En Heaven V1, une algebre est une **type class** :

    class Monoid a where
      concat : a -> a -> a
      empty  : a

    instance Monoid (List a) where
      concat = append
      empty  = nil

---

## 3. Hierarchie des algebres

Trois familles independantes.

### 3.1 Comparaison

| Algebre | Operation | Depend de |
|---|---|---|
| **Setoid** | `equals` | -- |
| **Ord** | `lte` | Setoid |

### 3.2 Composition

| Algebre | Operation | Depend de |
|---|---|---|
| **Semigroupoid** | `compose` | -- |
| **Category** | `id` | Semigroupoid |
| **Semigroup** | `concat` | -- |
| **Monoid** | `empty` | Semigroup |
| **Group** | `invert` | Monoid |

### 3.3 Structure fonctionnelle

| Algebre | Operation | Depend de |
|---|---|---|
| **Functor** | `map` | -- |
| **Contravariant** | `contramap` | -- |
| **Apply** | `ap` | Functor |
| **Applicative** | `of` | Apply |
| **Chain** | `chain` | Apply |
| **Monad** | -- | Applicative + Chain |
| **ChainRec** | `chainRec` | Chain |
| **Alt** | `alt` | Functor |
| **Plus** | `zero` | Alt |
| **Alternative** | -- | Applicative + Plus |
| **Extend** | `extend` | Functor |
| **Comonad** | `extract` | Extend |
| **Bifunctor** | `bimap` | Functor |
| **Profunctor** | `promap` | Functor |
| **Foldable** | `reduce` | -- |
| **Traversable** | `traverse` | Functor + Foldable |
| **Filterable** | `filter` | -- |

---

## 4. Lois

Les lois sont **obligatoires** : une instance qui ne les respecte
pas n'est pas valide. Chaque loi devient un test dans
`tests/test_laws.hvn`.

### Setoid

1. **Reflexivite** : `a.equals(a) == true`
2. **Symetrie** : `a.equals(b) == b.equals(a)`
3. **Transitivite** : `a.equals(b) && b.equals(c) -> a.equals(c)`

### Ord (herite de Setoid)

1. **Totalite** : `a.lte(b) || b.lte(a)`
2. **Antisymetrie** : `a.lte(b) && b.lte(a) -> a.equals(b)`
3. **Transitivite** : `a.lte(b) && b.lte(c) -> a.lte(c)`

### Semigroup

1. **Associativite** : `a.concat(b).concat(c) == a.concat(b.concat(c))`

### Monoid (herite de Semigroup)

1. **Identite a droite** : `m.concat(empty) == m`
2. **Identite a gauche** : `empty.concat(m) == m`

### Functor

1. **Identite** : `u.map(id) == u`
2. **Composition** : `u.map(f . g) == u.map(g).map(f)`

### Apply (herite de Functor)

1. **Composition** : `v.ap(u.ap(a.map(compose))) == v.ap(u).ap(a)`

### Applicative (herite de Apply)

1. **Identite** : `v.ap(of(id)) == v`
2. **Homomorphisme** : `of(x).ap(of(f)) == of(f(x))`
3. **Interchange** : `of(y).ap(u) == u.ap(of(f => f(y)))`

### Chain (herite de Apply)

1. **Associativite** : `m.chain(f).chain(g) == m.chain(x => f(x).chain(g))`

### Monad (herite de Applicative + Chain)

1. **Identite a gauche** : `of(a).chain(f) == f(a)`
2. **Identite a droite** : `m.chain(of) == m`

### Extend (herite de Functor)

1. `w.extend(g).extend(f) == w.extend(_w => f(_w.extend(g)))`

### Comonad (herite de Extend)

1. `w.extend(_w => _w.extract()) == w`
2. `w.extend(f).extract() == f(w)`

### Bifunctor (herite de Functor)

1. **Identite** : `p.bimap(id, id) == p`
2. **Composition** : `p.bimap(a => f(g(a)), b => h(i(b))) == p.bimap(g, i).bimap(f, h)`

### Profunctor (herite de Functor)

1. **Identite** : `p.promap(id, id) == p`
2. **Composition** : `p.promap(a => f(g(a)), b => h(i(b))) == p.promap(f, i).promap(g, h)`

---

## 5. Mapping Fantasy Land -> Heaven V1

| Fantasy Land | Heaven V1 | Note |
|---|---|---|
| `fantasy-land/equals` | `equals` | -- |
| `fantasy-land/lte` | `lte` | -- |
| `fantasy-land/compose` | `compose` | -- |
| `fantasy-land/id` | `id` | -- |
| `fantasy-land/concat` | `concat` | -- |
| `fantasy-land/empty` | `mempty` | evite collision avec `empty` |
| `fantasy-land/invert` | `invert` | -- |
| `fantasy-land/map` | `fmap` | evite collision avec List.map |
| `fantasy-land/contramap` | `contramap` | -- |
| `fantasy-land/ap` | `ap` | -- |
| `fantasy-land/of` | `pure` | -- |
| `fantasy-land/chain` | `bind` | reserve du noyau, a discuter |
| `fantasy-land/chainRec` | `chainRec` | -- |
| `fantasy-land/alt` | `alt` | -- |
| `fantasy-land/zero` | `zero` | reserve ? |
| `fantasy-land/extend` | `extend` | -- |
| `fantasy-land/extract` | `extract` | -- |
| `fantasy-land/bimap` | `bimap` | -- |
| `fantasy-land/promap` | `promap` | -- |
| `fantasy-land/reduce` | `fold` | -- |
| `fantasy-land/traverse` | `traverse` | -- |
| `fantasy-land/filter` | `filter` | -- |

Notes :
- `bind` est reserve par le noyau (6 primitives). Renommage possible
  en `chain`.
- `map` existe deja sur List (`core/std/list.hvn`). `fmap` evite
  la collision.
- `zero` est deja un constructeur de `Nat` (Peano).

---

## 6. Ordre d'implementation (V1)

Dependances resolues dans l'ordre :

1. **Setoid** (`equals`) -- deja partiel dans `core/std/eq.hvn`
2. **Semigroup** (`concat`) -- deja partiel (`list.hvn`)
3. **Monoid** (`mempty`) -- a creer (`core/std/monoid.hvn`)
4. **Ord** (`lte`, `Ordering`) -- a creer (`core/std/ord.hvn`)
5. **Functor** (`fmap`) -- a creer (`core/std/functor.hvn`)
6. **Apply** (`ap`) -- depend de Functor
7. **Applicative** (`pure`) -- depend de Apply
8. **Chain** (`chain`) -- depend de Apply
9. **Monad** -- depend de Applicative + Chain
10. **Foldable** (`fold`) -- a creer (`core/std/foldable.hvn`)
11. **Traversable** (`traverse`) -- depend de Functor + Foldable
12. **Extend/Comonad** -- pour Stream, si utile
13. **Bifunctor/Profunctor** -- pour Pair et fonctions

---

## 7. Tests des lois

Un fichier dedie `tests/test_laws.hvn` verifie les lois sur les
instances existantes. Exemples :

    -- Functor List : identite
    test "Functor List identity": (fmap id (list 1 2 3)) == (list 1 2 3)

    -- Monoid List : identite a gauche
    test "Monoid List left-id": (concat mempty (list 1 2 3)) == (list 1 2 3)

    -- Setoid Int : reflexivite
    test "Setoid Int refl": (equals 42 42) == true

Les lois doivent **toutes** passer. Si une instance ne les respecte
pas, elle n'est pas enregistree.

---

## 8. Ce qui manque pour V1

L'implementation des algebres exige **HKT** (Higher-Kinded Types) :
un parametre de type qui est lui-meme un constructeur de type.

    class Functor f where        -- f est higher-kinded
      fmap : (a -> b) -> f a -> f b

Heaven V0.5 a les bases (types en position d'argument), mais pas
l'**unification bidirectionnelle** ni les **type classes generiques**.
Voir `docs/ROADMAP.md` section V1.

---

## 9. Historique

| Version | Date | Changement |
|---|---|---|
| Draft | 2026-10-12 | Specification initiale, basee sur Fantasy Land |
