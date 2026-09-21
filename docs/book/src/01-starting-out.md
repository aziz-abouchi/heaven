# Chapitre 1 — Starting Out

> *« Un langage où l'on peut prouver ce qu'on affirme ne devrait pas
> être ennuyeux. »*

Bienvenue dans Heaven. Si tu viens de Python, JavaScript, C ou Java,
ce tutoriel est fait pour toi. Si tu viens de Haskell ou d'Idris, tu
peux survoler les deux premiers chapitres — mais reste pour les effets
algébriques et les théorèmes.

## Pourquoi un nouveau langage ?

Il y a beaucoup de langages. Pourquoi en ajouter un ? Parce que Heaven
essaie de faire tenir ensemble trois choses qui, d'habitude, ne se
parlent pas :

1. **La légèreté d'un REPL** — tu tapes, tu vois, tu ajustes.
2. **La rigueur d'un assistant de preuve** — quand tu affirmes quelque
   chose, le noyau peut le vérifier.
3. **La réactivité des systèmes modernes** — acteurs, streams, effets
   algébriques, sans framework.

Ces trois mondes existent séparément. Heaven essaie de les coudre
ensemble.

## Le REPL

Ouvre un terminal, tape :

    $ heaven repl
    Noyau opérationnel sur le port 0
    Noyau Expr (6 primitives) initialisé
    Système prêt. Entrée dans le Shell.
    heaven>

Tu es dans le REPL. C'est ton laboratoire. Tout ce qu'on fera dans ce
tutoriel, tu peux le refaire ici.

## Les expressions

Commence simple :

    heaven> 2 + 3
    5
    heaven> 2 * 3 + 1
    7
    heaven> 10 / 2
    5

La précédence marche comme tu l'attends : `*` lie plus fort que `+`.

**Pour les habitués de Lisp** : tu peux aussi écrire en S-expression.

    heaven> (+ 1 2)
    3

Heaven accepte les deux styles. On utilisera l'infixe dans la suite.

## Premiers noms

Donnons un nom à un calcul :

    heaven> double x = x * 2
    ✓ clause enregistrée pour 'double'
    heaven> double 21
    42

Note deux choses :

1. **`double` est une fonction**. Pas une lambda, pas un objet, pas une
   closure. Une **clause** — une équation qui dit ce que `double` vaut
   pour n'importe quel `x`.
2. **Il n'y a pas de `return`**. La dernière expression est la valeur.
   On ne dit pas à Heaven *comment* calculer, on lui dit *ce que*
   `double` signifie.

Ce style s'appelle **déclaratif**. Tu ne donnes pas d'instructions,
tu poses des équations.

## Et si je me trompe ?

    heaven> double "bonjour"
    eval error: error.TypeError

Heaven refuse. Pas parce qu'il est méchant, parce qu'il est honnête :
`*` demande deux nombres, et `"bonjour"` n'en est pas un.

Compare avec Python :

    >>> "bonjour" * 2
    'bonjourbonjour'

Python choisit une interprétation. Heaven refuse de choisir à ta place.
C'est parfois agaçant, et parfois exactement ce qu'on veut.

## Plusieurs clauses

Pour les fonctions un peu plus riches, on écrit plusieurs équations :

    heaven> add zero n = n
    ✓ clause enregistrée pour 'add'
    heaven> add (succ n) m = succ (add n m)
    ✓ clause enregistrée pour 'add'

`add` a maintenant **deux clauses**. Heaven essaie la première, puis la
seconde si la première ne matche pas. C'est le **pattern matching**, et
c'est central dans la suite.

On peut utiliser `add` :

    heaven> add zero zero
    zero
    heaven> add (succ zero) zero
    (succ zero)

`zero` et `succ` ne sont pas des nombres — ce sont des **constructeurs**
d'un type de données qu'on n'a pas encore vu (`Nat`). Tu comprendras au
chapitre 3. Pour l'instant, retiens qu'on peut définir des données et
des fonctions dessus, et que le pattern matching fait le tri.

## Taper du code dans un fichier

Le REPL est sympa pour explorer, mais pour un vrai programme on écrit
dans un fichier `.hvn` :

    -- hello.hvn
    double x = x * 2
    triple x = x * 3

    assert_eq double 21 == 42
    assert_eq triple 21 == 63

Puis :

    $ heaven --run-test hello.hvn
    ── Running tests from hello.hvn ──
    ✓ double x = x * 2 → ✓ clause enregistrée pour 'double'
    ✓ triple x = x * 3 → ✓ clause enregistrée pour 'triple'
    ✓ assert_eq double 21 == 42 → ✓ assert_eq passed
    ✓ assert_eq triple 21 == 63 → ✓ assert_eq passed
      Total: 4 / 4

Tu vois `assert_eq`. C'est la façon de vérifier qu'un calcul donne bien
ce qu'on attend. On en reparlera — c'est une des choses qui rend Heaven
différent.

## Un avant-goût de ce qui suit

Ce tutoriel va t'apprendre plusieurs choses qui sortent de l'ordinaire.

### Les effets algébriques

Tu peux écrire du code qui *performe* un effet (« log cette info »,
« lis ce fichier ») sans dire *comment* il est géré. Le handler décide :

    heaven> logHandler msg = (+ msg 100)
    heaven> handle (perform "Log" 42) logHandler
    142

Le `perform` signale l'effet. Le `handle` l'intercepte. Le même code
peut être instrumenté, simulé, ou testé sans changer une ligne.

### Les streams

Une liste paresseuse, avec une syntaxe légère pour la composer :

    heaven> inc x = x + 1
    heaven> dbl x = x * 2
    heaven> map (inc >>> dbl) (Cons 1 (Cons 2 End))
    (Cons 4 (Cons 6 End))

Le `>>>` compose deux fonctions. C'est le style d'astra-core, un DSL
de pipelines qu'on verra au chapitre 7.

### Les théorèmes

Ceci :

    heaven> theorem add_zero : x + 0 = x
    heaven> prove add_zero by simplify
    ✓ [add_zero] proved (simplify)

est vérifié par un noyau formel. Si Heaven dit que c'est prouvé, c'est
prouvé — dans les limites de son kernel, qu'on verra au chapitre 8.

### Les holes — demander de l'aide

Un **trou** n'est pas un `TODO` ni un `undefined`. C'est une **demande
d'assistance au système**. Tu écris :

    f x = ? + 1

et le système te répond avec le **but** (ce qu'il attend) et le
**contexte** (ce qui est en portée). Tu raffines progressivement,
jusqu'à ce qu'il ne reste plus de `?`.

C'est le **type-driven development**, popularisé par Idris et Agda.
On en reparle en détail au chapitre 8.

    -- vision : non implémenté
    heaven> f x = ? + 1
    ? : Int
    -- x : Int

## Où aller ensuite

- Chapitre 2 — on parle de **types** : ce que Heaven sait, et comment
  il te le dit.
- Chapitre 3 — **pattern matching**, constructions de données, `data`.
- Chapitre 4 — **récursion**, le cœur du fonctionnel.

Pour l'instant, joue avec le REPL. Casse des choses. `Ctrl-D` pour
sortir. `Ctrl-C` pour interrompre un calcul qui tourne trop longtemps.

À bientôt.
