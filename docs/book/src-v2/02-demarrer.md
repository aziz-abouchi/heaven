# Chapitre 2 — Démarrer : la première conversation

> **Version 2 (2026-11-04)** — rédaction from scratch (v1 = stub 24 l.).
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Le commencement est la moitié de tout. »*
> — Pythagore

Un langage, c'est d'abord un endroit où parler. Avant les types, avant
les preuves, avant la théorie des catégories, il y a cette chose
simple : tu écris quelque chose, le langage répond. Ce chapitre est
consacré à cette conversation initiale.

On va installer Heaven, écrire trois lignes, voir un résultat. Pas de
théorie. Le reste du livre viendra ensuite.

## 1. Installer

Heaven n'est pas encore dans les dépôts de ta distribution. On le
compile. Trois commandes, dix minutes.

    git clone https://github.com/aziz-abouchi/heaven
    cd heaven
    bash build.sh

À la fin, un binaire nommé `heaven` se trouve dans `./zig-out/bin/`.
Il n'est **pas** dans le `PATH` — c'est volontaire. Un langage
expérimental ne doit pas s'installer par-dessus ton système. On
l'appelle par son chemin complet.

    ./zig-out/bin/heaven

Si tu vois un message d'usage, tout va bien. L'installation est
terminée. On passe à la suite.

## 2. Premier programme

Crée un fichier `hello.hvn` :

    1 + 2

Puis lance-le :

    ./zig-out/bin/heaven run hello.hvn

    → 3

Trois choses à noter :

1. L'expression s'écrit **en infixe** : `1 + 2`, pas `(+ 1 2)`.
   Les deux formes marchent — mais l'infixe est la forme par défaut.
2. Pas de `print`, pas de `main`. Le fichier entier est une expression.
   Heaven l'évalue et affiche le résultat. C'est le mode « script ».
3. Le résultat s'affiche après une flèche informelle — c'est un
   commentaire du livre, pas une sortie littérale. Heaven affiche
   `3` tout court.

## 3. Une fonction

Le fichier suivant, `double.hvn` :

    double x = x * 2
    double 5

Lance-le :

    ./zig-out/bin/heaven run double.hvn

    → 10

La première ligne **définit** une fonction. La seconde l'**appelle**.
La définition persiste pour toute la suite du fichier — c'est un
`let` implicite à chaque ligne.

Une fonction Heaven n'a pas de `return`. Elle est une **égalité** :
« `double x` vaut `x * 2` ». C'est une équation, pas un ordre. Si tu
as déjà vu des maths, tu es en terrain connu.

## 4. L'erreur comme cadeau

Essaie maintenant :

    double "bonjour"

    → erreur

Le message exact dépend de la version, mais l'idée est là : Heaven
refuse. Pas parce qu'il est méchant — parce qu'il **sait**. Il a
compris que `double` attend un nombre, et que `"bonjour"` n'en est
pas un.

Compare avec un langage qui laisserait passer :

    # Python, pour comparaison
    "bonjour" * 2

    → "bonjourbonjour"

Python a raison dans son modèle (multiplication de chaînes), mais il
n'a **pas** refusé. Heaven refuse parce que ses types sont stricts.
C'est contraignant au début, **libérateur** ensuite : tu passes moins
de temps à déboguer des choses qui n'auraient jamais dû arriver.

## 5. Le REPL interactif

Pour les explorations rapides, Heaven a un REPL. Lance-le :

    ./zig-out/bin/heaven repl

Après quelques messages d'initialisation, un prompt apparaît. Tu peux
taper :

    double x = x * 2
    double 5
    double 100

et voir chaque résultat immédiatement. La définition de `double`
persiste entre les lignes — l'environnement se souvient.

**Attention** : le REPL nécessite un terminal interactif (TTY). Si tu
lances `heaven repl` depuis un pipe ou un script, il bascule
silencieusement en mode serveur et n'affiche pas de prompt. C'est un
piège classique — on y revient plus bas.

## Piège — `heaven repl` en pipe ne marche pas

Tu voudras peut-être automatiser :

    printf '(+ 1 2)\n' | ./zig-out/bin/heaven repl

