# Chapitre 10 — Structures récursives : se contenir soi-même

> **Version 2 (2026-11-04)** — rédaction from scratch (v1 = `14-recursion-schemes`
> couvre cata/ana/hylo, plus avancé ; ce chapitre couvre les structures récursives
> de base + fold simple).
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Une chose est ce qu'elle est, et contient ce qu'elle n'est pas
> encore. »*
> — Héraclite, fragment B49a

Le chapitre 8 t'a appris à créer des types. Tu sais faire `Bool`,
`Pair`, `Option`, `Result`. Ce sont des types **finis** — ils
contiennent un nombre fixe de valeurs.

Ce chapitre ouvre une porte : les types **récursifs**, ceux qui se
contiennent eux-mêmes. Une liste, un arbre, une expression — ce sont
tous des structures récursives. Ce sont elles qui font la puissance
du fonctionnel.

## 1. Un type qui se contient

Un entier est fini. Un `Bool` est fini. Une liste **non**.

    data List a = Nil | Cons a (List a)

Lis la définition à voix haute : « une liste de `a`, c'est soit
`Nil` (vide), soit `Cons a (List a)` — un élément, suivi d'une
**liste du même type** ».

`List a` **contient** `List a`. C'est légal, parce qu'il y a un
**cas de base** (`Nil`) qui arrête la récursion. Sans `Nil`, la
définition serait infinie, et le compilateur la refuserait (ou ton
programme boucherait).

C'est exactement le principe du chapitre 4 (récursion) — cas de
base + cas récursif — mais appliqué aux **types** au lieu des
**fonctions**. Une liste est récursive comme une fonction factorielle
est récursive.

## 2. Construire une liste

    Nil                                  -- liste vide
    (Cons 1 Nil)                         -- [1]
    (Cons 1 (Cons 2 Nil))                -- [1, 2]
    (Cons 1 (Cons 2 (Cons 3 Nil)))       -- [1, 2, 3]

Chaque `Cons` ajoute un élément **à gauche**. Le `Nil` final ferme
la liste. C'est une structure **persistante** : `(Cons 1 xs)` ne
modifie pas `xs`, il crée une nouvelle liste qui **partage** `xs`.
En mémoire, c'est très efficace — pas de copie.

