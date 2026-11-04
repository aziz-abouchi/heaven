# Chapitre 8 — Définir ses types : le monde qu'on crée

> **Version 2 (2026-11-04)** — rédaction from scratch (v1 n'a pas de chapitre dédié).
> Source de la syntaxe : exemples réels dans `core/std/`, `stdlib/`, `tests/`.
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Les limites de mon langage sont les limites de mon monde. »*
> — Ludwig Wittgenstein, *Tractatus logico-philosophicus*, §5.6

Jusqu'ici, on a utilisé les types que Heaven fournit : `Int`, `Str`,
`Bool`. C'est bien pour démarrer — c'est insuffisant pour vivre.
Aucun programme sérieux ne se contente des types de base. Il faut
**inventer les siens**.

Ce chapitre est consacré à ce pouvoir : **définir ses propres types**.
C'est le moment où le langage cesse d'être un outil qu'on utilise et
devient un matériau qu'on façonne.

## 1. `data` — le mot-clé qui crée des formes

En Heaven, un type se déclare avec `data`. La forme minimale :

    data Bool = true | false

Trois parties :
- `data` — le mot-clé
- `Bool` — le **nom du type** (majuscule par convention)
- `true | false` — les **constructeurs** (les formes possibles)

`Bool` est un type à **deux constructeurs**. Une valeur de type `Bool`
est *forcément* `true` ou `false`. Pas d'autre option. C'est ce qu'on
appelle un **type somme** (sum type).

Un type à **un constructeur** :

    data Unit = unit

Une seule façon d'être `Unit` : c'est `unit`. Utile pour les fonctions
qui n'attendent « rien » (`f _ = ...` peut prendre `unit`).

Un type avec **un champ** :

    data Wrapper = Wrap Int

`Wrap` est un constructeur qui **contient** un `Int`. `(Wrap 42)` est
une valeur de type `Wrapper`. C'est un **type produit** (product type).

## 2. Constructeurs et arité

Les constructeurs peuvent prendre **plusieurs** arguments. Le nombre
s'appelle l'**arité**.

    data Pair a b = pair a b        -- arité 2
    data Result a e = ok a | err e  -- arité 1 par constructeur
    data Array = MkArray Int Int Int  -- arité 3

`Pair` a **un seul constructeur** `pair` d'arité 2. `Result` a **deux
constructeurs**, chacun d'arité 1. `Array` a un constructeur d'arité 3.

**Ce que ça signifie concrètement** :

    (pair 1 2)        -- valide, Pair Int Int
    (pair 1)          -- INVALIDE, arité 2 attendue
    (pair 1 2 3)      -- INVALIDE, arité 2 attendue
    (ok 42)           -- valide, Result Int e (e à inférer)
    (err "boom")      -- valide, Result a Str

L'arité est **vérifiée**. Le compilateur (ou l'interpréteur) refuse une
construction avec le mauvais nombre d'arguments. C'est une garantie
forte — pas de `pair 1` qui deviendrait `pair 1 nil` silencieusement.

## 3. Types paramétrés

`Pair a b` a **deux paramètres de type** : `a` et `b`. Ce sont des
places vides, qu'on remplit à l'usage.

    (pair 1 2)          -- Pair Int Int
    (pair "x" true)     -- Pair Str Bool
    (pair 1 "x")        -- Pair Int Str

Le même constructeur `pair` marche pour **n'importe quels** types `a`
et `b`. C'est le **polymorphisme paramétrique** — déjà vu au chapitre 3,
appliqué à tes propres types.

Exemples réels du repo :

    data Option a = None | Some a
    data Result a e = ok a | err e
    data Stream a = Cons a (Stream a) | End    -- récursif !

`Stream a` est **récursif** : `Cons a (Stream a)` contient un `Stream a`.
C'est comme ça qu'on définit des structures infinies (le chapitre 11
sur les streams en profite).

## 4. Pattern matching sur constructeurs

