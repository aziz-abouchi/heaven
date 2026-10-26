# Chapitre 2 — Types et catégories

> *« Les catégories ne sont pas des choses — ce sont des manières
> de classer les choses. »*
> — Aristote, *Catégories*

Au chapitre précédent, on a vu Heaven refuser `double "bonjour"` et
on a dit : « parce que `*` demande deux nombres ». Maintenant on va
voir pourquoi, et ce que Heaven sait vraiment.

## 1. Ce qu'on dit d'une chose

Aristote, dans les *Catégories*, distingue dix manières de dire
« ce que c'est » qu'une chose : substance, quantité, qualité,
relation, lieu, temps, position, avoir, action, passion. Ces dix
catégories ne sont pas des choses — ce sont des **manières de
classer** les choses. Des grilles pour penser.

Quand tu dis « Socrate est un homme », tu dis *ce qu'il est*
(substance). Quand tu dis « il mesure 1m70 », tu dis *combien*
(quantité). Ces deux phrases ne disent pas la même chose *de la
même manière*. Les catégories d'Aristote sont là pour rendre ces
distinctions explicites.

Un **type**, dans un langage de programmation, joue le même rôle
que les catégories d'Aristote. Il dit *comment* on peut parler
d'une valeur — pas ce qu'elle est en soi. C'est une **grille de
lecture**, pas une essence cachée.

    heaven> :type 42
    Int

    heaven> :type "bonjour"
    String

`42` est un `Int` (un entier). `"bonjour"` est un `String` (une
suite de caractères). Le type est l'étiquette que le langage
attache à chaque valeur.

## 2. Quatre manières d'être une valeur

![Les quatre types de base](images/02-types-base.svg)

Heaven a quatre types de base — quatre manières de classer les
valeurs :

    heaven> :type 42
    Int

    heaven> :type 3.14
    Float

    heaven> :type "bonjour"
    String

    heaven> :type true
    Bool

    heaven> :type ()
    Unit

- **Int** — un nombre entier (positif, négatif, ou zéro).
- **Float** — un nombre à virgule flottante (pour les calculs
  approchés).
- **String** — une suite de caractères.
- **Bool** — un booléen : `true` ou `false`.
- **Unit** — la valeur unique qui ne porte aucune information.
  Elle s'écrit `()` et se prononce « unit ».

Ces cinq types (dont on dit souvent quatre, car `Unit` est à part)
sont **de base** : on ne les définit pas, on les utilise. Tout le
reste — listes, options, paires, arbres, ce que tu voudras — se
construit à partir d'eux.

Note : `:type ()` et `:type Float` fonctionnent dans le REPL. Il
n'y a pas de type `Float` littéral ici, mais un calcul comme
`(/ 3 2)` en produit.

## 3. Le langage devine : l'inférence

Quand tu écris `42`, Heaven sait que c'est un `Int` sans que tu le
lui dises. C'est ce qu'on appelle l'**inférence de type**.

Regarde :

    heaven> inc x = x + 1
    ✓ clause enregistrée pour 'inc'

    heaven> :type inc
    Int -> Int

Tu n'as écrit *aucun type* dans la définition. Pas une seule fois
le mot `Int`. Pourtant, Heaven a déduit que `inc` prend un `Int`
et rend un `Int`. Comment ?

Parce que `+` est une fonction qui, appliquée à deux `Int`, rend un
`Int`. Et `1` est un `Int`. Donc `x + 1` est un `Int`. Donc `inc x`
est un `Int`. Donc `inc` prend un `Int` et rend un `Int`.

> **État réel (2026-10-26).** L'inférence décrite ici est la
> **cible**. Dans le code actuel, `TypeEnv.infer`
> (`src/core/types.zig:266`) retourne `"Int"` pour toute expression —
> c'est un stub. `DependentChecker.piType` et `sigmaType` retournent
> `0`. L'exemple `inc x = x + 1` donne `Int -> Int` par convention
> (et parce que `+` est câblé), pas par une inférence Hindley-Milner
> réelle. Voir `docs/spec/_claims_vs_reality.md`.

