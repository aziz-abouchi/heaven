# Chapitre 16 — Optiques : lire et écrire en profondeur

> **Version 2 (2026-11-04)** — refonte style LYAH/LYSE.
> Version publiée : `15-optiques.md` (v1).
> Référentiel de style : `05-recursion.md` (v2, pilote).

> *« Une lentille ne change pas ce qu'elle voit. Elle décide
> seulement ce qui, depuis elle, devient visible. »*
> — à la manière d'Erik Meijer, Maarten Fokkinga et Ross Paterson,
> *Functional Programming with Bananas, **Lenses**, Envelopes and Barbed Wire* (1991)

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

Les **optiques** formalisent cet accès. Ce chapitre les présente
et les implémente en Heaven — avec les penseurs qui les ont pensées.

![Encodage van Laarhoven](images/15-van-laarhoven.svg)

## 1. Le problème : accéder, c'est déjà interpréter

En 1945, le philosophe **Maurice Merleau-Ponty** (1908-1961) publie
la *Phénoménologie de la perception*. Son argument central : on ne
perçoit jamais un objet « en soi », on le perçoit toujours **depuis
un point de vue**. Voir une maison, c'est voir une façade — pas
toutes les façades à la fois. La perception est *orientée*, et
cette orientation n'est pas un défaut : elle est la condition même
de l'accès.

Accéder à un champ dans une structure imbriquée, c'est exactement
ça. `(fst (fst p))` n'est pas neutre : c'est un **chemin** dans un
espace de positions. Et comme pour Merleau-Ponty, ce chemin est
corrélé à un **geste de modification**. Si je vise le `fst` du
`fst`, je peux le changer ; et changer demande de **préserver tout
le reste** — la façade qu'on ne regarde pas.

Les optiques font de cette idée un objet de première classe.

## 2. get et set — la lens comme couple

![Une source s, une cible a, deux flèches](images/15-get-set.svg)

Une **lens** est un couple : un *getter* et un *setter*.

    get : s -> a          -- extrait la valeur cible
    set : a -> s -> s     -- remplace la valeur, rend la source modifiée

Le mathématicien **David Spivak** (né en 1978), connu pour son
travail sur les bases de données catégoriques, a montré en 2016
(*A Categorical Reconstruction of Lenses*) que ce couple n'est pas
arbitraire : c'est un **morphisme dans une catégorie précise**, et
cette structure explique *pourquoi* les lenses se composent. Le
getter et le setter ne sont pas deux fonctions indépendantes
rangées ensemble — ils obéissent à des lois (lois « put-get »,
« get-put », « put-put »). En V0, on les tient à la main ; en V1,
elles pourraient être vérifiées.

En Heaven, on construit une lens avec `lens` :

    lens get set = (pair get set)

Et on l'utilise via trois opérations :

    view l s = (fst l) s
    set_via l v s = (snd l) v s
    over l f s = (snd l) (f (view l s)) s

- `view` lit la cible.
- `set_via` la remplace par une valeur donnée.
- `over` la modifie par une fonction.

Le point clé : le setter **préserve le reste**. On ne touche qu'un
champ, tout le contexte autour survit intact — c'est exactement
ce que le test `set pp_fst preserve snd` vérifie : après avoir
changé `pp_fst` de 1 à 99, `snd` vaut toujours 3.

L'exemple le plus simple, en REPL :

    heaven> view (lens_snd 0) (mk 0)
    3
    heaven> view (lens_snd 0) (set_via (lens_snd 0) 30 (mk 0))
    30
    heaven> view (lens_snd 0) (over (lens_snd 0) inc (mk 0))
    4

## 3. Composition — la promesse non tenue de V0

![Composition de deux lenses](images/15-compose.svg)

En Haskell, deux lenses se composent avec l'opérateur `.`. Si
`l1` cible `a` dans `s`, et `l2` cible `b` dans `a`, alors `l1 . l2`
cible `b` dans `s`. Un seul chemin, une seule opération.

En Heaven V0, cette composition **n'existe pas**. Il faut écrire
chaque composition à la main :

    get_pp_fst p = (fst (fst p))
    set_pp_fst v p =
      let inner = (fst p) in
      (pair (pair v (snd inner)) (snd p))

    lens_pp_fst _ = (lens get_pp_fst set_pp_fst)

