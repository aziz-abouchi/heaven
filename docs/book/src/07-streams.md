# Chapitre 7 — Streams

> *« Une liste est finie. Un stream est une promesse. »*

Un `Stream`, c'est une liste paresseuse. Elle peut être infinie, ou
très longue, ou simplement inconnue à l'avance. On la décrit au fur et
à mesure qu'on la consomme. C'est le modèle qui sous-tend les pipelines
de traitement, les flux de données, et — dans notre cas — le DSL
d'astra-core.

## La structure

    data Stream a = Cons a (Stream a) | End

Identique à une liste chaînée. La différence n'est pas dans la
structure, elle est dans l'**usage**. On ne construit pas un `Stream`
entier en mémoire. On le décrit comme une *recette* : « si on me
demande le premier élément, voilà ; si on me demande le reste, voilà
comment le calculer ».

    heaven> Cons 1 (Cons 2 (Cons 3 End))
    (Cons 1 (Cons 2 (Cons 3 End)))

Pour l'instant, ça ressemble à une liste. C'est normal. La paresse
vient du fait qu'on ne force pas la suite tant qu'on ne la demande
pas.

## Les transformations de base

`map` applique une fonction à chaque élément :

    heaven> map f End = End
    heaven> map f (Cons x reste) = Cons (f x) (map f reste)

`filter` garde les éléments qui satisfont un prédicat :

    heaven> filter p End = End
    heaven> filter p (Cons x reste) =
      if (p x) (Cons x (filter p reste)) (filter p reste)

`take` rend les N premiers éléments :

    heaven> take zero s = End
    heaven> take (succ n) End = End
    heaven> take (succ n) (Cons x reste) = Cons x (take n reste)

`drop` saute les N premiers :

    heaven> drop zero s = s
    heaven> drop (succ n) End = End
    heaven> drop (succ n) (Cons x reste) = drop n reste

`zip` combine deux streams en un stream de paires :

    heaven> zip End s = End
    heaven> zip s End = End
    heaven> zip (Cons x rx) (Cons y ry) = Cons (Pair x y) (zip rx ry)

## La composition avec >>>

Rappelez-vous du chapitre 5 : `>>>` compose deux fonctions. Sur les
streams, c'est magique :

    heaven> stream = Cons 1 (Cons 2 (Cons 3 End))
    heaven> take 2 (map inc stream)
    (Cons 2 (Cons 3 End))

Mais avec `>>>`, on écrit :

    heaven> traitement = take 2 >>> map inc
    heaven> traitement stream
    (Cons 2 (Cons 3 End))

`traitement` est une fonction. Elle prend un stream, en garde 2, puis
incrémente. Chaque étape est indépendante. C'est exactement le style
d'astra-core.

## Le pipeline complet

Voici un exemple réaliste, inspiré d'un traitement de logs :

    heaven> isCritical x = x > 100
    heaven> toAlert x = let _ = perform "Alert" x in x
    heaven> pipeline = filter isCritical >>> take 3 >>> map toAlert

Décomposons :

1. **`filter isCritical`** : garde les logs critiques.
2. **`take 3`** : s'arrête après 3 éléments.
3. **`map toAlert`** : émet une alerte pour chacun.

On applique :

    heaven> logs = Cons 50 (Cons 120 (Cons 90 (Cons 150 (Cons 200 End))))
    heaven> pipeline logs
    (Cons 120 (Cons 150 (Cons 200 End)))

Les alertes sont émises (ou pas, selon le handler), mais le pipeline
lui-même est pur.

## Pourquoi « paresseux » ?

Vous vous demandez peut-être : « c'est juste une liste, non ? » La
réponse : pas tout à fait.

L'idée du paresseux, c'est qu'on ne calcule que ce dont on a besoin.
Pour `take 3`, on n'a pas besoin de construire toute la liste — juste
les 3 premiers éléments. Si la liste fait un milliard d'éléments,
`take 3` n'en touche que 3.

Heaven n'implémente pas encore cette optimisation à fond (les streams
sont pour l'instant évalués strictement), mais la **structure** est
prête. Le jour où on ajoute la paresse, le code existant fonctionnera
tel quel.

## Les sous-streams (window)

Un cas plus avancé : `window n` transforme un `Stream a` en
`Stream (List a)`, où chaque élément est une fenêtre de `n` éléments
consécutifs.

    window 3 (Cons 1 (Cons 2 (Cons 3 (Cons 4 End))))
    -- devrait donner : (Cons (List 1 2 3) (Cons (List 2 3 4) End))

C'est utile pour les moyennes glissantes, les détections de motifs,
etc. On ne l'a pas encore implémenté, mais c'est dans la feuille de
route.

## Comparaison avec les listes

| Liste | Stream |
|---|---|
| Finie | Peut être infinie |
| Construite en entier | Construite à la demande |
| `Nil` / `Cons` | `End` / `Cons` |
| Évaluation stricte | Évaluation paresseuse (à venir) |

En pratique, `Stream` est ce qu'on utilise pour tout ce qui vient
d'ailleurs : fichiers, réseau, capteurs, événements. Une `List` est
ce qu'on utilise pour des données qu'on contrôle entièrement.

## Le lien avec astra-core

astra-core est un DSL qui décrit des pipelines de traitement. Sa
syntaxe :

    logPipeline = filter isCritical >>> map toAlert >>> window 100 >>> tap notify

Chaque étape est une fonction. Le `>>>` les compose. Le résultat est
une fonction qui prend un stream et rend un stream.

C'est exactement ce qu'on vient de voir. Heaven implémente déjà
`filter`, `map`, `>>>`. Le jour où on ajoute `window` et `tap` avec
effets, on aura un astra-core complet, dans le langage lui-même.

## Récapitulatif

- Un `Stream` est une liste paresseuse : `Cons x reste | End`.
- `map`, `filter`, `take`, `drop`, `zip` fonctionnent dessus.
- `>>>` compose les transformations en pipelines.
- La paresse n'est pas encore implémentée, mais la structure est prête.
- `window` et les effets sur stream sont la prochaine étape.

Au chapitre suivant, on quitte le monde des valeurs pour entrer dans
celui des **théorèmes** : comment Heaven vérifie qu'une affirmation
est vraie.
