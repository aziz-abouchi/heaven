# Effets algébriques

> *« Le code pur calcule. Le code impur agit. Un bon langage sépare
> les deux sans les rendre incompatibles. »*

Jusqu'ici, tout notre code était **pur**. `inc`, `map`, `filter` :
ils prennent des valeurs, rendent des valeurs, et ne font rien
d'autre. Pas de lecture de fichier, pas de log, pas de requête réseau.

Mais les programmes réels doivent *faire* des choses. Comment
concilier pureté et action ? La réponse de Heaven s'appelle les
**effets algébriques**.

## 1. Le problème : pureté et action

![Deux mondes : pur et impur](images/06-purity-vs-effect.svg)

Il y a une tension ancienne entre deux exigences :

- **Calculer** proprement — une fonction pure rend toujours le même
  résultat pour la même entrée. On peut la tester, la reproduire,
  la prouver.
- **Agir** sur le monde — lire un fichier, envoyer un message,
  afficher un résultat.

Dans la plupart des langages, ces deux mondes se mélangent. Une
fonction Python peut `print` un log au milieu d'un calcul :

    def process(x):
        print(f"pipeline de {x}")
        return x * 2

Cette fonction est *impure* : elle écrit sur la sortie standard. On
ne peut pas la tester sans capturer stdout. On ne peut pas la
paralléliser sans mélanger les logs. On ne peut pas la transformer
en appel réseau sans tout réécrire.

Le philosophe du langage John Austin (1911-1960) avait fait une
distinction voisine dans *How to Do Things with Words* (1955) : les
énoncés ne se contentent pas de **décrire** le monde — ils
**agissent** sur lui. Quand un maire dit « je vous déclare mari et
femme », ce n'est pas une description de mariage, c'est l'acte de
mariage lui-même. Un **performatif**.

Le `print` de Python est un performatif : il ne décrit pas qu'un
log est écrit, il l'écrit.

## 2. Séparer l'intention de l'action

En Heaven, on sépare l'**intention** de l'**exécution**. Voici le
même calcul, mais sans effet :

    process x = x * 2

Et voici la version avec l'**intention** de logger :

    process x =
      let _ = (perform "Log" x) in
      (* x 2)

`perform "Log" x` dit : « je veux logger `x` ». Pas *comment*. C'est
un signal, pas une action. Le code reste pur tant que personne
n'intercepte. Si on écrit `process 5` sans handler, le signal est
émis mais rien ne se passe de particulier — il attend.

## 3. `perform` : émettre un signal

`perform` s'écrit en préfixe (notation de Frege, chapitre 1) :

    perform "Log" 42

Le premier argument est le **nom** de l'effet (`"Log"`). Le second
est la **charge utile** (42). Le résultat de `perform` est une
**valeur** de type `Unit` — la même chose que `()` du chapitre 2.
C'est-à-dire « rien de spécial à signaler ».

En fait, `perform` *fait* quelque chose : il **émet un signal** que
l'environnement peut intercepter. Mais du point de vue du calcul, il
ne rend rien de particulier.

## 4. `handle` : intercepter

![Le signal et le handler](images/06-handler.svg)

Pour donner un sens au signal, on utilise `handle`. Il prend deux
arguments : une expression contenant des `perform`, et un **handler**
qui sait quoi faire de ces signaux.

    heaven> logHandler msg = (+ msg 100)
    ✓ clause enregistrée pour 'logHandler'

    heaven> handle (perform "Log" 42) logHandler
    142

Déroulons :

1. `perform "Log" 42` émet un signal avec la valeur 42.
2. `handle ... logHandler` intercepte le signal.
3. Il appelle `logHandler 42`, qui rend 142.
4. `handle` rend ce résultat.

Le handler est une **fonction ordinaire**. Il prend la charge utile
(42) et rend ce qu'il veut (142). C'est aussi simple que ça.

*Vérifiable : `logHandler` et `handle (perform "Log" 42)
logHandler` fonctionnent tels quels dans le REPL.*


## 5. L'effet comme valeur

![L'effet est une valeur qu'on manipule](images/06-effect-as-value.svg)

Voici l'idée centrale des effets algébriques : un signal est une
**valeur** comme une autre. On peut le passer, le retourner, le
stocker. Ce n'est pas un mécanisme spécial du langage, c'est un
objet ordinaire.

Regardons ce que ça permet. Voici un programme qui émet un signal :

    process x =
      let _ = (perform "Log" x) in
      (* x 2)

Ce programme est **pur**. Il ne fait rien quand on l'évalue seul. Il
se contente d'**émettre une intention** que quelqu'un pourra
intercepter.