La raison est profonde : pour composer génériquement, il faut que
le setter de `l1` soit *lui-même* paramétré par un autre setter.
C'est l'encodage de **Twan van Laarhoven** (2009), popularisé par
**Oleg Kiselyov** : une lens n'est plus un couple `(get, set)` mais
une fonction unique qui prend une fonction de modification et rend
une fonction de modification sur la structure externe.

    type Lens s a = forall f. Functor f => (a -> f a) -> (s -> f s)

Cette signature ne peut pas s'écrire en Heaven V0 — il faut des
types paramétrés, des classes de foncteurs, et l'égalité
extensionnelle qu'on n'a pas encore. V0 reste à `(get, set)`.
C'est une limitation de **fond**, pas de surface : elle disparaîtra
quand le système de types s'enrichira.

> **Piège** — Les trois lois de lens ne sont pas symétriques.
>
> Une lens `L` sur un champ `s.a` doit obéir à **trois** lois :
>
> 1. **Get-Set** : `(set L (view L s) s) == s` — écrire ce qu'on lit
>    ne change rien.
> 2. **Set-Get** : `(view L (set L a s)) == a` — lire ce qu'on vient
>    d'écrire rend ce qu'on a écrit.
> 3. **Set-Set** : `(set L b (set L a s)) == (set L b s)` — écrire
>    deux fois = écrire la dernière.
>
> **Ce qui surprend** : les trois ne sont **pas** équivalentes. `set`
> peut passer la loi 1 mais échouer la 2 (si `set` coerce `a`), ou
> passer 1 et 2 mais échouer 3 (si `set` accumule au lieu de
> remplacer).
>
> **Exemple concret** : une lens sur `Pair Int Int` avec
>
>     view (pair x _) = x
>     set (pair _ y) v = (pair v y)
>
> Passe Get-Set ? Oui (`view (set (pair 3 7) (view (pair 3 7))) = 3`).
> Passe Set-Get ? Oui (`view (set (pair 3 7) 5) = 5`). Passe Set-Set ?
> Oui. **Mais** si tu écris `set (pair _ y) v = (pair (+ v y) y)` (au
> lieu de remplacer), Set-Get échoue : `view (set (pair 3 7) 5) = 8 ≠ 5`.
>
> **Cas vécu** : `tests/optics/law_set_view_idem.hvn` (2/2) et
> `law_view_set.hvn` (2/2) testent **séparément** les lois 1 et 2.
> Le test 3 (`Set-Set`) est **absent** — c'est un trou documenté dans
> `tests/optics/README.md`. Si tu écris ta propre lens, teste les
> trois, pas deux.

## 4. Le bug qui a débloqué tout ça

L'implémentation de `lens.hvn` **ne marchait pas** avant un fix
précis. Ce code :

    g x = x + 1
    mkl _ = (pair g 0)
    ((fst (mkl 0)) 5)

devait rendre `6`. Il rendait autre chose. Pourtant, cette variante
marchait :

    (let f (fst (mkl 0)) (f 5))

Le problème était dans le tree-walker, pas dans la sémantique.
Quand on écrit `(apply expr args)`, l'évaluateur résolvait `expr`,
puis reconstruisait un nœud `apply` avec la valeur résolue **et**
les arguments d'origine — dont le premier argument qui *était*
`expr`. Résultat : le nœud reconstruit se croyait encore en
position d'opérateur, et passait **deux** arguments à la fonction
extraite au lieu d'un.

Le fix tient en quelques lignes (commit `2810cc7`) : reconstruire
le nœud avec **seulement** les arguments, sans l'opérateur
d'origine. Ça a suffi à débloquer les fonctions stockées dans des
structures.

C'est le point de **Christopher Strachey** (1916-1975), dans ses
*Fundamental Concepts in Programming Languages* (1967, publiés
tardivement en 2000). Strachey a introduit la distinction entre
les valeurs dites **first-class** (qu'on peut passer, retourner,
stocker) et les autres. Les fonctions en Heaven V0 sont *presque*
first-class — un seul `apply` mal reconstruit suffit à les
rétrograder. La leçon : quand un langage prétend qu'une valeur est
first-class, il faut pouvoir la mettre **n'importe où**, y compris
dans un champ de `Pair`. La lens a été le test qui a révélé que ce
n'était pas encore vrai.

## 5. Ce qui reste fragile en V0