C'est pour ça que `(Cons 1 (Cons 2 Nil))` et `(let xs = (Cons 2 Nil)
in (Cons 1 xs))` sont la **même valeur** (même structure partagée),
même si tu les as écrites différemment.

## 3. Pattern matching récursif

Une fonction sur une liste doit traiter **les deux cas** :
vide (`Nil`), non-vide (`Cons`). C'est exactement le chapitre 4
(récursion structurelle), appliqué à `List`.

    -- Longueur d'une liste
    length Nil = 0
    length (Cons _ xs) = 1 + (length xs)

    -- Somme des éléments (entiers)
    sum Nil = 0
    sum (Cons x xs) = x + (sum xs)

    -- Concaténation
    append Nil ys = ys
    append (Cons x xs) ys = (Cons x (append xs ys))

    -- Inverser
    reverse xs = (reverse_helper xs Nil)
    reverse_helper Nil acc = acc
    reverse_helper (Cons x xs) acc = (reverse_helper xs (Cons x acc))

Regarde le **parallélisme** entre le type et les fonctions :

| Type | Fonction correspondante |
|---|---|
| `Nil` | `length Nil = 0` |
| `Cons a rest` | `length (Cons _ rest) = 1 + (length rest)` |

La fonction **suit** le type. Chaque cas du type a un cas dans la
fonction. C'est la **récursion structurelle** — le chapitre 4 l'a
introduite, ce chapitre la généralise à toutes les structures.

## 4. Fold : l'abstraction de la récursion

Regarde `sum`, `length`, `append` — ils ont **tous** la même forme :

    -- Un cas de base (Nil)
    -- Un cas récursif (Cons x xs) qui combine x et (recurse sur xs)

C'est le pattern **fold**. On peut l'extraire une fois pour toutes :

    -- foldr : replier une liste de droite à gauche
    foldr _ acc Nil = acc
    foldr f acc (Cons x xs) = (f x (foldr f acc xs))

Trois arguments :
- `f` : une fonction à **deux** arguments (`x` et le résultat accumulé)
- `acc` : l'**accumulateur** (valeur de départ, pour `Nil`)
- la liste

`foldr` **remplace** `Cons` par `f`, et `Nil` par `acc`. C'est une
substitution structurelle. Exemples :

    -- length via foldr
    length xs = (foldr (λ_ n. 1 + n) 0 xs)

    -- sum via foldr
    sum xs = (foldr (+) 0 xs)

    -- append via foldr (plus subtil)
    append xs ys = (foldr (λx rest. (Cons x rest)) ys xs)

Le `foldr` capture le **squelette** de la récursion. Tu ne l'écris
plus à chaque fois — tu passes juste la fonction qui combine.

Il existe aussi `foldl` (gauche à droite, avec accumulateur en
premier) :

    foldl _ acc Nil = acc
    foldl f acc (Cons x xs) = (foldl f (f acc x) xs)

`foldl` est **TCO** (récursion terminale, chapitre 4), `foldr` ne
l'est pas. Pour les grandes listes, `foldl` est plus sûr. Mais
`foldr` marche sur les **structures infinies** (streams, chapitre 11),
où `foldl` boucherait.

**Règle** : `foldl` pour les listes finies grosses, `foldr` pour les
structures paresseuses et les opérations « préfixes » (comme
`append`).

## 5. Arbres : la récursion bifurque

Une liste est **linéaire** — un seul chemin. Un **arbre** bifurque :

    data Tree a = Leaf | Node (Tree a) a (Tree a)

Un `Tree a` est soit une `Leaf` (feuille, vide), soit un `Node` avec
**deux** sous-arbres (`gauche`, `droit`) et une valeur (`a`).

Pattern matching :

    -- Compter les nœuds
    size Leaf = 0
    size (Node l _ r) = 1 + (size l) + (size r)

    -- Somme des valeurs
    sum_tree Leaf = 0
    sum_tree (Node l x r) = x + (sum_tree l) + (sum_tree r)

    -- Hauteur
    height Leaf = 0
    height (Node l _ r) = 1 + (max (height l) (height r))

Regarde `Node l _ r` : trois patterns en un (`l`, `_`, `r`). Le `_`
ignore la valeur du nœud. La structure est **binaire** — chaque
nœud a **deux** enfants.

Un arbre binaire **ordonné** (BST) est une structure classique :

    insert Leaf x = (Node Leaf x Leaf)
    insert (Node l v r) x =
      (if (< x v)
        (Node (insert l x) v r)
        (Node l v (insert r x)))

Le type `Tree` **n'est pas** ordonné — c'est `insert` qui impose
l'ordre. Le type dit juste « deux enfants ». C'est la fonction qui
donne le sens.

## 6. Les structures récursives du repo

Heaven utilise intensivement les types récursifs. Voici les plus
importants :

| Type | Définition | Usage |
|---|---|---|
| `List a` | `data List a = Nil \| Cons a (List a)` | listes |
| `Stream a` | `data Stream a = Cons a (Stream a) \| End` | flux infinis (ch. 11) |
| `BList` | `data BList = BNil \| BCons Int BList` | chiffres BigInt |
| `A` (test) | `data A = ANil \| ACons Int A` | tests récursion |
| `Vec (n : Nat)` | `data Vec (n : Nat) = Nil \| Cons a (Vec n)` | taille indexée (ch. 33) |
| `Arbre` (test) | `data Arbre = Feuille Int \| Noeud Arbre Arbre` | tests fold |

Tu remarques `Vec (n : Nat)` : le paramètre `n` est un **entier**,
pas un type. C'est du **dépendant** (chapitre 33). `Cons a (Vec n)`
signifie « un élément + un vecteur de taille `n`, qui donne un
vecteur de taille `n+1` ». La taille est **dans le type**. C'est
puissant et plus tard.

## Piège — la liste infinie

Le piège le plus célèbre avec les types récursifs, c'est de
**construire une valeur infinie sans le vouloir**.

    -- Une liste infinie, sans Nil
    zeros = (Cons 0 zeros)

    -- length zeros ?
    -- → boucle infinie, ou stack overflow

`zeros` est une liste **récursive infinie**. `Cons 0 zeros` référence
`zeros` — qui référence `Cons 0 zeros` — etc. Sur une machine
finie, c'est une boucle.

**Ce qui rend ça légal** : le type `List a` n'interdit pas les
valeurs infinies. Il dit juste « soit Nil, soit Cons ». `zeros`
est une valeur **valide** de `List Int` (même si elle est infinie).

**Comment s'en protéger** :
1. **`take n xs`** — forcer une longueur finie. `(take 5 zeros)` =
   `[0, 0, 0, 0, 0]`. Le `take` arrête la récursion.
2. **Streams** (chapitre 11) — la version **paresseuse** des listes.
   `Stream Int` peut être infini **en mémoire** parce que le `delay`
   capture le calcul, pas la valeur. `(nats 0)` est légal, infini,
   et on peut `take`.
3. **`Nil` explicite** — pour les listes finies, toujours terminer
   par `Nil`.

**Cas vécu** : `test_stream_lazy.hvn` (8/8) teste exactement cette
différence. Une liste sans `Nil` = boucle. Un `Stream` avec `delay`
= valeur infinie manipulable.

**Autre piège** : `data Bad = MkBad Bad Bad` — pas de cas de base !
Le compilateur Heaven refuse (ou ta définition est inutilisable).
Les types récursifs exigent **au moins un cas non-récursif**
(`Nil`, `Leaf`, `End`, ...).

## Sous le capot — comment `Cons` est stocké, et pourquoi c'est efficace

Quand tu écris `(Cons 1 (Cons 2 Nil))`, voici la structure mémoire :

    Node(id=1) {
      tag: .ctor
      payload: <Sym "Cons">
      aux: 2                         -- arité
      span_a: [int(1), node(2)]      -- 1, puis lien vers le reste
    }
    Node(id=2) {
      tag: .ctor
      payload: <Sym "Cons">
      aux: 2
      span_a: [int(2), node(3)]
    }
    Node(id=3) {
      tag: .ctor
      payload: <Sym "Nil">
      aux: 0
      span_a: []
    }

**Trois choses importantes** :

1. **Structure partagée** : si tu écris `(let xs = (Cons 2 Nil) in
   (Cons 1 xs))`, le `xs` du node 1 **pointe vers le même** node 2
   que `xs`. Pas de copie. C'est ce qui rend les listes immuables
   **efficaces** — ajouter en tête est O(1), pas O(n).

2. **Pas de GC entre les forces** : tant que le node 1 est vivant,
   le node 2 et le node 3 le sont aussi (référencés transitivement).
   Heaven V0 ne collecte pas ces nodes — ils vivent jusqu'à la fin
   du programme. Pour les grosses structures, ça peut être un
   problème (`_memory.md`).

3. **`foldr` reconstruit la pile d'appels** : `foldr f acc
   (Cons x xs)` = `f x (foldr f acc xs)`. La récursion empile `f` à
   chaque niveau. Pour une liste de 1M, 1M cadres. `foldl` évite ça
   (TCO). C'est pour ça que `foldl` est préféré sur les listes
   finies grosses — pas par choix esthétique, par nécessité
   mémoire.

**`Vec (n : Nat)`** (chapitre 33) : le runtime ne peut pas vérifier
`n` (le type est effacé). C'est le **type checker** qui vérifie
statiquement que `(Cons 1 (Vec 2))` a bien type `Vec 3`. Le runtime
ne stocke que le `Cons` — la longueur est **dans le type**, pas dans
la valeur. C'est le principe de l'**effacement de types**
(`type erasure`), qui rend le dépendant utilisable sans coût runtime.

## Exercices

1. **Longueur et somme.** Définis `length` et `sum` sur `List Int`.
   Teste `(length (Cons 1 (Cons 2 (Cons 3 Nil)))) == 3` et
   `(sum (Cons 1 (Cons 2 (Cons 3 Nil)))) == 6`. *Piège* : ordre des
   clauses (`Nil` avant `Cons`), sinon `Nil` est inatteignable.

2. **Fold vs récursion manuelle.** Écris `sum` deux fois : une fois
   avec récursion directe (`sum Nil = 0`, `sum (Cons x xs) = x + sum xs`),
   une fois avec `foldr (+) 0`. Lequel est plus clair ? Lequel est
   TCO ? Compare `foldr` et `foldl` sur une liste de 10 000.

3. **Arbre binaire de recherche.** Définis `data Tree = Leaf | Node Tree Int Tree`.
   Écris `insert` (décrit au sous-chapitre 5), `contains`, et
   `to_list` (parcours in-order → liste triée). Teste
   `insert (insert (insert Leaf 2) 1) 3` puis `to_list` → `[1, 2, 3]`.

4. **Liste infinie, mais contenue.** Écris `zeros = (Cons 0 zeros)`
   (liste infinie). Puis `take n xs` qui extrait les `n` premiers
   éléments. `(take 5 zeros)` doit retourner `[0, 0, 0, 0, 0]` sans
   boucler. *Piège* : `take` doit s'arrêter sur `Nil` **et** sur
   `n == 0`, sinon `(take 0 xs)` boucle.

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.

## À toi de jouer

Tu sais maintenant :
- définir des types **récursifs** (List, Tree) ;
- écrire des fonctions qui **suivent** la structure (récursion structurelle) ;
- abstraire le squelette avec **fold** (`foldl`, `foldr`, TCO) ;
- reconnaître et éviter les **listes infinies** non maîtrisées ;
- voir les structures récursives du repo (`List`, `Stream`, `BList`, `Vec`).

Le chapitre 11 (`streams`) reprend `Stream` — la version **paresseuse**
de `List`, qui rend l'infini utilisable. Le chapitre 14
(`recursion-schemes`) généralise `fold` en `cata`, `ana`, `hylo` —
le vocabulaire catégorique de la même idée.

Mais avant, une question : **peux-tu écrire une fonction qui
construit une liste de `n` à `0** (décroissant) ? Et une qui prend
une liste et retourne la liste des éléments **pairs** ? Ces deux
fonctions sont récursives structurelles, mais la première **génère**
et la seconde **filtre**. La différence préfigure `ana` et `cata`
(chapitre 14). Réfléchis-y — c'est la prochaine marche.