C'est bien de créer des types. C'est mieux de les **utiliser**. Le
pattern matching (chapitre 4) s'applique aux constructeurs qu'on vient
de définir.

    -- Fonctions sur Bool
    neg true  = false
    neg false = true

    -- Fonctions sur Option
    from_option None    d = d
    from_option (Some x) _ = x

    -- Fonctions sur Pair
    swap (pair x y) = (pair y x)

    -- Fonctions sur Stream
    head_stream (Cons x _) = x
    tail_stream (Cons _ xs) = xs

Le pattern `(Some x)` **décompose** la valeur : `x` est lié au contenu.
Le pattern `None` ne lie rien — c'est le cas « vide ».

**Règle d'or** : l'ordre des clauses est sémantique (chapitre 4, Piège).
Pour `Option`, mets `None` et `(Some x)` — l'ordre n'a pas d'importance
ici (pas de chevauchement). Mais pour `Result`, si tu écris `(ok _)`
avant `(err _)`, tu couvres 50 % des cas dès la première clause. Le
suivant ne s'applique que si `ok` échoue.

## 5. Les types réels du repo

Voici les types que Heaven utilise dans sa propre bibliothèque
(`core/std/*.hvn`, `stdlib/*.hvn`). Ils sont **réels**, testés,
utilisés :

| Type | Définition | Usage |
|---|---|---|
| `Bool` | `data Bool = true \| false` | logique |
| `Ordering` | `data Ordering = LT \| EQ \| GT` | comparaison |
| `Option a` | `data Option a = None \| Some a` | valeur optionnelle |
| `Result a e` | `data Result a e = ok a \| err e` | succès/erreur |
| `Pair a b` | `data Pair a b = pair a b` | couple |
| `Stream a` | `data Stream a = Cons a (Stream a) \| End` | flux infini |
| `BigInt` | `data BigInt = BZero \| BPos BList \| BNeg BList` | entiers arbitraires |
| `BList` | `data BList = BNil \| BCons Int BList` | liste binaire |
| `Array` | `data Array = MkArray Int Int Int` | tableau bas niveau |
| `Vec (n : Nat)` | `data Vec (n : Nat) = Nil \| Cons a (Vec n)` | vecteur dépendant |

Tu remarques `Vec (n : Nat)` : c'est **plus tard** (types dépendants,
chapitre 33). La syntaxe est là, mais on ne l'exploitera pas encore.

## Piège — l'arité, encore et toujours

Le piège le plus courant quand on définit ses types, c'est de
**confondre le nombre d'arguments du constructeur avec le nombre de
paramètres du type**.

    data Result a e = ok a | err e

- Le **type** a 2 paramètres (`a`, `e`).
- Le **constructeur** `ok` a 1 argument (de type `a`).
- Le **constructeur** `err` a 1 argument (de type `e`).

Donc :

    (ok 42)        -- valide
    (ok 42 "x")    -- INVALIDE, `ok` attend 1 arg
    (err "boom")   -- valide

Et pour `Pair` :

    data Pair a b = pair a b

- Le **type** a 2 paramètres (`a`, `b`).
- Le **constructeur** `pair` a 2 arguments (`a` et `b`).

    (pair 1 2)     -- valide
    (pair 1)       -- INVALIDE
    (pair 1 2 3)   -- INVALIDE

**Cas vécu** : `test_data_eq.hvn` (12 tests) et `test_data.hvn` (2 tests)
testent exactement cette vérification. Si tu passes 3 arguments à
`pair`, tu obtiens une erreur claire — pas un crash silencieux.

**Autre piège** : `data Nat` dans le repo est parfois écrit **sans
constructeur visible** sur la même ligne (par exemple `data Nat` seul).
C'est un type **abstrait** dans ce contexte — il vient avec des
constructeurs définis ailleurs, ou c'est un type primitif. Ne présume
pas que `data X` sans `=` n'a pas de constructeurs. **Vérifie** dans
le contexte.

## Sous le capot — comment un constructeur est stocké