Le module `core/std/lens.hvn` (32 lignes) couvre le strict minimum.
Trois limites à connaître, qu'on retrouve dans la bibliothèque
**`lens`** d'**Edward Kmett** (né en 1970) — la référence Haskell,
qui implémente tout ce qu'on n'a pas :

- **Composition générique absente** : pas d'opérateur `.` entre
  lenses. Chaque niveau supplémentaire demande une nouvelle paire
  de fonctions à écrire à la main. Kmett résout ça par l'encodage
  van Laarhoven, indisponible en V0.

- **Prisms et traversals absents** : une lens cible **exactement
  un** élément. Un **prism** cible zéro ou un (utile pour `Maybe`,
  `Either`, les sum types). Un **traversal** cible zéro ou
  plusieurs (listes, arbres). Ces optiques sont des variations du
  même motif — la bibliothèque Kmett les unifie sous
  `profunctor optics`. V0 s'arrête à la lens.

- **Pas de records** : sans champs nommés, toutes les lenses sont
  des `fst`/`snd` ou des positions. Si Heaven ajoute un jour des
  records, `lens_fst` deviendra `lens_name`, et tout le reste
  tiendra sans modification.

Ces limitations sont de surface pour deux d'entre elles (composition,
records), de fond pour l'autre (prisms/traversals demandent un
système de types plus riche).

## 6. Pourquoi ça vaut quand même

Même sans composition générique, une lens apporte deux choses —
et c'est **Ludwig Wittgenstein** (1889-1951) qui en donne la
formule la plus juste dans les *Recherches philosophiques* (1953) :
*« Les limites de mon langage sont les limites de mon monde. »*
Une lens, c'est un **mot nouveau** dans le vocabulaire du
programme.

1. **Un nom.** `view lens_snd p` dit ce qu'on fait. `(snd p)` dit
   la même chose mais sans intention. Sur du code long, la
   différence n'est pas cosmétique — c'est la différence entre un
   programme qui parle et un programme qui calcule.

2. **Un point d'extension.** Si demain on ajoute la composition
   générique ou les records, tout le code qui utilise
   `view`/`set_via`/`over` continuera de marcher. On n'aura changé
   que la **construction** des lenses, pas leur usage. C'est
   exactement le principe des abstractions bien posées :
   l'interface tient, la représentation bouge.

C'est le même mouvement qu'au chapitre 14 : Simon nous a dit qu'un
système complexe se construit par sous-ensembles stables. Une lens
est un sous-ensemble stable du code d'accès.

