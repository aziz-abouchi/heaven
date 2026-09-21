# Chapitre 2 — Believe the Type

> *« Un type, c'est une promesse qu'on se fait à soi-même et qu'on
> tient. »*

Au chapitre précédent, on a vu Heaven refuser `double "bonjour"`. On
a dit « parce que `*` demande deux nombres ». Maintenant on va voir
pourquoi, et ce que Heaven sait vraiment.

## Le REPL te dit tout

Dans le REPL, demande à Heaven le type d'une expression :

    heaven> type 42
    Int
    heaven> type 3.14
    Float
    heaven> type "bonjour"
    String
    heaven> type true
    Bool

Simple. Une valeur a un type. `42` est un `Int`, `"bonjour"` est un
`String`, `true` est un `Bool`.

Tu peux aussi demander le type d'une fonction :

    heaven> inc x = x + 1
    ✓ clause enregistrée pour 'inc'
    heaven> type inc
    Int -> Int

`inc : Int -> Int`. La flèche se lit « vers ». Ça veut dire : prends
un `Int`, rends un `Int`.

## Les types sont des inventions

D'où viennent `Int`, `Float`, `String`, `Bool`, `Unit` ? Ce sont des
types **de base**. Heaven en a quelques-uns. On ne les définit pas,
on les utilise.

`Unit` mérite une mention. C'est le type qui ne contient **qu'une
seule valeur**. On l'écrit `()`. À quoi ça sert ? À dire « cette
fonction ne renvoie rien d'intéressant, mais elle renvoie quelque
chose ». Tu rencontreras `Unit` partout dans les fonctions qui
*font* quelque chose plutôt que de *calculer* quelque chose.

## Ce qui se passe sous le capot

`type` n'est pas magique. Heaven **infère** le type de l'expression :
il la parcourt, applique des règles, et te donne le résultat. Il ne
te demande pas de l'écrire. C'est l'**inférence de types**.

Compare avec C :

    int inc(int x) { return x + 1; }

Tu écris `int` deux fois. En Heaven :

    inc x = x + 1

Rien. Heaven a compris.

Compare avec Python :

    def inc(x):
        return x + 1

Python te laisse faire, et tu découvriras à l'exécution que `inc("a")`
est une erreur. Heaven t'avertit **avant** l'exécution, à la première
analyse. Le compromis : Heaven est plus strict, Python est plus
permissif.

## Quand Heaven ne sait pas

Il y a un cas où Heaven refuse de deviner :

    heaven> λx.x
    -> ?

Traduit : « une fonction d'un type vers un autre, mais je ne sais pas
lesquels ». Le `?` signifie **type inconnu**. Heaven ne peut pas
inventer. C'est un peu frustrant, mais c'est honnête.

Si tu veux, tu peux *guider* Heaven :

    heaven> type ((λx.x) 42)
    Int

Ici, on applique l'identité à `42`, donc le résultat est `Int`. Heaven
a déduit.

## Types paramétrés

Les types comme `Int` sont simples. Heaven en a de plus riches :

    heaven> data Maybe a = None | Some a
    ✓ data type registered (2 constructors)
    heaven> type Some 42
    Maybe Int

`Maybe a` prend **un paramètre** : le `a`. C'est un type **générique**.
`Maybe Int`, `Maybe String`, `Maybe (Maybe Bool)` sont tous des types
différents, tous construits sur le même moule.

L'intérêt ? Écris une fois, utilise partout :

    heaven> map f None = None
    heaven> map f (Some x) = Some (f x)

`map` fonctionne pour n'importe quel `Maybe a`, quel que soit `a`.
C'est ce qu'on appelle le **polymorphisme paramétrique**. Tu n'as pas
besoin de définir `map_Maybe_Int`, `map_Maybe_String`, etc.

## Les streams

Un exemple concret de type paramétré qu'on va utiliser souvent :

    heaven> data Stream a = Cons a (Stream a) | End
    ✓ data type registered (2 constructors)

Un `Stream Int`, `Stream String`, `Stream (Stream Bool)` — c'est
toujours la même structure, elle change juste de contenu.

On verra tout au chapitre 7. Pour l'instant, note que `Stream` prend
`a` et construit un type.

## Ce que ça change

Tu te dis peut-être : « pourquoi tout ce cérémonial ? Python marche
très bien sans types. » Trois choses :

**1. Les erreurs remontent tôt.** `double "bonjour"` échoue au moment
où tu tapes, pas à 2h du matin en production.

**2. Le code se documente.** `map : (a -> b) -> List a -> List b` te
dit tout. `def map(f, xs):` ne dit rien.

**3. On peut raisonner.** C'est là que ça devient intéressant. Si tu
sais que `add : Int -> Int -> Int`, tu peux affirmer :

    theorem add_zero : x + 0 = x

et Heaven **vérifiera** que ton théorème est bien typé. Un système de
types solide rend la preuve possible.

## Un mot sur les types dépendants

Il y a plus fort que les types paramétrés : les types **dépendants**.
Un type peut dépendre d'**une valeur**. Par exemple :

    Vector : Nat -> Type

`Vector n` est le type des vecteurs de longueur exactement `n`. Un
`Vector 3` a exactement 3 éléments. Un `Vector 5` en a 5. Le type
*lui-même* garantit la longueur — pas besoin d'un check à l'exécution.

C'est ce que font les assistants de preuve comme Coq ou Agda. Heaven
les supporte via son noyau CIC (Calcul des Constructions
Inductives), qu'on verra au chapitre 8.

Pour l'instant, retiens : **Heaven peut exprimer qu'un type dépend
d'une valeur**. C'est ce qui permet les théorèmes comme
`add_zero`, et c'est rare parmi les langages.

## Axiomes, holes, et le reste

Trois mots que tu croiseras bientôt :

**Axiome**. Une affirmation qu'on accepte sans preuve. Tu peux en
déclarer :

    axiom is_commutative : forall (a b : Int). a + b = b + a

Heaven ne le prouvera pas. Il l'enregistrera comme vérité de base. À
utiliser avec parcimonie.

**Hole**. Un trou dans ton programme, qui **demande de l'aide au
système**. Tu écris :

    f x = ? + 1

et le système te dit le type attendu et le contexte. C'est du
**type-driven development** — voir chapitre 8. Rien à voir avec un
`undefined` : ce n'est pas un placeholder, c'est une question.

**Signature**. Pour déclarer explicitement un type :

    inc : Int -> Int
    inc x = x + 1

Heaven vérifiera que l'implémentation correspond. C'est redondant avec
l'inférence, mais utile pour la documentation et les erreurs.

## En résumé

- Heaven **infère** les types — tu ne les écris pas d'habitude.
- Les types **de base** : `Int`, `Float`, `String`, `Bool`, `Unit`.
- Les types **paramétrés** : `Maybe a`, `Stream a`, etc.
- Les types **dépendants** : plus fort, on y viendra.
- `type <expr>` te dit tout dans le REPL.

Au chapitre suivant, on plonge dans le **pattern matching** : comment
écrire des fonctions qui prennent vraiment de la donnée structurée.