Quand tu écris `(pair 1 2)`, voici ce que le Store retient
(`src/core/expr.zig`) :

    Node {
      tag: .ctor
      payload: <Sym "pair">       -- nom du constructeur, interné
      aux: <arity 2>               -- arité attendue
      span_a: [1, 2]               -- les arguments (IDs des enfants)
      span_b: []                   -- (réservé, vide pour un ctor)
    }

**Trois choses à retenir** :

1. **Le constructeur est un tag `.ctor`**, pas un appel de fonction.
   `(pair 1 2)` n'est **pas** `(apply pair [1, 2])` — c'est une
   construction de nœud. Le runtime sait que c'est une donnée, pas un
   calcul à faire.
2. **L'arité est stockée** dans `aux` (u32). C'est ce qui permet la
   vérification « 3 args pour `pair` → erreur ». Chaque constructeur
   d'un `data` a son arité propre.
3. **Le pattern matching teste `payload == "pair"` puis extrait les
   enfants de `span_a`**. C'est exactement le même mécanisme que
   `unify` (kanren, chapitre 32) — pattern matching et unification
   sont le **même algorithme** sur des structures différentes.

**Ce qui n'existe pas en V0** :
- **Types génériques au runtime** : `Pair a b` est stocké comme un
  `ctor` avec deux enfants, sans information de type. Le polymorphisme
  est **dans le type checker**, pas dans la valeur. `(pair 1 2)` et
  `(pair "x" true)` sont des nœuds identiques structurellement.
- **Type classes** sur constructeurs : `Option` n'a pas d'instance
  `Functor` automatique. Il faut la définir manuellement (chapitre 9).
- **Dérivation automatique** (`deriving` en Haskell) : pas en V0. Si
  tu veux `Eq`, `Ord`, `Show` sur ton type, tu écris tout à la main.

Le chapitre 10 (`structures récursives`) revient sur les types
récursifs (`Stream`, `BList`) et les schémas de récursion qu'on peut
en tirer (fold, unfold).

## Exercices

1. **Créer un type.** Définis `data Couleur = Rouge | Vert | Bleu`
   puis une fonction `to_string` qui retourne `"rouge"`, `"vert"` ou
   `"bleu"` selon la couleur. Teste avec `(to_string Rouge)` → `"rouge"`.

2. **Type à deux champs.** Définis `data Complexe = MkComplexe Int Int`
   (partie réelle, partie imaginaire). Écris `norme2` qui retourne
   `a*a + b*b` pour `(MkComplexe a b)`. Teste avec `(MkComplexe 3 4)`
   → `25`.

3. **Récursif.** Définis `data Arbre = Feuille Int | Noeud Arbre Arbre`.
   Écris `somme` qui additionne toutes les `Feuille`. Teste avec
   `(Noeud (Feuille 1) (Noeud (Feuille 2) (Feuille 3)))` → `6`.
   *Piège* : l'ordre des clauses n'a pas d'importance ici, mais si
   tu avais mis `(Noeud _ _)` en premier, `Feuille` serait
   inatteignable.

4. **Arité.** Écris `data Triple = MkTriple Int Int Int`. Puis essaie
   `(MkTriple 1 2)`. Que se passe-t-il ? Compare avec
   `(MkTriple 1 2 3)`. *Indice* : c'est la vérification d'arité du
   sous-chapitre 2. Note le message exact.

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.

## À toi de jouer

Tu sais maintenant :
- déclarer un type avec `data` ;
- distinguer type somme (`Bool`) et type produit (`Pair`) ;
- passer des paramètres (`Option a`) ;
- faire du pattern matching sur tes constructeurs ;
- reconnaître les pièges d'arité.

Le chapitre suivant (`09-typeclasses`) plonge dans les **contrats
avec des lois** : comment dire qu'un type se comporte « comme un
monoïde », « comme un functor », et comment vérifier que c'est vrai.

Mais avant, une question : **peux-tu définir un type qui se contient
lui-même ?** `data Stream a = Cons a (Stream a) | End` le fait déjà.
Qu'est-ce qui empêche `data Bad = MkBad Bad Bad` (sans cas de base)
d'être infini ? Réfléchis — le chapitre 10 (structures récursives)
donnera la réponse.
