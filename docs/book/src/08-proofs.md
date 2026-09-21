# Chapitre 8 — Proofs and Theorems

> *« Prouver, c'est contraindre l'imagination à ne plus pouvoir
> douter. »*

Heaven n'est pas qu'un langage de programmation. C'est aussi un
**assistant de preuve**. On peut y écrire des théorèmes mathématiques,
et le noyau vérifie que les preuves sont correctes. Ce chapitre
introduit ce monde.

## Théorème et preuve

Un théorème est une affirmation. Par exemple :

    theorem add_zero : x + 0 = x

En français : « pour tout `x`, `x + 0` égale `x` ». La formulation est
naïve : `x` n'est pas quantifié explicitement. Heaven comprendra que
c'est pour tout `x` par défaut.

Une preuve, c'est la justification. On l'écrit avec `prove` :

    theorem add_zero : x + 0 = x
    prove add_zero by simplify
    ✓ [add_zero] proved (simplify)

`by simplify` demande à Heaven d'utiliser la tactique `simplify`. Elle
essaie de réduire les deux côtés jusqu'à ce qu'ils soient identiques.

## Les tactiques

`simplify` est une **tactique** : une recette pour prouver. Heaven en
a plusieurs.

**`eval`** : évalue une expression, vérifie qu'elle donne le résultat
attendu.

    theorem deux_plus_deux : 2 + 2 = 4
    prove deux_plus_deux by eval

**`simplify`** : simplifie les deux côtés et compare.

    theorem mul_one : x * 1 = x
    prove mul_one by simplify

**`induction`** : raisonne par récurrence.

    theorem add_comm : x + y = y + x
    prove add_comm by induction x

Pour `add_comm`, `simplify` ne suffit pas : il faut distinguer le cas
`x = zero` et le cas `x = succ n`. C'est ce que fait `induction`.

## Le noyau

Derrière les tactiques, il y a un **noyau** : un petit programme de
quelques centaines de lignes qui vérifie chaque étape. Si le noyau
accepte, la preuve est valide — indépendamment de la tactique
utilisée.

C'est crucial. Les tactiques peuvent être complexes, avoir des bugs,
ou même être malveillantes. Le noyau, lui, est simple et vérifiable.
Il n'utilise que des règles formelles, dérivées du **Calcul des
Constructions Inductives** (CIC).

Les règles sont :

- **Univers** : `Type(i) : Type(i+1)`. Il y a une hiérarchie de types
  pour éviter les paradoxes.
- **Produit dépendant** : `Π(x:A). B` est le type des fonctions qui
  prennent un `x : A` et rendent un `B` qui peut dépendre de `x`.
- **Abstraction** : `λx:A. t` est une fonction.
- **Application** : `f a` applique `f` à `a`.
- **Égalité** : `Eq(a, b)` est le type des preuves que `a` égale `b`.
- **Réflexivité** : `refl(a) : Eq(a, a)`.

Ces six règles suffisent à formaliser la quasi-totalité des
mathématiques.

## Types dépendants

Le mot « dépendant » signifie qu'un type peut dépendre d'une
**valeur**. Par exemple :

    Vecteur : Nat -> Type

`Vecteur 3` est le type des vecteurs de longueur exactement 3. On peut
écrire :

    head : (n : Nat) -> Vecteur (succ n) -> a

Cette signature dit : « `tete` prend un entier `n` et un vecteur de
longueur `n + 1`, et rend un élément ». Impossible d'appeler `tete` sur
un vecteur vide — le type l'interdit.

C'est une garantie qu'aucun test ne peut donner. Le type **est** la
preuve.

## Axiomes

Parfois on ne peut pas prouver. On **pose** :

    axiom tiers_exclu : forall (P : Prop). P ou non P

Un axiome est une affirmation qu'on accepte sans justification. Heaven
l'enregistre et l'utilise dans les preuves suivantes. À utiliser avec
parcimonie : chaque axiome est une faille dans la forteresse.

## Holes — le type-driven development

Un **trou** dans Heaven n'est pas un `undefined` ni un `TODO`. C'est
une **demande d'assistance au système**. On écrit :

    f x = ? + 1

et le système répond avec le **but** (`goal`) et le **contexte** :

    ? : Int
    -- x : Int

C'est le style **type-driven development**, popularisé par Idris et Agda.
Le principe :

