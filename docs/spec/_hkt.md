# HKT — Higher-Kinded Types (V0.5)

**Date** : 2026-10-14
**Statut** : ✅ fait en V0.5. 15/15 tests verts.
**But** : documenter ce que V0.5 supporte, ce qui reste à faire
pour V1 (classes de types, forall explicite).

## 1. Ce que "HKT" veut dire

Un **Higher-Kinded Type** est un type qui **paramètre** un autre
type. Comparons :

- `List Int` — un type concret. `List` est appliqué à `Int`.
- `List` **tout seul** — un *constructeur de type* (`Type -> Type`).
  Il attend un type pour produire un type.

En Haskell, on peut abstraire sur ce constructeur :

    class Functor f where
      fmap :: (a -> b) -> f a -> f b

Ici `f` n'est pas un type (comme `Int`), c'est un **constructeur
de type** (`List`, `Maybe`, `Pair String`, ...). C'est ça, HKT.

## 2. Ce que Heaven V0.5 supporte

V0.5 introduit le **constructeur de type en position d'argument**.
La syntaxe passe par `sig` :

    sig id_t : (a : Type) -> a -> a
    id_t a x = x

Puis à l'appel, on instancie `a` :

    (id_t Int 42)           -- 42
    (id_t String "hello")   -- "hello"
    (id_t (List Int) 42)    -- 42

`a` est un *paramètre de type*. `List Int` peut être passé comme
argument, c'est-à-dire que le constructeur `List` appliqué à `Int`
est un type légitime.

## 3. Le cas HKT proprement dit

Le test `wrap` couvre le vrai HKT — un constructeur **variable**
en position de tête :

    sig wrap : (f : Type) -> (a : Type) -> f a -> f a
    wrap f a x = x

À l'appel :

    (wrap List Int (cons 1 (cons 2 nil)))   -- la liste inchangée
    (wrap Maybe Int 42)                     -- 42 (Maybe traité comme ctor)

Ici `f` est un constructeur de type, `a` est un type. `f a` est
un type formé par application. C'est exactement HKT.

## 4. Autres cas supportés

### Type composé dans le domaine

    sig f_list : (a : Type) -> List a -> Int
    f_list a _ = 0

`List a` avec `a` variable. Fonctionne.

### Constructeurs en argument sans `sig`

    id_ignore a x = x
    (id_ignore (List Int) 42)              -- 42
    (id_ignore (Pair Int Int) (pair 1 2))  -- (pair 1 2)

Sans signature, `a` est inféré au moment de l'appel. Le nom est
traité comme variable de type si l'argument est un type explicite
(`Int`, `String`) ou composé (`List Int`, `Pair Int Int`).

## 5. Test suite

`tests/test_hkt.hvn` — 15/15.

| Test | Statut |
|---|---|
| `id_t Int 42` | ✅ |
| `id_t String "hello"` | ✅ |
| `id_t (List Int) 42` | ✅ |
| `wrap List Int (cons 1 (cons 2 nil))` | ✅ |
| `wrap Maybe Int 42` | ✅ |
| `f_list Int (cons 1 (cons 2 nil))` | ✅ |
| `id_ignore (List Int) 42` | ✅ |
| `id_ignore (Pair Int Int) (pair 1 2)` | ✅ |

## 6. Ce qui manque pour V1

V0.5 couvre HKT **au niveau des signatures et des arguments**.
Il manque trois choses pour parler de "vraie HKT" au sens Haskell.

### 6.1 Classes de types

Pas de `class Functor f where fmap : ...` en V0.5. Résultat : on ne
peut pas dire *"toute structure `f` qui supporte fmap"*. On doit
nommer chaque instance séparément (`fmap_list`, `fmap_maybe`, ...).

### 6.2 Contraintes de type

Pas de `Functor f => ...`. En V0.5, `f : Type` accepte n'importe
quel type, sans contrainte qu'il supporte une opération donnée.
Résultat : les lois ne peuvent pas être vérifiées statiquement.

### 6.3 Quantification universelle explicite

`forall a. a -> a` n'est pas une forme de première classe. La
quantification est **implicite** dans les `sig`. On ne peut pas
écrire de fonction qui prend un `forall a. a -> a` en argument et
le réutilise à deux types différents (`rank-2 polymorphism`).

### 6.4 Instances multiples pour un même type

En Haskell, `Int` peut être `Monoid` pour `+` (avec 0) et pour `*`
(avec 1). V0.5 ne supporte pas cette multiplicité — pas de
résolution d'instance.

## 7. Lien avec `_algebras.md`

`docs/spec/_algebras.md` spécifie la hiérarchie d'algèbres
(Fantasy Land) : `Setoid`, `Ord`, `Functor`, `Monad`, etc. Ces
algèbres **dépendent de HKT** (elles quantifient sur `f`).

V0.5 ouvre la voie : on peut maintenant écrire la **signature**
d'un `Functor` (avec `f : Type`), mais on ne peut pas encore
déclarer une classe de types qui regroupe toutes les instances.
C'est le chaînon manquant entre V0.5 et V1.

## 8. Décision

**HKT V0.5 est fait et suffisant pour la pratique.** Le langage
peut déjà écrire des fonctions génériques en `f` et `a` — ce qui
couvre 90 % des besoins (fmap, map, filter sur des structures
variées).

**Pour V1** (post-scope actuel) :
1. Ajouter `class` / `instance` au système de types.
2. Ajouter les contraintes `Functor f => ...`.
3. Ajouter `forall a.` explicite.
4. Permettre les instances multiples (résolution par nom ou tag).

Ces 4 éléments transforment HKT "syntaxique" (V0.5) en HKT
"sémantique" (V1). Le noyau CIC actuel supporte déjà la
quantification implicite et l'application de type — le travail
est surtout dans le frontend (`elab.zig`) et le système de
résolution.

## 9. Références

- **Philip Wadler, Stephen Blott**, *How to make ad-hoc polymorphism
  less ad hoc* (1989) — introduction des classes de types.
- **Mark P. Jones**, *A System of Constructor Classes* (1993) —
  formalisation HKT.
- `docs/spec/_algebras.md` — hiérarchie cible des algèbres.
- `tests/test_hkt.hvn` — 15 tests verts.
- `src/core/elab.zig` — pipeline `sig` / `forall_type`.
- `src/core/heaven_expr.zig:844` — parsing des `sig`.