On peut l'interpréter de plusieurs manières différentes :

**Handler 1 — logguer vers la sortie standard** :

    logStdout msg = msg
    resultat = handle (process 5) logStdout

**Handler 2 — logguer vers un fichier** :

    logFile msg = msg
    resultat = handle (process 5) logFile

**Handler 3 — ignorer les logs** :

    logIgnore msg = msg
    resultat = handle (process 5) logIgnore

Le **même programme** `process`, trois interprétations différentes.
C'est exactement ce que nous cherchions : le code reste pur, on peut
le tester sans effet, et chaque usage décide de la sémantique.

C'est une idée que la philosophie du langage a explorée :
*un texte peut être lu de plusieurs manières sans changer*. Le
programme est le texte. Les handlers sont les lectures.

## 6. Comparaison avec les monades

Depuis les années 1990, la manière habituelle de gérer les effets
en Haskell s'appelle les **monades**. Une monade `IO` encapsule les
effets d'entrée-sortie ; une monade `State` encapsule un état
mutable ; une monade `Either` encapsule les erreurs.

Eugenio Moggi (1989) et Philip Wadler (1992) ont montré que
**beaucoup** de ces structures partageaient les mêmes lois. Une
monade, c'est :

- Un type paramétré `M a` (comme `Option a` ou `List a`).
- Une fonction `return : a -> M a`.
- Une fonction `bind : M a -> (a -> M b) -> M b`.
- Trois lois : identité à gauche, identité à droite, associativité.

Les **effets algébriques** généralisent les monades. Au lieu d'avoir
une monade par type d'effet, on a :

- Une seule syntaxe `perform` pour émettre n'importe quel signal.
- Une seule syntaxe `handle` pour intercepter n'importe quel signal.

Un effet algébrique ressemble à une monade libre : on empile les
signaux, on les interprète plus tard. La différence est dans le
*dispatch* : les monades se composent à la main (`M1 (M2 a)`), les
effets se composent automatiquement (le handler choisit ce qu'il
attrape).

C'est pourquoi Heaven, et d'autres langages modernes (Koka, Eff,
Unison), préfèrent les effets aux monades : *moins de code pour la
même puissance expressive*.

## 7. Pourquoi c'est puissant

Trois raisons.

**1. Testabilité.** Un programme qui émet des signaux peut être
testé sans effet de bord. On écrit un handler qui collecte les
signaux au lieu de les exécuter, et on vérifie que la liste est
correcte.

    logCollector msg = msg
    -- En test, on "collecte" au lieu de logger.

**2. Modularité.** Le programme ne sait pas *comment* on va
l'exécuter. Le handler décide. On peut changer de handler sans
toucher au programme. C'est la séparation des préoccupations poussée
à son terme.

**3. Composition.** Deux effets (Log et Error, par exemple) se
composent avec deux handlers imbriqués :

    handle
      (handle programme logHandler)
      errorHandler

Le handler interne attrape les logs, le handler externe attrape les
erreurs. Chacun fait son travail sans interférer avec l'autre.

C'est ce que John Austin appelait la **force illocutoire** : un
même énoncé peut avoir différentes forces selon le contexte. « Il
pleut » peut être une description, une plainte, une réponse à une
question. En Heaven, le même `perform` peut être un log, une
écriture, ou une requête — c'est le handler qui décide.

## Ce qu'on a appris

- Il y a une tension entre **calculer** (pur) et **agir** (impur).
- John Austin, dans *How to Do Things with Words* (1955), a montré
  que le langage ne décrit pas seulement le monde — il agit sur lui.
- Un **`perform`** émet un signal, sans l'exécuter.
- Un **`handle`** intercepte les signaux et leur donne un sens.
- Les effets sont des **valeurs** ordinaires : on peut les passer,
  les intercepter, les ignorer.
- Le **même programme** peut être interprété de plusieurs manières
  selon le handler choisi.
- Les **effets algébriques** généralisent les **monades** de Moggi
  et Wadler (1989-1992), avec moins de code pour la même puissance.

Wittgenstein aurait vu dans les effets une illustration de son
« voir comme » : le même programme, deux lectures. Composer des
handlers, c'est voir le programme **comme** un pipeline de
transformations successives.

Au chapitre suivant, on explore une application des effets :
les **streams**. Une liste paresseuse où les effets jouent un rôle
central — on peut lire, écrire, ou transformer, sans matérialiser
toute la séquence.

*Vérifiable : tous les exemples `handle` et `logHandler` de ce
chapitre fonctionnent tels quels dans le REPL.*