1. Tu donnes la **structure** de ta fonction.
2. Le système te dit **ce qu'il attend** à cet endroit (le type).
3. Tu **raffines** progressivement — remplacer `?` par une expression,
   qui peut contenir d'autres `?`.
4. À la fin, tu as du code complet.

### L'état actuel

L'infrastructure est en place :

- `_` produit un nœud `Tag.hole` dans l'AST.
- Le vérificateur de types traite un trou comme une variable de type
  fraîche (`typer.zig`) : il **infère** ce que le trou doit être.
- Une substitution (`kanren_expr.zig`) permet de **lier** un trou à
  une valeur — c'est le mécanisme de raffinement.

    subst.bind(hole_idx, id)   -- raffine ?h en id
    subst.lookup(hole_idx)     -- retrouve ce qui a été assigné

### La commande `:hole`

Dans le REPL, `:hole` afficherait le but et le contexte :

    heaven> :hole ? + 3 = 10

Ceci **n'est pas encore implémenté**. La commande existe
(`cmdHole` dans `commands.zig`) mais affiche seulement l'usage. Une
vraie implémentation :

1. Résoudrait les équations arithmétiques simples (`? + 3 = 10` → `7`).
2. Afficherait le but et le contexte pour un trou typé.
3. Permettrait le raffinement interactif (`?h` → une expression).

    -- vision : non implémenté
    heaven> :hole ? + 3 = 10
    ? = 7

    -- vision : non implémenté
    heaven> f x = ?h
    ?h : Int
    -- x : Int

### Pourquoi c'est utile

En programmation classique, écrire du code quand on ne sait pas quoi
mettre ressemble à ça :

    f x = undefined  -- puis on revient plus tard
    f x = 0          -- puis on oublie
    f x = TODO       -- puis on oublie

En type-driven development, le trou **force** une conversation avec le
système. Tu ne peux pas avancer sans répondre à la question « quel est
le type de ce trou ? ». C'est contraignant, et ça produit du code plus
juste.

### Les trous dans le noyau de preuve

Dans une preuve, un trou est un **sous-but non prouvé**. Idris l'accepte
comme `?hole` et le signale ; Agda l'accepte et le marque `?`. Heaven
n'a pas encore cette intégration — le noyau voit un `hole` comme un
nœud qu'il ne sait pas réduire, ce qui l'empêche de conclure.

C'est un chantier pour plus tard : permettre au noyau de **poursuivre**
une preuve contenant des trous, en accumulant les sous-buts à résoudre.

## Un exemple complet

Prouvons que l'addition est associative. On a déjà `add` au bootstrap :

    add zero n = n
    add (succ n) m = succ (add n m)

Énonçons :

    theorem add_assoc : add (add x y) z = add x (add y z)

La preuve par induction sur `x` :

    prove add_assoc by induction x

Heaven déroule :

1. **Cas `x = zero`** : `add (add zero y) z = add zero (add y z)`.
   Simplifie à `add y z = add y z`. Réflexivité.
2. **Cas `x = succ n`** : suppose que c'est vrai pour `n`, prouve pour
   `succ n`. Utilise l'hypothèse d'induction.

Le noyau vérifie chaque étape. Si tout est bon :

    ✓ [add_assoc] proved (induction x)

## Limites

Il faut être honnête : le noyau de Heaven est un CIC **simplifié**. Il
ne supporte pas encore :

- les **types quotients** (pour quotienter par une relation)
- l'**unicité des preuves** (proof irrelevance)
- les **univers multiples** avec arithmétique complète (la règle `Π`
  est en cours de correction)

C'est suffisant pour l'arithmétique de Peano et beaucoup de
mathématiques de base. Pour les preuves très avancées, il faudra
étendre.

## Récapitulatif

- Un **théorème** est une affirmation, une **preuve** la justifie.
- Les **tactiques** (`simplify`, `eval`, `induction`) construisent la
  preuve.
- Le **noyau** vérifie chaque étape avec des règles formelles.
- Les **types dépendants** permettent d'exprimer des propriétés très
  précises.
- Les **axiomes** sont des affirmations acceptées sans preuve.
- Les **trous** sont des questions posées au système (TDD, voir ci-dessus).

Au chapitre suivant, on quitte les mathématiques pour le monde réel :
fichiers, réseau, acteurs.
