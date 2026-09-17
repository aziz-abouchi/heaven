# Chapitre 6 — Effects

> *« Le code pur calcule. Le code impur agit. Un bon langage sépare
> les deux sans les rendre incompatibles. »*

Jusqu'ici, tout notre code était **pur**. `inc`, `map`, `filter` :
ils prennent des valeurs, rendent des valeurs, et ne font rien
d'autre. Pas de lecture de fichier, pas de log, pas de requête réseau.

Mais les programmes réels doivent *faire* des choses. Comment
concilier pureté et action ? La réponse de Heaven s'appelle les
**effets algébriques**.

## Le problème

Imaginez une fonction qui doit logger chaque étape d'un calcul. En
Python :

    def traite(x):
        print(f"traitement de {x}")
        return x * 2

Cette fonction est *impure* : elle écrit sur la sortie standard. On ne
peut pas la tester sans capturer stdout. On ne peut pas la paralléliser
sans mélanger les logs. On ne peut pas la transformer en appel réseau
sans tout réécrire.

En Heaven, on sépare l'**intention** de l'**exécution** :

    traite x = let _ = perform "Log" x in x * 2

`perform "Log" x` dit : « je veux logger `x` ». Pas *comment*. C'est
un signal, pas une action. Le code reste pur tant que personne
n'intercepte.

## Intercepter avec handle

Pour donner un sens au signal, on utilise `handle` :

    heaven> logHandler msg = (+ msg 100)
    heaven> handle (perform "Log" 42) logHandler
    142

Déroulons :

1. `perform "Log" 42` émet le signal avec la valeur 42.
2. `handle ... logHandler` intercepte le signal.
3. Il appelle `logHandler 42`, qui rend 142.
4. `handle` rend ce résultat.

Le handler décide. C'est *lui* qui sait quoi faire du signal. Le code
de `perform`, lui, n'en sait rien.

## Plusieurs handlers

Le même signal peut être interprété de plusieurs façons. On peut :

- **logger vraiment** : `logHandler msg = print msg`
- **compter les logs** : `logHandler msg = (+ msg 1)`
- **ne rien faire** : `logHandler msg = msg`
- **simuler en test** : accumuler dans une liste

Le code qui émet le signal ne change pas. C'est toute la puissance.

## Chaîner plusieurs effets

On peut traiter plusieurs signaux dans un seul `handle` :

    heaven> traiteTout = handle (perform "Log" 1) (handle (perform "Log" 2) logHandler)

Mais c'est lourd. En pratique on écrit :

    heaven> traite xs = map traitementUnitaire xs
    heaven> traitementUnitaire x = let _ = perform "Log" x in x

Un seul `handle` au niveau supérieur intercepte tout.

## Effets et pureté

On dit souvent qu'un langage avec effets algébriques reste **pur**.
C'est vrai, mais il faut comprendre pourquoi.

Une fonction comme `traite` :

    traite x = let _ = perform "Log" x in x * 2

est, mathématiquement, une fonction. Elle prend `x`, elle rend `x * 2`.
Le `perform` est un effet *suspendu* — il ne se produit que si
quelqu'un l'intercepte. Tant que personne ne le fait, la fonction est
inerte.

C'est pour ça qu'on peut la tester en isolation : on ne fournit pas de
handler, et le signal disparaît. Pas de log, pas de bruit, pas de
sortie. Juste le calcul.

## Les effets sont des valeurs

Il y a une conséquence importante : un effet non géré est une
**valeur**. On peut le capturer, le passer, l'accumuler. Par exemple :

    heaven> accumulateur = (perform "Log" 1) + (perform "Log" 2)

L'expression vaut la somme des valeurs émises. Mais les signaux,
eux, attendent un handler.

En pratique, ça permet des choses comme :

- **Les tests** : on accumule les logs dans une liste, on vérifie
  qu'ils sont les bons.
- **Le replay** : on enregistre les signaux, on les rejoue plus tard.
- **Le tracing** : on enveloppe une fonction, on compte combien de
  fois un effet est déclenché.

Aucune de ces techniques ne change la fonction originale.

## Green profiling

Heaven utilise ce mécanisme pour une chose particulière : le
**green profiling**. C'est un mode où chaque `perform` est compté, et
où le temps CPU passé dans les effets est mesuré. On l'active avec :

    heaven> green (handle (perform "Log" 42) logHandler)
    142 (green calls: 1, cpu: 324000ns, wall: 326247ns, energy: 0.000J)

Le résultat est le même (`142`), mais on a en plus le nombre d'appels
et les métriques. Utile pour optimiser sans changer le code.

## Comparaison avec les monades

Si vous venez de Haskell, vous connaissez les monades. Une monade
encapsule un effet et une valeur, et force le programmeur à
enchaîner les opérations avec `>>=`. C'est puissant mais ça envahit
toute la signature des fonctions.

Les effets algébriques sont différents : ils *ne changent pas la
signature*. Une fonction qui émet un effet est de type `Int -> Int`,
exactement comme une fonction pure. C'est au **handler** de décider
si l'effet existe ou non.

C'est plus permissif. C'est aussi plus dangereux : rien ne vous
empêche d'oublier un handler et de laisser un effet suspendu. Mais en
pratique, c'est plus simple à raisonner.

## Récapitulatif

- `perform` **émet un signal**, sans rien exécuter.
- `handle` **intercepte** le signal et appelle un handler.
- Le même code peut être testé, loggé, simulé sans changement.
- Les effets suspendus sont des **valeurs**.
- `green` active le profilage des effets.
- Les effets algébriques ne polluent **pas** les signatures.

Au chapitre suivant, on applique tout ça aux **streams** : une liste
paresseuse où les effets jouent un rôle central.
