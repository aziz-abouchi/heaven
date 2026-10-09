# Chapitre 16 — Free monads : séparer programme et interprétation

> *« Écrire un programme, c'est décrire ce qu'on veut faire.
> L'exécuter, c'est décider comment. Les deux peuvent être séparés. »*

Jusqu'ici, quand on a voulu faire quelque chose, on l'a fait tout de
suite : `(+ 1 2)` calcule, `perform` signale, `writeFile` écrit. Le
programme **est** son exécution.

Mais dans beaucoup de cas, on voudrait **décrire** un programme sans
l'exécuter tout de suite : pour le tester, pour le transformer, pour
l'interpréter de plusieurs manières. C'est l'idée derrière les
**free monads**, une abstraction qui vient de la théorie des
catégories et qui a envahi l'écosystème Haskell grâce aux
bibliothèques d'Edward Kmett.

Ce chapitre présente l'idée et son implémentation minimale en Heaven.
Le module `core/std/free.hvn` (49 lignes) est un **AST
d'opérations** avec plusieurs interpréteurs — la version
dégénérée mais déjà utile d'un free monad complet.

## Le problème : programme = exécution

Supposons qu'on veuille écrire une petite machine à pile. En style
direct :

    calc_direct _ = (+ 10 20)

Cette fonction fait le calcul. Rien à redire. Mais :

- Impossible de **la tester** sans l'exécuter.
- Impossible de **l'optimiser** sans la réécrire.
- Impossible de lui donner **plusieurs sens** (évaluer, tracer,
  compiler vers autre chose).

Pour séparer le *quoi* du *comment*, on décrit d'abord les
opérations comme une **structure de données**. La structure ne
fait rien : elle raconte.

## Le type Free : un AST d'opérations

Le module `core/std/free.hvn` définit quatre opérations et une fin :

    data Free
      = Pure Int
      | Push Int Free
      | Add Free
      | Mul Free
      | LogOp Str Free

Chaque constructeur représente **une instruction** :

- `Pure x` — fin du programme, on rend la main.
- `Push n rest` — empile `n` puis continue avec `rest`.
- `Add rest` — dépile deux valeurs, empile leur somme.
- `Mul rest` — idem avec le produit.
- `LogOp s rest` — émet un log `s` puis continue.

Un programme, c'est une **liste chaînée** de ces instructions. Par
exemple, « calcule (10 + 20) » s'écrit :

    p1 _ = (Push 10 (Push 20 (Add (Pure 0))))