> **Sous le capot** — Une lens est une **paire de closures**, pas une
> structure Van Laarhoven.
>
> En Haskell, une lens est `type Lens s a = ∀f. Functor f => (a -> f a)
> -> s -> f s`. C'est du **Van Laarhoven** — une seule fonction qui
> encode get et set simultanément via le foncteur `f` (`Const` pour
> get, `Identity` pour set).
>
> Heaven V0 n'a pas ça. `core/std/lens.hvn` implémente une lens comme
> une **paire explicite** :
>
>     data Lens s a = MkLens ((s -> a), (s -> a -> s))
>     view (MkLens (get, _))   = get
>     set  (MkLens (_, put)) s a = (put s a)
>
> C'est **plus simple**, **plus direct**, et ça évite le HKT partiel
> (ch15, « Functor f => » n'est pas vérifié). C'est aussi **moins
> puissant** :
>
> | Van Laarhoven (Haskell) | Paire (Heaven V0) |
> |---|---|
> | `>>>` compose **toutes** les optiques | `>>>` compose seulement les lens |
> | Prismes, Traversals : même type | Types **distincts** par optique |
> | `(%%~)` sur un Functor | Pas de traverse générique |
> | Performance (fusion) | Pas de fusion |
>
> **Conséquence pour toi** : en V0, tu composes des **lens** (get/set
> sur champ) mais **pas** prismes (get/set sur variant) ni traversals
> (get/set sur N éléments) — ces deux derniers existent
> (`tests/optics/traversal.hvn` : 2/2) mais via des **types
> séparés**, pas composables avec `>>>`.
>
> **Le bug qui a débloqué tout ça** (`_runtime_gaps.md:290`,
> `apply-chain-in-returned-lambda`) : `(f x) y` où `f x` retournait
> une lambda ne s'appliquait pas — le runtime traitait `(f x)` comme
> un résultat final au lieu de continuer l'application. C'est ce qui
> empêchait les lens de composer (chaque `>>>` produit une lambda qui
> doit s'appliquer au suivant). Fixé le 2026-10-29.
>
> **`tests/optics/compose.hvn`** (2/2) teste la composition. **`iso_swap.hvn`**
> (3/3) teste un isomorphisme (`swap . swap == id`), qui est le cas
> dégénéré de lens (get et set sont des bijections).
>
> **Ce qui manque pour du vrai Van Laarhoven** : HKT complet (ch36),
> `Functor`/`Applicative` vérifiés, `compose` polymorphe. C'est la
> roadmap HKT (`_hkt_v1b_plan.md`) — 2 sessions après le noyau.

## Pour aller plus loin

- `core/std/lens.hvn` : le module (32 lignes).
- `tests/test_lens.hvn` : **12 tests** qui couvrent `view`/`set_via`/
  `over`, sur `Pair` simple et `Pair` imbriqué, plus un test
  first-class explicite — tous verts, exécution en moins de 10 ms.
- Référence externe : la bibliothèque **`lens`** d'Edward Kmett
  implémente composition générique, prisms, traversals, et bien
  plus — le tout fondé sur une théorie catégorique de l'accès
  (`van Laarhoven lenses`, `profunctor optics`). Heaven s'en
  inspire, mais s'arrête à la version minimale.
- Sur la théorie : David Spivak, *A Categorical Reconstruction of
  Lenses* (2016) — pourquoi `get`/`set` obéissent à des lois.

---

Tu sais maintenant lire et écrire dans des structures imbriquées
proprement, et tu as vu comment une limitation du runtime peut
bloquer une abstraction entière — jusqu'à ce qu'un bug de dix
lignes la débloque. C'est ça, un langage en construction : les
concepts avancés ne sont pas toujours possibles tout de suite, mais
ils laissent des traces — un nom, une interface, un test qui
échoue.

Il reste une autre abstraction de la même famille à explorer. Là
où les optiques accèdent à des **données**, les free monads
manipulent des **programmes**. Séparer le programme de son
interprétation est un motif qui revient partout. C'est le sujet du
prochain chapitre.

## Exercices

1. **Les trois lois.** Écris une lens sur `Pair Int Int` (get = premier,
   set = remplace le premier). Vérifie les **trois** lois :
   - `(set L (view L p) p) == p` (Get-Set)
   - `(view L (set L 5 p)) == 5` (Set-Get)
   - `(set L b (set L a p)) == (set L b p)` (Set-Set)
   
   Puis écris une **fausse** lens qui échoue à Set-Get (par exemple
   `set L 5 p = (pair (+ 5 (view L p)) (snd p))`) et vérifie laquelle
   des trois lois casse.

2. **Composition.** Compose deux lens : `L1` sur `Pair (Pair Int Int) Int`
   (premier = paire interne), `L2` sur `Pair Int Int` (premier = int).
   `(L1 >>> L2)` doit :
   - `view` : lire le `Int` au fond
   - `set` : remplacer le `Int` au fond, en préservant les paires
   
   Teste sur `(pair (pair 1 2) 3)`. `view (L1 >>> L2)` = 1.
   `set (L1 >>> L2) 99` = `(pair (pair 99 2) 3)`.

3. **Iso swap.** `tests/optics/iso_swap.hvn` teste `swap . swap == id`.
   Écris la même chose pour `reverse` sur liste : `(reverse . reverse) xs == xs`.
   Est-ce un isomorphisme ? *Indice* : oui, mais `reverse` n'est pas
   une lens — pas de `set`. C'est un **iso** (get et set sont des
   bijections). Peut-on l'encoder comme lens ? Oui, trivialement
   (`set _ a _ = a`, get = `reverse`), mais c'est **inutile** —
   l'intérêt de `set` est de **préserver** ce qui n'est pas modifié.

4. **Le trou de Set-Set.** Cherche dans `tests/optics/` le test
   `law_set_set` (s'il existe). S'il n'existe pas (probable), écris-le :
   `(set L c (set L b (set L a s))) == (set L c s)`. Lance-le sur les
   lens existantes (`compose.hvn`). Le trou est-il réel ou juste un
   oubli de test ? *Indice* : les lens en V0 sont **correctes** par
   construction (paire get/set), donc Set-Set passe. Le trou est
   **documentaire** — les tests ne le prouvent pas.

Les solutions ne sont **pas** dans le livre — c'est en cherchant
qu'on apprend.