Et tu ne verras **rien** — ou plutôt, tu verras les messages
d'initialisation, puis :

    [CORE] Mode serveur (REPL desactive: HEAVEN_NO_REPL=1 ou stdin non-TTY).

Le REPL s'est **désactivé** parce que `stdin` n'est pas un terminal.
C'est une sécurité : il ne faut pas qu'un script s'embrouille à
attendre un prompt qui ne viendra jamais.

**Ce qu'il faut faire** :

- **Pour un test rapide** : mets l'expression dans un fichier et
  utilise `heaven run file.hvn`. C'est **toujours** déterministe.
- **Pour l'interactif** : ouvre un vrai terminal (`gnome-terminal`,
  `kitty`, `tmux`, peu importe), tape `heaven repl` à la main.
- **Pour un script** : n'utilise pas `repl`. Utilise `run`.

**Autre piège de la même famille** : `heaven eval '(+ 1 2)'`
n'existe **pas**. `eval` est interprété comme un nom de port. Le
binaire affiche l'usage ou démarre en mode bizarre. Si tu veux
évaluer une expression unique, mets-la dans un fichier et `run`.

**Règle** : `heaven run FILE.hvn` est ton ami. Le reste (`repl`) est
pour l'exploration manuelle.

## Sous le capot — que fait `heaven run` ?

Quand tu lances `heaven run hello.hvn`, trois choses se passent dans
cet ordre :

1. **Lecture** : le fichier est lu, analysé (lexer + parser), et
   transformé en une séquence de définitions / expressions.
2. **Évaluation** : les définitions sont ajoutées à un
   **environnement persistant** (une `Env` en mémoire), puis les
   expressions sont évaluées dans cet environnement.
3. **Affichage** : la **dernière** expression évaluée est imprimée.
   Les précédentes sont silencieuses (sauf si tu utilises `print`).

Ce qui compte pour toi :

- **Pas de recompilation** entre les lignes. Un fichier `.hvn` est
  interprété, pas compilé. (Il existe un `compile-qbe` pour le
  compilateur natif — voir plus tard.)
- **Pas de `main`**. Le fichier entier est le programme. La dernière
  expression est le résultat.
- **L'environnement est frais** à chaque `heaven run`. Deux exécutions
  du même fichier donnent le même résultat, toujours.

Le REPL fait la même chose, mais **boucle** : lit, évalue, affiche,
recommence — avec le **même** environnement entre les tours. C'est
pour ça que `double` persiste après sa définition : l'environnement
n'est pas jeté.

## Exercices

1. **Le classique.** Écris un fichier `carre.hvn` qui définit `carre x`
   (le carré d'un nombre) puis calcule `carre 7`. Vérifie que le
   résultat est `49`.

2. **Deux définitions.** Écris un fichier qui définit `double` puis
   `quadruple` **en utilisant `double`** (pas de multiplication
   directe). Calcule `quadruple 3`. Vérifie que c'est `12`.

3. **Casser exprès.** Écris `double "bonjour"` dans un fichier.
   Lance `heaven run`. Note le message d'erreur exact. Puis essaie
   `double true`. Le message est-il le même ? Pourquoi ?

4. **Le piège.** Lance `printf '1 + 2\n' | ./zig-out/bin/heaven repl`
   dans ton terminal. Que vois-tu ? Pourquoi ? Comment corriger ?
   *Indice* : `isatty` de `stdin`, ou le message `[CORE] Mode serveur`
   qui apparaît. Propose deux corrections (une avec `run`, une avec
   un vrai terminal).

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.

## À toi de jouer

Tu sais maintenant :

- installer Heaven ;
- écrire un fichier `.hvn` et l'évaluer avec `heaven run` ;
- définir une fonction ;
- comprendre (et éviter) le piège du REPL en pipe.

Le chapitre suivant plonge dans les **types**. Pourquoi `double`
accepte `5` mais pas `"bonjour"` ? Qu'est-ce qui distingue un nombre
d'une chaîne, au-delà du symbole ? Et comment Heaven le **sait** ?

Tu n'as pas besoin du REPL pour suivre. Un éditeur, un terminal, et
`heaven run` — c'est tout ce qu'il faut.