C'est un **arbre**, mais en pratique une liste puisque chaque
constructeur a une seule continuation. Le `Pure 0` final est un
marqueur de fin (le `0` n'est pas utilisé).

## Deux interpréteurs, un seul programme

Le point magique : le même `p1` peut être interprété de plusieurs
façons. Le module en fournit deux.

**Interpréteur 1 : évaluer sur une pile.** `run_stack` traverse
l'AST en maintenant une pile d'entiers :

    run_eval (Pure _) stack = (if (null stack) 0 (head stack))
    run_eval (Push n rest) stack = (run_eval rest (cons n stack))
    run_eval (Add rest) stack =
      (run_eval rest (cons (+ (head stack) (head (tail stack)))
                           (tail (tail stack))))
    ...

Sur `p1`, ça donne `30`. Sur `p2 = (Push 3 (Push 4 (Mul (Pure 0))))`,
ça donne `12`. Sur `p3`, qui mélange `Push`, `LogOp` et `Add`, ça
donne `7` — les logs sont ignorés.

**Interpréteur 2 : collecter les logs.** `run_trace` oublie les
opérations arithmétiques et ne garde que les `LogOp` :

    run_log (Pure _) acc = acc
    run_log (Push _ rest) acc = (run_log rest acc)
    run_log (Add rest) acc = (run_log rest acc)
    run_log (Mul rest) acc = (run_log rest acc)
    run_log (LogOp s rest) acc = (run_log rest (cons s acc))

Sur le même `p3`, ça donne la liste `["done", "start"]` (ordre
inverse, dernier en tête). Le calcul `5 + 2` n'a plus aucune
importance — l'interpréteur ne le voit pas.

**Même programme, deux sens.** On peut ajouter un troisième
interpréteur qui compte les opérations, un quatrième qui compile
vers du code C, un cinquième qui exécute en parallèle... sans
toucher au programme lui-même.

## Pourquoi ça s'appelle « free »

Dans la théorie des catégories, la **monade libre** sur un foncteur
`f` est la monade la plus générale qu'on puisse construire à partir
de `f`. En Haskell :

    data Free f a = Pure a | Free (f (Free f a))

`Free f a` est un programme dont les opérations sont décrites par
le foncteur `f`, et dont le résultat final est de type `a`. C'est la
structure « minimale » qui supporte `>>=` (bind) : on peut chaîner
des programmes librement, et l'interprétation se fait a posteriori
via des transformations naturelles.

En Heaven, on est **monomorphe** : `Free` porte des `Int` en
résultat final, et les opérations sont figées (Push/Add/Mul/LogOp).
C'est moins général que la version Haskell, mais l'idée — séparer
*programme* de *interprétation* — est la même.

## Ce qui manque pour un vrai free monad

Le module fait 49 lignes et rend déjà service : il sépare
programme et interprétation, il supporte plusieurs interpréteurs.
Mais il lui manque deux choses pour être un vrai free monad.

**1. Le `>>=` (bind).** En Haskell, `>>=` chaîne deux programmes :
`p >>= f` est un programme qui exécute `p`, puis passe son résultat
à `f` pour continuer. On avait essayé d'écrire :

    chain (Pure x) k = (k x)
    chain (Push n rest) k = (Push n (chain rest k))
    ...

Ça ne marche pas tel quel parce que `Pure x` marque une **position**
dans la pile, pas une **valeur de retour**. Pour que `chain`
fonctionne, il faudrait que `Pure` porte réellement la valeur
finale et que les continuations (`k`) reçoivent cette valeur
comme argument. Or en Heaven v0, `Pure x` est un marqueur ; le
résultat réel vit sur la pile d'exécution, pas dans la structure.

**2. Les continuations valuées.** Pour un vrai bind, il faut que
chaque opération puisse dire : « après avoir fait ceci, appelle
cette fonction avec le résultat ». Ça demande que les continuations
soient des **fonctions** (`Int -> Free`) plutôt que des `Free`
directs. On a vu au chapitre 15 que Heaven supporte les fonctions
comme valeurs (avec le fix first-class). Mais le type `data Free`
devrait alors contenir des champs de type fonction, et la
récursion entre `Free` et `(Int -> Free)` complique le pattern
matching.

**Verdict honnête** : le module est un **AST interprétable**, pas
une implémentation complète de free monad. C'est suffisant pour la
plupart des usages pratiques (DSL simples, tests multiples), mais
ce n'est pas la généralité de la version Haskell.

## Pourquoi documenter un presque-free-monad

Parce que l'**idée** est plus importante que la généralité :

1. **Séparation programme/interprétation** : c'est la contribution
   conceptuelle majeure. On l'a, et elle est utilisable.
2. **Multi-interprétation** : on l'a aussi. C'est ce qui rend les
   free monads intéressants en pratique.
3. **Point d'extension** : si Heaven v0.2 ou v0.3 ajoute des
   types plus riches (HKT, continuations valuées), le module
   `free.hvn` pourra être étendu sans casser l'API — les noms
   `Push`, `Add`, `run_stack`, `run_trace` sont stables.

C'est le même principe que pour les optiques au chapitre 15 :
mieux vaut une version minimale qui **fonctionne** et documente
ses limites, qu'une version théoriquement complète qui n'existe
pas encore.

## Pour aller plus loin

- `core/std/free.hvn` : le module (49 lignes).
- `tests/test_free.hvn` : 14 tests qui couvrent `run_stack` et
  `run_trace` sur quatre programmes.
- La bibliothèque **`free`** de l'écosystème Haskell implémente
  la vraie monade libre, avec `>>=`, `liftF`, et une collection
  d'interpréteurs réutilisables.
- Les **monades libres** sont le fondement de `mtl`, `polysemy`,
  `fused-effects` — les bibliothèques modernes de gestion
  d'effets en Haskell.
- Le lien avec le chapitre 6 (Effects) : les effets algébriques
  de Heaven sont une autre manière de séparer *quoi* de
  *comment*. Les free monads sont la version « data » de la même
  idée.

---

Tu sais maintenant décrire un programme comme une **donnée** et
l'interpréter de plusieurs façons. C'est une des idées les plus
puissantes de la programmation fonctionnelle : le code n'est pas
seulement exécuté, il est manipulé, transformé, analysé.

On a construit beaucoup d'abstractions — types, preuves, effets,
streams, schémas de récursion, optiques, free monads — et on a vu
qu'elles se répondent les unes aux autres. Mais **comment tout
cela tient ensemble** au niveau du compilateur ? Le prochain
chapitre ouvre le capot : le noyau à 6 primitives, le tree-walker,
le compilateur, et pourquoi ces choix pèsent sur chaque décision
du langage.
