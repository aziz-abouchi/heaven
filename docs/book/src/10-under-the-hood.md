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

## Un monolithe qui se découpe

À l'origine, tout le frontend vivait dans un seul fichier,
`heaven_expr.zig` : le REPL, les tactiques, les imports, les types
dépendants, le chargement de la stdlib. 4000 lignes. Ça marchait,
mais ça freinait tout — impossible de tester une partie isolément,
impossible de lire la structure sans tout avaler.

Le découpage (RFC-0001) a extrait six modules :

- `io_handler.zig` — `print`, `readFile`, entrées/sorties.
- `expr_parser.zig` — parsing des expressions (infixe, S-expr,
  lambda).
- `hole_runtime.zig` — les trous `_`, leur raffinement, leur
  description.
- `std_loader.zig` — chargement des fichiers `core/std/*.hvn` au
  boot.
- `import.zig` — résolution de chemins, cycles, exports.
- `unify_proof.zig` — unification de premier ordre pour les
  tactiques.

Chaque module suit le même contrat. Il ne connaît **pas** la struct
`Heaven` — ça créerait un cycle d'import. Il prend un paramètre
`heaven: anytype`, et Zig résout les champs à la compilation :
`heaven.allocator`, `heaven.eval`, `heaven.current_module`. Si un
champ manque, le compilateur le dit. Il retourne ses propres
erreurs (`ImportError = error{OutOfMemory}`), et le wrapper dans
`heaven_expr.zig` traduit en `HeavenError`.

C'est un peu inhabituel — en général, on préfère des interfaces
explicites. Mais pour un projet solo, c'est un compromis
raisonnable : pas de fichier `interface.zig` à maintenir, pas de
boilerplate, et le compilateur vérifie tout.

## Deux sortes de trous

Il y a **deux** notions de « trou » dans Heaven, et les confondre
mène à des bugs silencieux.

Le premier est `Tag.hole`. C'est ce que vous tapez quand vous
écrivez `_` dans un programme. Un trou, c'est « je ne sais pas
encore quoi mettre ici ». Le REPL peut vous demander de le
raffiner. Il ne participe pas à l'unification.

Le second est `Tag.evar`. C'est une **métavariable** interne.
Personne ne la tape. Les tactiques la créent quand elles ont
besoin de nommer un inconnu à unifier. `unify` sait la lier.

Le piège : quand on a introduit v2d (unification d'indexes
dépendants), le code produisait `Vec (succ _)` avec `_` parsé en
`Tag.hole`. Puis il appelait `unify`. Mais `unify` ne lie que les
`Tag.evar`. Résultat : la substitution restait **toujours vide**.
Le mécanisme était un no-op silencieux.

Les tests v2d ne l'ont pas vu, parce qu'ils vérifiaient le résultat
d'un appel (`head (Cons 42 Nil) → 42`), et le pattern matching
liait `x := 42` indépendamment de l'unification. C'est le genre de
bug qu'on ne trouve qu'en testant **la chose qu'on croit avoir
ajoutée**. v2e a ajouté un test qui vérifie explicitement que la
substitution n'est pas vide. Il a échoué. C'était le bon signal.

Le fix : `holesToEvars`, une méthode qui parcourt un `Id`, remplace
chaque `Tag.hole` par un `Tag.evar` frais, et laisse le reste
intact. Avant d'unifier, on convertit. Aujourd'hui, ce mécanisme
tourne mais ne change encore rien en pratique — le body d'une
clause est parsé depuis une string utilisateur, il n'y a jamais
d'evar dedans. v2e est préparatoire à v2f (unification vraie modulo
arithmétique, `Vec (n + m)`).

## Un bug vieux de deux ans

Un dernier détail, dans le Store.

Un nœud `apply` a deux champs : `payload` (l'opérateur) et `span_a`
(les arguments). Quand on a voulu ajouter `Store.pi` — la
construction du type Π, celui de `(n : Nat) -> Vec n -> a` — on a
écrit un code qui mettait un `Id` dans `payload`.

C'était faux. `payload` doit contenir un **Sym** (un entier interné)
pour `apply`, et un **Id** pour d'autres tags. Le compilateur ne le
dit pas, parce que `payload` est un `u32` unique qui accepte les
deux par coercition. On l'a découvert en écrivant v2c, quand
`sig head : ... -> a` se comportait bizarrement.

Le fix est une ligne. La leçon : dans un langage non typé, `u32`
peut cacher n'importe quoi. Le hash-consing aide, mais ne remplace
pas la discipline.

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
- **L'unification vraie des indexes** (`Vec (n + m)`, v2f).

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
