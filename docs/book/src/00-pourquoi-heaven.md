# Pourquoi Heaven ?

> *« Ce qui se conçoit bien s'énonce clairement, et les mots pour
> le dire arrivent aisément. »*
> — Nicolas Boileau, *Art poétique* (1674)
>
> *Nuance : la clarté rend les preuves possibles, mais elle n'est
> pas une preuve en soi. Ce livre s'en sert comme boussole, pas
> comme garantie.*

Ce chapitre ne contient pas de code. Il s'adresse à ceux qui
ouvrent ce livre sans être programmeurs — philosophes, littéraires,
linguistes, curieux — et qui veulent comprendre *pourquoi* Heaven
existe avant de voir *comment* il fonctionne.

Si tu es déjà développeur, tu peux sauter directement au chapitre 1.
Reviens ici si tu te demandes un jour « mais pourquoi tout ça ? ».

## Une question ancienne

Quand tu poses 3 + 4 sur une feuille de papier, que fais-tu ?

Tu ne **penses** pas à quelque chose. Tu **suis une règle**. Une
règle que tu as apprise enfant, qui dit : « pour additionner deux
nombres, écris-les côte à côte et applique la table d'addition. »
Tu regardes. Tu ne philosophes pas. Tu appliques.

C'est ce que Ludwig Wittgenstein appelait un **jeu de langage** :
une activité humaine régie par des règles, où le sens des mots se
montre dans l'usage qu'on en fait — pas dans une définition
préalable. Sa phrase la plus célèbre, dans les *Investigations
philosophiques* (§43) : *« La signification d'un mot, c'est son
usage dans le langage. »*

Dans un langage formel comme Heaven, cette idée se précise : le
sens se voit dans ce qu'on peut faire d'une expression — mais
les règles de ce « faire » sont mathématiquement définies, pas
laissées à l'usage social.

Heaven est un jeu de langage. C'est un ensemble de règles pour
décrire des calculs, des raisonnements, des communications. Ces
règles ne sont pas arbitraires — elles ont été choisies pour
permettre quelque chose que les autres jeux de langage ne
permettent pas : **prouver qu'un programme fait ce qu'il prétend
faire**.

## Le problème : opinion vraie et savoir

Platon, dans le *Ménon*, pose une question restée célèbre : quelle
est la différence entre une **opinion vraie** et un **savoir** ?

Son exemple : un esclave, sans éducation, peut répondre
correctement à une question de géométrie. Il a une opinion vraie.
Mais peut-il la **justifier** ? Non. Il ne sait pas *pourquoi* sa
réponse est correcte. Il a une croyance vraie, pas une connaissance.

Un programme qui passe tous ses tests ressemble à l'esclave du
*Ménon*. Il **marche**. Il fait ce qu'il fait. Mais peut-on
*prouver* qu'il fait toujours ce qu'il prétend ? C'est une autre
question.

Heaven essaie de répondre à cette question. Il permet d'écrire
des programmes qu'on peut non seulement **exécuter**, mais
**prouver** corrects. Ce n'est pas un slogan marketing — c'est un
noyau mathématique qui vérifie chaque affirmation.

Heaven réunit dans le **même langage** deux gestes habituellement
séparés : *programmer pour exécuter*, et *démontrer pour garantir*.
Les preuves y sont des programmes comme les autres.

## Trois idées fondatrices

### 1. La vérité mathématique comme source unique

Un langage moderne contient beaucoup de mécanismes : types,
effets, concurrence, entrées-sorties. Chacun peut être implémenté
de plusieurs façons. Heaven prend un parti : le **noyau
mathématique** (un système formel appelé *Calcul des Constructions
Inductives*) fournit le **cadre rigoureux** dans lequel toutes
les preuves sont vérifiées. Tout le reste — les
types, les fonctions, les listes, les protocoles de communication —
n'est que du **sucre** posé au-dessus, qui disparaît à l'exécution.

C'est une idée ancienne : dans *Les Mots et les Choses*, Michel
Foucault montre comment les classifications savantes reposent sur
un petit nombre de distinctions fondatrices. Heaven fait pareil :
six primitives, pas une de plus. Le reste se dérive.

Ces six primitives sont : `lit` (un littéral), `sym` (un nom),
`apply` (une application), `bind` (une liaison), `lambda` (une
abstraction), `relation` (une égalité). Toute autre construction
se désucre vers ces six formes avant évaluation.

### 2. L'esthétique comme critère

Il y a un théorème célèbre en mathématiques (le « lemme de
Yoneda ») qui dit, en substance : *un objet est entièrement
déterminé par la manière dont les autres le voient*. Heaven prend
cette idée au sérieux. Un programme court, lisible, élégant est
*probablement* plus correct qu'un programme long et tortueux —
parce que la simplicité rend la vérification plus facile.

D'où une devise du projet : *« un théorème en trois lignes vaut
mieux qu'un théorème en trente »*. Ce n'est pas une coquetterie.
C'est une heuristique : un énoncé court et clair est plus facile
à vérifier, donc plus sûr, qu'une formulation compliquée. La
brièveté n'est pas un critère de vérité — un énoncé court peut
être faux, un énoncé long peut être correct.

### 3. La construction à partir du minimum

La logique repose sur quelques règles d'inférence (modus ponens,
etc.). La linguistique générative postule une structure profonde
sous la diversité des langues. Heaven suit la même intuition :
**six primitives** suffisent à tout construire. Tout le reste —
boucles, conditions, fonctions d'ordre supérieur, preuves, effets
concurrents — est une manière plus lisible de dire ces six
primitives. Nous verrons dans les chapitres suivants comment ces
constructions familières se définissent à partir du noyau minimal.

