# Chapitre 10 — Under the Hood

> *« Un langage qu'on ne comprend pas est un langage qu'on ne peut pas
> aimer. »*

Dernier chapitre. On a vu comment utiliser Heaven. Maintenant,
regardons comment il est fait. Pas parce que vous allez le modifier
tout de suite, mais parce que comprendre la mécanique rend meilleur
programmeur.

## Les six primitives

Heaven repose sur **six primitives** :

1. **`lit`** : un littéral (entier, flottant, chaîne, booléen).
2. **`sym`** : un symbole (un nom, comme `x` ou `add`).
3. **`apply`** : une application (`f a`).
4. **`bind`** : une liaison (`let x = e in body`).
5. **`lambda`** : une abstraction (`λx. body`).
6. **`relation`** : une relation (`Eq(a, b)`).

Tout le reste — `if`, `let`, `+`, `*`, les listes, les types
dépendants — se **désucre** vers ces six primitives. C'est ce qu'on
appelle le *lowering*.

Par exemple, `(+ 1 2)` devient `apply(sym("+"), [lit(1), lit(2)])`.
`if cond then a else b` devient un apply particulier. Le compilateur
traduit tout en primitives, puis le reste du système ne connaît que
ces six formes.

## Le Store

Toutes les expressions sont stockées dans un **Store**, un grand
tableau de nœuds. Chaque nœud a :

- un **tag** (parmi les six primitives)
- un **payload** (un index ou une valeur)
- une **span** (une plage dans un pool d'arguments)

Un `Id` est un index dans ce tableau. Deux expressions identiques ont
souvent le même `Id` — c'est un **hash-consing** léger.

Pourquoi ce design ? Parce qu'il est **rapide** et **compact**. Pas
de pointeurs, pas d'allocation par expression. Tout vit dans un
tableau qu'on peut parcourir vite.

## Le pool et l'invariant critique

Les arguments d'un `apply` ne sont pas dans le nœud lui-même : ils
sont dans un **pool** séparé. Un nœud `apply` a une `span_a` qui
pointe vers une plage du pool.

C'est efficace, mais ça crée un piège : si le pool est réalloué
pendant qu'on tient une slice vers lui, la slice devient **dangling**.
C'est le bug le plus fréquent de Heaven. Un poison `0xAAAAAAAA` dans
un `Id` signale qu'on lit de la mémoire libérée.

La parade : **snapshotter** avant tout appel qui peut réallouer. La
fonction `snapshotArgs` du Store encapsule ce pattern.

## L'évaluateur

L'évaluateur est une fonction récursive `evaluate(store, env, engine,
id, depth)`. Elle prend un `Id` et rend un `Id` (la forme évaluée).

Elle a six branches, une par tag :

- `lit` : déjà une valeur.
- `sym` : cherche dans l'environnement, ou retourne le symbole.
- `apply` : évalue l'opérateur et les arguments, dispatch.
- `bind` : lie une valeur à un nom, évalue le corps.
- `lambda` : retourne tel quel (c'est une valeur).
- `relation` : évalue les deux côtés, retourne un booléen.

Le **dispatch** de `apply` est là où tout se joue. Selon l'opérateur,
on appelle une fonction utilisateur, un opérateur magique (`+`, `if`,
`handle`), ou un constructeur.

## L'environnement

`Env` est une `HashMap` de `Sym` vers `Id`. Un `Sym` est un entier qui
représente un nom interné. Toutes les chaînes de caractères du
programme vivent dans un **interner** (une table de chaînes uniques).

L'environnement est **lexical** : quand on entre dans une lambda, on
copie l'environnement courant et on ajoute la liaison du paramètre.
C'est simple, et ça évite les fuites de portée.

## Le noyau de preuve

À part, il y a le **noyau** (`kernel.zig`). Il ne partage rien avec
l'évaluateur : ses propres types de termes, son propre vérificateur.
C'est volontaire : un noyau doit être **simple** et **autonome** pour
être auditable.

Le noyau a ~500 lignes de logique. Il implémente :

- l'inférence de types (`infer`)
- la vérification (`check`)
- la réduction (`whnf`, `eval`)
- la conversion (`subst`)

Quand vous prouvez un théorème, le noyau est le seul juge.

## Le compilateur C

Heaven embarque **TinyCC** (TCC) pour compiler du C à la volée. C'est
utile pour l'interopérabilité et pour les performances. Le module
`codegen_expr_c` traduit l'AST en C, TCC compile, le résultat est
chargé en mémoire.

C'est ce qui permet à Heaven d'appeler du C natif sans avoir besoin
d'un compilateur externe.

## Le compilateur WebAssembly

Pour le web, Heaven se compile en **WebAssembly** via le backend
Zig. Le même code source, deux cibles. Le module `wasm_entry.zig` est
le point d'entrée du wasm.

Les tests tournent en WASM avec le même `heaven.eval`. C'est ce qui
garantit que le comportement du web est identique au natif.

## La philosophie

Trois principes structurent Heaven :

1. **Un noyau minimal, un frontend riche.** Le noyau vérifie les
   preuves. Le frontend offre des tactiques, du sucre syntaxique, des
   raccourcis. Les deux communiquent par un AST bien défini.

2. **Zéro dépendance externe.** Tout est vendu avec le code source :
   TCC, tree-sitter, les parseurs. Pas de `apt install`, pas de
   `cargo`. Le projet compile seul.

3. **Iso-fonctionnalité.** Le natif et le web font la même chose. Le
   test `test_suite.hvn` tourne dans les deux.

## Ce qui reste à faire

Heaven est un projet jeune. Il manque :

- **L'optimisation d'appel terminal** (récursion efficace).
- **La paresse** sur les streams.
- **Les types quotients** dans le noyau.
- **Un scheduler** pour les acteurs.
- **Une bibliothèque standard** plus riche.

Chaque point est identifié. La structure est prête. C'est une question
de temps et de contributions.

## Le mot de la fin

Vous avez traversé dix chapitres. Vous savez écrire des fonctions,
manipuler des listes et des streams, gérer des effets, prouver des
théorèmes. Vous savez aussi comment tout ça tient ensemble.

Heaven n'est pas parfait. Il est jeune, parfois rugueux, avec des
coins non polis. Mais il essaie quelque chose d'ambitieux : faire
tenir dans un même langage la légèreté d'un REPL, la rigueur d'un
assistant de preuve, et la réactivité des systèmes modernes.

Si vous voulez contribuer, tout est sur GitHub. Si vous voulez
juste l'utiliser, le REPL vous attend. Dans tous les cas, amusez-vous
bien.

À bientôt.