Cette déduction se fait **sans que tu aies à l'écrire**. C'est un
des apports majeurs de Haskell et de ses successeurs (dont Idris,
Agda, et Heaven). Le langage **devine** le type le plus général qui
convient.

Frege, à la fin du XIXᵉ siècle, parlait déjà de cela : une
expression a un **sens** (Sinn) — ce qu'elle signifie — et une
**référence** (Bedeutung) — l'objet qu'elle désigne. Un type, en
programmation, joue le rôle du sens : il dit *comment* on peut
utiliser une valeur, avant même de savoir *quelle* valeur c'est.
On y reviendra à la section 5.

## 4. Types paramétrés : les places vides

![Types paramétrés](images/02-parametric.svg)

Voici une liste :

    heaven> cons 1 (cons 2 nil)
    cons 1 (cons 2 nil)

C'est une liste de deux entiers. Comment en écrire le type ?

    heaven> :type (cons 1 nil)
    List Int

    heaven> :type (cons 1 (cons 2 nil))
    List Int

`List Int` se lit « liste d'Int ». Mais il existe aussi des listes
de `String`, de `Bool`, de n'importe quoi :

    heaven> :type (cons "a" (cons "b" nil))
    List String

Le type `List` n'est **pas complet** tout seul. Il attend un autre
type — un type **paramètre**. On note `List a` où `a` est la place
vide. Quand on remplit la place avec `Int`, on obtient `List Int`.
Quand on la remplit avec `String`, on obtient `List String`.

Trois exemples courants en Heaven :