Cela a une conséquence pratique importante. Quand quelque chose ne
fonctionne pas dans Heaven, on ne cherche pas dans une pile de
mécanismes exotiques. On redescend à six primitives, on voit où ça
coince, et on remonte. C'est une méthode de diagnostic, mais aussi
une méthode philosophique : *comprendre, c'est savoir décomposer*.

## Ce que Heaven n'est pas

- **Ce n'est pas un langage pour remplacer Python ou JavaScript.**
  Il est expérimental, jeune, rugueux par endroits.
- **Ce n'est pas un assistant de preuve pur** comme Coq ou Agda.
  Le noyau est le même (Calcul des Constructions Inductives), mais
  là où Coq sépare le mode *calcul* du mode *preuve*, Heaven
  utilise la même syntaxe et les mêmes concepts pour les deux.
  C'est un *langage de programmation*, pas un outil réservé aux
  mathématiciens.
- **Ce n'est pas fini.** Beaucoup de choses manquent. Le livre le
  dit honnêtement à chaque fois.

## Comment lire ce livre

Trois manières :

**Si tu es développeur** — tu peux sauter ce chapitre et le
glossaire ci-dessous. Commence au chapitre 1.

**Si tu n'es pas développeur** — lis ce chapitre, puis le
glossaire. Ensuite, aborde le chapitre 1 sans crainte : les
exemples sont expliqués comme des phrases, pas comme du code.

**Si tu veux juste voir Heaven en action** — essaie le REPL web
à `https://aziz-abouchi.github.io/heaven/repl`. Tape
`(+ 1 2)`, regarde ce qui se passe, puis reviens lire le
chapitre 1.

## Glossaire pour non-initiés

Avant d'entrer dans le vif, voici les mots que tu rencontreras. Tu
n'as pas besoin de les retenir — reviens ici quand l'un d'eux te
bloque.

**REPL** — *Read-Eval-Print Loop*. Un environnement interactif où
l'on tape du code ligne par ligne et où l'on voit immédiatement le
résultat. Comme une calculatrice, mais pour un langage entier.
Ce livre en utilise un constamment : les lignes qui commencent par
`heaven>` sont tapées dans un REPL.

**Fonction** — Un bloc de code qui prend des entrées (appelées
*arguments* ou *paramètres*) et produit une sortie. `inc x = x + 1`
est une fonction qui ajoute 1 à son argument.

**Type** — Une étiquette qui dit *ce qu'est* une valeur. `42` est de
type `Int` (entier), `"bonjour"` est de type `String` (chaîne de
caractères). Les types servent à vérifier que le code a du sens.

**Récursion** — Quand une fonction s'appelle elle-même. C'est la
manière fonctionnelle de faire des boucles. Exemple : « factorielle
de n = n × factorielle de (n−1), sauf si n = 0 ».

**Pattern matching** — Une manière de décrire le comportement d'une
fonction en distinguant plusieurs *formes* de ses arguments. Un peu
comme dire « si c'est un chat, fais ceci ; si c'est un chien, fais
cela ».

**AST** — *Abstract Syntax Tree*. La structure d'une expression,
représentée comme un arbre. L'expression `1 + 2` devient un nœud
`+` avec deux enfants, `1` et `2`. C'est la manière dont
l'ordinateur « comprend » ce que tu as écrit.

**Théorème** — Une affirmation qu'on essaie de *prouver* à partir
d'axiomes et de règles. Dans Heaven, un théorème n'est pas juste
une note pour soi — le langage vérifie la preuve.

**Effet (algébrique)** — Une manière de décrire ce qu'un programme
*veut faire* (écrire dans un fichier, envoyer un message) sans le
faire tout de suite. C'est une séparation entre l'intention et
l'action.

**Monade** — Un mot qui fait peur mais qui désigne une idée simple :
une manière de chaîner des opérations qui ont un « contexte »
(comme l'absence possible de valeur, ou la possibilité d'échouer).

**Concurrence** — Quand plusieurs tâches avancent en même temps.
Pas forcément en parallèle (sur plusieurs processeurs) — parfois
juste en alternance, comme un serveur qui répond à plusieurs
clients.

**CIC** — *Calcul des Constructions Inductives*. Le système formel
qui sert de noyau mathématique à Heaven. C'est lui qui garantit
qu'une preuve est correcte.

**QTT** — *Quantitative Type Theory*. Un système de types qui suit
*combien de fois* une variable est utilisée. Utile pour la gestion
mémoire et la programmation linéaire. C'est une **inspiration**
pour Heaven : le suivi des ressources est en étude pour une
intégration future dans le noyau (voir `docs/spec/_memory.md`).

**HKT** — *Higher-Kinded Types*. Des types qui paramètrent d'autres
types. « Liste de X » où X est lui-même un type.

**IR** — *Intermediate Representation*. Une forme intermédiaire
entre le code source et le code machine.

**E-graph** — *Equivalence graph*. Une structure de données qui
stocke plusieurs formes équivalentes d'une même expression.

**MPST** — *Multiparty Session Types*. Un cadre théorique qui
décrit les protocoles de communication entre plusieurs acteurs.
Il **guide la conception** des fonctionnalités de communication
et de concurrence de Heaven ; l'implémentation reste partielle.

**WASM** — *WebAssembly*. Un format de code compilé, exécutable
dans un navigateur web.

**Vessel** — Ancien serveur web de Heaven (REPL web, IDE,
monitoring), écrit en Zig. Vestige en cours de remplacement par
l'environnement HTTP écrit 100 % en Heaven (`core/http.hvn`).

## À toi de jouer

Si ces idées t'intéressent, le chapitre 1 commence par les bases.
Tu peux lire la suite sans coder — les exemples sont faits pour
être lus autant que tapés. Et si un mot te bloque, reviens au
glossaire ci-dessus.
