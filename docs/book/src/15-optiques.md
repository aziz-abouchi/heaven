# Chapitre 15 — Optiques : lire et écrire en profondeur

> *« Un champ, c'est un nom qui sait lire et écrire. Une optique,
> c'est la même idée, mais composable. »*

Au chapitre 14, on a factorisé la **récursion**. Il reste un autre
genre de boilerplate dans nos programmes : l'accès aux structures
imbriquées. Pour lire le fond d'un `Pair (Pair a b) c`, on écrit
`(fst (fst p))`. Pour modifier cette valeur, il faut démonter,
changer, remonter :

    set_pp_fst v p =
      let inner = (fst p) in
      (pair (pair v (snd inner)) (snd p))

Sur un seul niveau, ça va. Sur cinq, ça devient illisible. Et chaque
nouvelle forme de structure demande une nouvelle paire de fonctions.

Les **optiques** formalisent cet accès. Ce chapitre présente l'idée,
montre comment la littérature (Haskell) la réalise, puis explique
pourquoi Heaven v0 ne peut pas encore l'implémenter.

## L'idée : séparer lire de écrire

Une **lens** est un couple : un *getter* et un *setter*.

    get : s -> a          -- extrait la valeur cible
    set : a -> s -> s     -- remplace la valeur, rend la source modifiée

Ces deux fonctions vivent ensemble. Un exemple pour `Pair` :

    lens_fst = (pair fst set_fst)   -- conceptuellement

Une fois qu'on a une lens, on peut :

- **Lire** : `view l s` applique le getter.
- **Écrire** : `set_via l v s` applique le setter.
- **Modifier** : `over l f s` combine les deux.

Le point clé : le setter **préserve le reste**. On ne touche qu'un
champ, tout le contexte autour survit intact.

## La vraie promesse : la composition

En Haskell, deux lenses se composent en une seule avec l'opérateur
`.`. Si `l1` cible `a` dans `s`, et `l2` cible `b` dans `a`, alors
`l1 . l2` cible `b` dans `s`. C'est cette composition qui rend les
optiques puissantes : on écrit une lens pour chaque champ, et on
les combine à l'infini sans boilerplate.

Un exemple Haskell :

    data Person = Person { name :: String, address :: Address }
    data Address = Address { city :: String, zip :: Int }

    cityOf :: Lens' Person String
    cityOf = address . city

    -- Utilisation
    view cityOf person          -- "Paris"
    set cityOf "Lyon" person    -- person avec ville changee

Deux lenses (`address`, `city`), une composition, et on lit/ecrit au
fond d'une structure sans ecrire une seule fonction de reconstruction.

## Pourquoi Heaven v0 ne peut pas

L'implémentation naturelle d'une lens en Heaven serait :

    lens get set = pair get set
    view l s = (fst l) s
    set_via l v s = (snd l) v s

On met les deux fonctions dans un `Pair`, et on les appelle quand
on en a besoin. Simple. Élégant.

**Mais ça ne marche pas.** Test minimal :

    g x = (+ x 1)
    set_z v _ = v
    mkl _ = (pair g set_z)

    -- Ces appels echouent :
    ((fst (mkl 0)) 5)       -- devrait etre 6
    ((snd (mkl 0)) 100 0)   -- devrait etre 100

Le probleme : en Heaven v0, les **fonctions ne sont pas des valeurs
first-class**. On peut les passer en argument (`map f xs` marche),
mais on ne peut pas les *stocker* dans une structure de donnees et
les récupérer plus tard. Quand on écrit `(pair g set_z)`, le `g` et
le `set_z` sont des symboles, pas des closures. Les extraire du
`Pair` avec `fst`/`snd` renvoie le symbole, pas une fonction
appelable.

C'est une limite de fond du runtime actuel : les fonctions sont
enregistrées dans un `FunctionRegistry` nommé, pas dans le `Store`
comme des valeurs. Les passer en argument marche par un chemin
spécial (application directe), mais les stocker demanderait que
`Expr.Value` inclue un cas « closure ».

## Le blocage précis

Résumé de ce qui manque pour que les optiques marchent :

- **Fonctions comme valeurs** : `Expr.Value` doit pouvoir contenir
  une lambda ou une référence de fonction, pas seulement des
  littéraux et des constructeurs.
- **Application de valeurs-fonctions** : le tree-walker doit savoir
  appliquer un `Id` qui pointe vers une closure, pas seulement un
  symbole résolu dans le registre global.
- **Composition générique** : une fois les deux points ci-dessus
  réglés, `l1 . l2` devient une lens construite à la volée à partir
  de deux autres. Sans ce dernier point, on peut avoir des lenses
  mais pas de composition — donc l'intérêt diminue beaucoup.

Ces trois étapes sont un chantier **estimé à 2-3 sessions**.
Il touche le cœur du runtime (`Expr.Value`, `evaluate`, `apply`),
pas juste le parser. Ce n'est pas un ajout cosmétique.

## Pourquoi documenter une fonctionnalité qui n'existe pas ?

Parce que ce chapitre **définit un objectif**. Les optiques sont
l'une des abstractions les plus utiles de l'écosystème fonctionnel.
Elles résolvent un problème réel (accès imbriqué) avec une solution
élégante (composition). Documenter ce qu'on ne peut pas encore faire
**est aussi important que documenter ce qu'on peut faire** : ça
oriente les prochains chantiers.

En attendant, on écrit les setters à la main. C'est verbeux, mais
correct. Et quand les fonctions first-class arriveront, tout ce code
manuel pourra être remplacé par des lenses composées, sans casser
l'API (les noms `view`/`set_via`/`over` sont stables).

## Pour aller plus loin

- La bibliothèque **`lens`** de l'écosystème Haskell (Edward Kmett)
  est la référence. Elle implémente non seulement les lenses mais
  aussi les **prisms** (accès 0-ou-1), les **traversals** (accès
  0-ou-plusieurs), et les **isos** (bijections).
- L'article fondateur de **van Laarhoven** (2009) montre comment
  encoder une lens comme un simple type de fonction, ce qui permet
  la composition gratuite via `.`.
- Les **profunctor optics** (Pickering, Gibbons, Wu 2017)
  généralisent encore : toutes les optiques deviennent des
  transformations de profoncteurs, unifiées et composables.
- Le module `core/std/recursion.hvn` (chapitre 14) montre le même
  esprit appliqué à un autre problème : séparer la structure du
  parcours pour la réutiliser.

---

Tu sais maintenant ce que sont les optiques, pourquoi elles sont
utiles, et pourquoi Heaven n'y est pas encore. Il reste un chapitre
avant la fin : **Under the Hood**. On ouvre le capot et on regarde
comment tout ce qu'on a construit — types, preuves, effets, streams,
schémas de récursion — **tient ensemble** au niveau du compilateur.
