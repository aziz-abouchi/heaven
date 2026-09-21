# Annexe C — Glossaire

Les termes techniques utilisés dans ce tutoriel, avec leur définition.

## A

**Acteur** — Modèle de concurrence où des objets isolés communiquent
par messages. Un acteur a un état et un handler. Voir le chapitre 9.

**Application partielle** — Appeler une fonction avec moins
d'arguments que prévu. Rend une fonction qui attend les arguments
restants. Voir la curryfication.

**Arbitraire (choix)** — Décision prise par le programmeur sans
justification formelle. Un axiome est un choix arbitraire.

**Assertion** — Affirmation qu'on demande à Heaven de vérifier.
`assert_eq` et `assert_err` sont des assertions.

**Axiome** — Affirmation acceptée sans preuve. Voir le chapitre 8.

## C

**CIC** — Calcul des Constructions Inductives. Le formalisme
mathématique sous-jacent au noyau de preuve de Heaven.

**Clause** — Une équation dans la définition d'une fonction. Une
fonction peut avoir plusieurs clauses, essayées dans l'ordre.

**Composition** — Combiner deux fonctions en une seule. L'opérateur
`>>>` fait ça.

**Constructeur** — Une des formes d'un type de données. Par exemple,
`Zero` et `Succ` sont les constructeurs de `Nat`.

**Curryfication** — Transformation d'une fonction à N arguments en
une chaîne de fonctions à 1 argument. Permet l'application partielle.

## D

**Déclaratif** — Style où on décrit *ce que* quelque chose est, pas
*comment* le calculer. Heaven est déclaratif.

**Dispatch** — Sélection de la bonne action en fonction d'un critère.
L'évaluateur dispatche sur l'opérateur d'un `apply`.

## E

**Effet algébrique** — Mécanisme pour signaler une action sans
l'exécuter. `perform` émet, `handle` intercepte. Voir le chapitre 6.

**Environnement** — Ensemble des liaisons de symboles à valeurs. Voir
`Env` dans le code.

**Expression** — Une construction qui a une valeur. Tout en Heaven
est expression (il n'y a pas de distinction expression / instruction).

## H

**Handler** — Fonction qui intercepte un effet. Voir le chapitre 6.

**Hash-consing** — Technique d'optimisation où deux expressions
identiques partagent le même `Id`. Utilisé dans le Store.

**Hole** — Un trou dans une expression, marqué par `_` ou `?`. N'est
pas un placeholder passif : c'est une **demande d'assistance au
système**, qui répond avec le but et le contexte. Voir type-driven
development, chapitre 8.

## I

**Id** — Entier qui identifie une expression dans le Store.

**Induction** — Preuve par récurrence. Tactique `induction` dans le
noyau.

**Inférence de types** — Déduction automatique du type d'une
expression, sans annotation.

**Interner** — Table de chaînes uniques. Chaque nom n'existe qu'une
fois en mémoire.

## K

**Kernel** — Noyau de preuve. Programme minimal qui vérifie les
théorèmes. Voir le chapitre 10.

## L

**Lambda** — Fonction anonyme. `\x -> x + 1` est une lambda.

**Lowering** — Transformation d'une forme de haut niveau en formes
primitives. `+` est lowered en `apply`.

## M

**Map** — Fonction d'ordre supérieur qui applique une fonction à
chaque élément d'une liste.

**Monade** — Structure mathématique utilisée pour modéliser les
effets en Haskell. Heaven utilise plutôt les effets algébriques.

## N

**Nat** — Type des entiers naturels de Peano. `Zero` ou `Succ n`.

**Noyau** — Voir Kernel.

## O

**Ordre supérieur (fonction d')** — Fonction qui prend une fonction
en argument ou rend une fonction.

## P

**Pattern matching** — Filtrage par motif. Sélection d'une clause en
fonction de la forme des arguments.

**Paresseux (évaluation)** — Évaluation à la demande, seulement
quand on a besoin du résultat.

**Peano** — Système d'axiomes pour les entiers naturels. Utilisé par
`Nat`.

**Pipeline** — Chaîne de transformations. Voir le chapitre 7.

**Pool** — Tableau d'arguments dans le Store. Les `Id` y sont stockés
pour les `apply`.

**Primitive** — Une des six formes de base : `lit`, `sym`, `apply`,
`bind`, `lambda`, `relation`.

**Prouver** — Vérifier qu'un théorème est vrai. Voir le chapitre 8.

## R

**Récursion** — Fonction qui s'appelle elle-même. Voir le chapitre 4.

**Récursion terminale** — Récursion où l'appel est la dernière
instruction. Économise la pile.

**Réflexivité** — Propriété d'être égal à soi-même. `refl(a) : Eq(a, a)`.

## S

**Signature** — Déclaration explicite du type d'une fonction.

**Simplification** — Réduction d'une expression à une forme plus
simple.

**Snapshot** — Copie d'une slice pour éviter les dangling pointers.

**Span** — Plage d'indices dans un tableau. Utilisée pour les
arguments.

**Store** — Tableau de nœuds d'expressions.

**Stream** — Liste paresseuse. Voir le chapitre 7.

**Sym** — Symbole interné. Représente un nom.

## T

**Tactique** — Procédure de preuve. `simplify`, `induction`, `eval`.

**Théorème** — Affirmation mathématique à prouver.

**Trou** — Voir Hole. Dans le contexte du développement, un trou est
une question posée au vérificateur de types, qui répond avec le but
attendu.

**Type** — Ensemble de valeurs. `Int`, `String`, `Bool`, etc.

**Type dépendant** — Type qui dépend d'une valeur. `Vecteur n`.

## U

**Unité** — Voir `Unit`. Type à une seule valeur `()`.

**Univers** — Hiérarchie de types. `Type(0) : Type(1) : Type(2) : ...`.

## V

**Vessel** — Serveur HTTP embarqué dans Heaven.