- **`List a`** — une liste (un nombre variable d'éléments).
- **`Option a`** — une valeur qui peut être absente (`none` ou
  `some x`).
- **`Pair a b`** — deux valeurs ensemble (`pair x y`), chacune
  pouvant être d'un type différent.

Aristote, encore : quand tu dis « trois », tu ne dis pas *quelle
chose est trois*, tu dis *combien* — la place vide de la substance.
Un type paramétré comme `List a` est pareil : `List` dit la *forme*
(une liste), `a` dit la *matière* (ce qu'il y a dedans). Les deux
se remplissent séparément.

*Vérifiable : les `:type` et les exemples ci-dessus fonctionnent
tels quels dans le REPL.*


## 5. Sens et référence

![Le triangle de Frege](images/02-sinn-bedeutung.svg)

Gottlob Frege, dans un article célèbre de 1892 (« Über Sinn und
Bedeutung »), propose une distinction qui va nous aider à
comprendre les types.

Il prend l'exemple de deux expressions :

- **« l'étoile du matin »**
- **« l'étoile du soir »**

Ces deux expressions **désignent le même objet** : la planète
Vénus. Mais elles ont un **sens** différent. L'une dit *quand* on
la voit (le matin), l'autre dit *quand* (le soir). Deux sens, une
seule référence.

Frege en tire une distinction :

- Le **sens** (Sinn) — la manière de présenter l'objet.
- La **référence** (Bedeutung) — l'objet lui-même.

En programmation, cette distinction éclaire la différence entre
types et valeurs. Deux expressions peuvent avoir **la même valeur**
sans avoir **le même type** :

    heaven> 42
    42

    heaven> 40 + 2
    42

Les deux évaluent à `42`. Mais l'une est un `Int` direct, l'autre
est le résultat d'une opération. Le type reste `Int` — mais la
manière de le construire diffère. C'est exactement ce que Frege
appelait le sens.

Un autre exemple : `42` et `6 × 7` désignent le même nombre (la
référence), mais présentent le nombre différemment (le sens). Le
langage peut les distinguer si nécessaire — par exemple pour
prouver qu'ils sont égaux. C'est l'objet du chapitre 8.

Dans Heaven, les types sont notre **sens** principal : ils disent
comment présenter une valeur, avant même de savoir ce que la
valeur vaut. Frege avait vu cela en 1892.

## 6. Vers les types dépendants

Il y a une dernière idée, plus avancée, qu'on annonce ici : les
**types dépendants**. Ce sont des types qui **dépendent d'une
valeur**.

Exemple : le type `Vec n a` désigne un vecteur (une liste de
longueur fixe) contenant `n` éléments de type `a`. `Vec 3 Int`
est un vecteur de trois entiers. `Vec 5 String` est un vecteur de
cinq chaînes. Le type **contient** le nombre `n`.

C'est très puissant. On peut écrire une fonction `head : Vec
(succ n) a -> a` qui prend un vecteur **non vide** — le type
garantit qu'on ne peut pas l'appeler sur un vecteur vide. Pas
besoin de vérification à l'exécution : le type l'interdit.

Aristote aurait aimé. Sa distinction entre les catégories
(substance, quantité, relation) devient, dans un type dépendant,
une **structure interne** au type lui-même. Le type porte sa
propre substance.

Heaven supporte partiellement les types dépendants en V0 (via
`sig`, `data`, `Vec`). On en verra le détail au chapitre 8
(« Preuves et théorèmes »). Pour l'instant, retiens qu'un type
peut contenir une valeur, et que cette idée vient de la logique
de Frege, Russell et Martin-Löf.

## 7. Combien de fois ? — QTT

![Les trois multiplicités QTT](images/02-qtt-multiplicites.svg)

> *« Une ressource linéaire n'est utilisée qu'une fois. Une
> ressource effacée, jamais. Une ressource libre, autant qu'on
> veut. »*
> — à la manière de Jean-Yves Girard, *Linear Logic* (1987)

Une dernière idée, encore plus fine que les types dépendants,
mérite d'être présentée ici — même si Heaven V0 ne fait que s'en
inspirer.

Imagine une fonction qui prend une valeur et la renvoie deux fois :

    heaven> dup x = (pair x x)

Combien de fois `x` apparaît-il dans le corps ? **Deux fois**.
Maintenant, une fonction qui jette son argument :

    heaven> ignore x = 42

Combien de fois `x` apparaît-il dans le corps ? **Zéro fois** —
il est nommé, puis oublié.

Et une fonction qui l'utilise exactement une fois :

    heaven> inc x = x + 1
**Une fois**.

Ces trois situations — zéro, une, plusieurs — correspondent à
trois **régimes d'usage**. En 1987, le logicien français
**Jean-Yves Girard** (né en 1947) a introduit une **logique
linéaire** qui distingue précisément ces régimes. Sa découverte :
le *combien de fois* n'est pas un détail, c'est une **structure
mathématique** à part entière.

### Les trois multiplicités

En QTT — *Quantitative Type Theory*, formalisée par **Robert
Atkey** en 2018 — chaque variable porte une **multiplicité** :

- **`0`** — variable **effacée**. Elle n'est jamais utilisée dans
  le corps. La valeur correspondante n'existe pas au runtime :
  **zéro octet**.
- **`1`** — variable **linéaire**. Elle est utilisée **exactement
  une fois**. Elle a un propriétaire unique : quand on la
  consomme, elle disparaît.
- **`ω`** — variable **libre**. Elle peut être utilisée zéro,
  une, ou plusieurs fois. C'est le régime habituel.

Dans un langage avec QTT, on annoterait :

    dup : a -> 1 (Pair a a)         -- x utilise 2 fois : non, erreur
    ignore : 0 a -> Int             -- a efface
    inc : 1 Int -> Int              -- Int utilise 1 fois

Le vérificateur **rejette** `dup` (utilise x deux fois alors que
la signature dit `1`), accepte `ignore` (x effacé), accepte `inc`
(x linéaire).

### Pourquoi c'est puissant

Trois bénéfices immédiats :

**1. Effacement.** Une variable `0` n'existe pas au runtime. Les
preuves, les types, les annotations — tout ce qui est `0` disparaît
à la compilation. C'est la base du *proof erasure* : on peut écrire
des preuves lourdes sans payer leur coût à l'exécution.

**2. Gestion mémoire.** Une variable `1` a un **propriétaire
unique**. Quand ce propriétaire consomme la variable — au dernier
usage — le compilateur sait qu'il peut libérer la mémoire. Pas de
compteur de références, pas de GC.

**3. Réutilisation in-place.** Si le compilateur voit qu'une
structure linéaire est détruite juste avant qu'une autre de même
taille soit allouée, il peut remplacer `free + alloc` par une
écriture **directement dans la mémoire de l'ancienne**. C'est
l'optimisation *drop-reuse* (Perceus, 2021) — aussi appelée
**FBIP** (Functional But In-Place).

![Drop-reuse (FBIP)](images/02-qtt-drop-reuse.svg)

Résultat : des algorithmes **fonctionnels purs** — `map`,
`filter`, `fold` — qui tournent en temps constant de mémoire, sans
GC. C'est le rêve de la programmation fonctionnelle efficace.

### Où en est Heaven

Heaven V0 **n'implémente pas** QTT. C'est une **inspiration** pour
la suite, documentée dans `docs/spec/_memory.md`. Aujourd'hui :

- La **couche mémoire** est explicite : `core/std/memory.hvn` +
  `Arena` (livré 2026-10-13).
- Les continuations délimitées one-shot (`@prompt`/`@throw`) sont
  livrées — la partie *linéaire* de leur usage viendra plus tard.
- Le suivi quantitatif des variables et l'injection automatique
  de `drop`/`alloc` par le compilateur restent à faire.

C'est un chantier long. Mais l'idée directrice est claire : *un
type n'est pas seulement une catégorie de valeurs — c'est aussi
une indication sur la manière dont elles circulent*.

Aristote classait les choses. Frege distinguait le sens de la
référence. Girard et Atkey ajoutent une troisième dimension :
**combien de fois**.

### 7.1 Un jugement de typage quantitatif

![Un jugement de typage avec multiplicités](images/02-qtt-jugement.svg)

Un vérificateur QTT ne dit pas seulement « telle expression a tel
type ». Il dit :

    Γ ⊢ t : A

qui se lit *« dans le contexte Γ, le terme t a le type A »*. Ce
qui change avec QTT, c'est la **structure du contexte** Γ : ce
n'est plus un simple ensemble de variables, c'est un ensemble de
paires `(variable, multiplicité)` :

    Γ = { x :¹ A, y :⁰ B, z :^ω C }

Traduction :

- `x :¹ A` — `x` est linéaire : utilisé **exactement une fois**.
- `y :⁰ B` — `y` est effacé : **jamais** utilisé dans le corps.
- `z :^ω C` — `z` est libre : utilisé zéro, une, ou plusieurs fois.

Quand on écrit le corps de la fonction, le vérificateur **compte**
les usages de chaque variable et compare aux multiplicités
déclarées. S'il y a un écart, il refuse :

    f : 1 Int -> Int
    f x = x + x             -- ✗ x utilisé 2 fois, mais déclaré 1

    f : 0 Int -> Int
    f x = x + 1             -- ✗ x utilisé, mais déclaré 0

    f : ^ω Int -> Int
    f x = x + x             -- ✓ libre : 2 usages OK

C'est un **raffinement du système de types** : au lieu de vérifier
seulement *quel type* a une valeur, on vérifie aussi *combien de
fois* elle est consommée.

### 7.2 Le lien avec la logique linéaire

Girard, en inventant QTT, ne partait pas de l'informatique — il
partait de la **logique**. Sa *logique linéaire* (1987) propose
une nouvelle lecture des connecteurs logiques :

- **`A ⊗ B`** (tenseur) — *« A et B »*, mais chaque ressource est
  utilisée une fois : c'est le produit linéaire, l'équivalent du
  `Pair` dans une lecture linéaire.
- **`A ⊕ B`** (plus) — *« A ou B »*, choix exclusif.
- **`!A`** (bang) — *« A est disponible sans contrainte »*. C'est
  ce qui permet de *répliquer* une ressource : passer de linéaire
  à libre.
- **`A ⊸ B`** (lolli) — *« A implique B »*, mais A est *consommé*
  pour produire B. C'est la flèche linéaire.

Ce vocabulaire éclaire QTT : les trois multiplicités `0`, `1`,
`ω` sont exactement les trois régimes que Girard distingue. `ω`
correspond à `!A` (« je peux l'utiliser autant que je veux »).
`1` correspond à `A` sans `!`. `0` correspond à une ressource
présente dans le contexte mais jamais consommée.

La **correspondance de Curry-Howard** s'étend : les preuves en
logique linéaire correspondent à des programmes qui consomment
leurs ressources linéairement. C'est exactement ce dont Heaven a
besoin pour la mémoire.

### 7.3 Un exemple concret : `map` avec drop-reuse

Voici pourquoi QTT compte pour l'efficacité. Une `map` sur une
liste :

    map f nil = nil
    map f (cons x xs) = cons (f x) (map f xs)

Chaque `cons` est un nœud alloué. Sur une liste de 1 million
d'éléments, ça fait 1 million de `cons` nouveaux — et 1 million
de `cons` anciens qui deviennent morts. **Sans QTT**, un GC doit
balayer tout ça.

**Avec QTT linéaire** (`1` sur `xs`) :

1. Le compilateur sait que chaque `xs` (la queue) est consommé
   exactement une fois — par le `map` récursif.
2. Quand `map` atteint un `cons x xs`, il *détruit* ce nœud
   (dernier usage) et *alloue* le nouveau `cons (f x) (...)`. Les
   deux ont la même taille.
3. **Perceus** détecte la paire `free + alloc` adjacente et la
   remplace par un `drop-reuse` : on écrit dans le nœud *existant*.

Résultat : `map` sur une liste linéaire ne fait **aucune
allocation nouvelle** en régime permanent. C'est l'optimisation
**FBIP** (Functional But In-Place). La liste de sortie occupe
exactement la même mémoire que la liste d'entrée — et seules
les valeurs `(f x)` ont été calculées.

C'est pour cela que QTT n'est pas un détail de typage : c'est
**le fondement d'un langage fonctionnel efficace sans GC**.

## Ce qu'on a appris

- Un **type** est une catégorie (Aristote) : une manière de
  classer les valeurs, pas une essence cachée.
- Heaven a **cinq types de base** : `Int`, `Float`, `String`,
  `Bool`, `Unit`.
- **Cible** : le langage infère les types (`inc x = x + 1` donne
  `Int -> Int`). **État réel** : `TypeEnv.infer` est un stub qui
  retourne `"Int"` pour tout. L'exemple fonctionne par convention,
  pas par inférence réelle.
- Les **types paramétrés** (`List a`, `Option a`, `Pair a b`)
  ont des places vides qu'on remplit plus tard.
- Frege distinguait **sens** (Sinn) et **référence**
  (Bedeutung) : deux expressions peuvent désigner la même chose
  par des chemins différents.
- Les **types dépendants** (`Vec n a`) portent une valeur dans
  leur structure.
- **QTT** ajoute une dimension : *combien de fois* une variable
  est utilisée (`0` effacé, `1` linéaire, `ω` libre). Heaven V0
  s'en inspire pour la mémoire (voir `docs/spec/_memory.md`) mais
  ne l'implémente pas encore.
- Un **jugement QTT** est un triplet `(contexte, terme, type)` où
  le contexte porte des multiplicités. Le vérificateur compare
  les usages aux déclarations.
- La **logique linéaire** de Girard donne le vocabulaire
  formel (`⊗`, `⊕`, `!`, `⊸`) qui sous-tend QTT.
- **Drop-reuse** (FBIP) : `map` sur une liste linéaire ne fait
  aucune allocation nouvelle — c'est la promesse concrète de
  QTT pour la performance.

Au chapitre suivant, on plonge dans le **pattern matching** :
comment écrire des fonctions qui prennent vraiment de la donnée
structurée, et comment la forme des arguments décide de leur
comportement.

*Vérifiable : tous les exemples `:type` et les constructions
montrées fonctionnent tels quels dans le REPL.*
