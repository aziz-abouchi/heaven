# Chapitre 27 — Selfhost : la preuve de concept, pas le compilateur

> **Piège d'entrée.** « Selfhost » ne veut pas dire « le langage s'écrit
> lui-même ». Il veut dire « **le compilateur** du langage est écrit dans le
> langage qu'il compile ». Nuance importante : Heaven n'est **pas** selfhost.
> Il a des **briques** selfhostées (15 + 96 lignes), et un compilateur qui
> reste en Zig. Ce chapitre montre ce qui existe, ce qui n'existe pas, et
> pourquoi la frontière est plus basse qu'on ne le pense.

## 1. Le problème du bootstrap

Un compilateur écrit dans son propre langage, c'est un cercle vicieux : qui
compile le premier compilateur ? La réponse classique :

1. **Phase 0** — compilateur en langage hôte (Zig, C, OCaml…)
2. **Phase 1** — réécrire le compilateur dans le langage cible, compiler avec Phase 0
3. **Phase 2** — compiler Phase 1 avec Phase 1 → selfhost

Heaven est en **Phase 0**. Le compilateur (`src/`) est en Zig. Les outils
(LSP, MCP) sont en Heaven mais **appellent** le compilateur Zig via subprocess
(ch. 25). La Phase 1 n'est pas commencée.

## 2. `bin/heaven.hvn` — 15 lignes qui compilent

Le fichier le plus selfhosté du projet fait **15 lignes** :

```heaven
-- bin/heaven.hvn — CLI auto-hebergee, V0.7 (multi-clauses)
version "version" = 1
version "help" = 2
version "run" = 3
version "test" = 4
version x = 0

main = (version (@argv 1))
```

**Ce que ça prouve** :

- **Multi-clauses** (5 clauses `version`) → dispatch par pattern matching
- **Compilation native** → le binaire `heaven-natif` est un ELF qui exit 1/2/3/4
- **`@argv`** → accès aux arguments de la ligne de commande

**Ce que ça ne prouve pas** : que Heaven peut écrire un **compilateur**. C'est
juste une CLI minimale. La différence est la même qu'entre « Hello World en C
compile » et « GCC est écrit en C ».

> **Note importante** : ce binaire est produit par `heaven compile-qbe`. C'est
> la chaîne QBE qui fait la compilation native (ch. 30, hors v2). Le langage
> Heaven ne compile pas encore Heaven — Zig compile Heaven, qui s'exécute.


## 3. `lib/heaven_eval.hvn` — 96 lignes d'évaluateur

L'autre brique selfhostée est un **évaluateur métacirculaire** : Heaven évalue
des expressions Heaven en Heaven.

```heaven
data Value = VInt Int | VStr Str | VClosure Str Expr Env | VRecClosure Str Str Expr Env | ...
data Env   = EnvNil | EnvCons Str Value Env

eval (HP.ELitI n) env = (VInt n)
eval (HP.ELitS s) env = (VStr s)
eval (HP.ESym s) env = (eval_sym s env)
eval (HP.EApply f a) env = (eval_apply f a env)
eval (HP.ELambda p b) env = (VClosure p b env)
eval (HP.EBind n b) env = (eval_bind n b env)
```

**Ce que ça prouve** :

- `data` + pattern matching sur constructeurs → le langage peut **représenter** son propre AST
- `VClosure p b env` → les closures capturent leur environnement (persistant, `EnvCons`)
- `VRecClosure` → récursion auto-nommée (les fixpoints usuels)
- **17 primitives** (`+`, `-`, `*`, `cons`, `head`, `tail`, `pair`, `string_concat`, …)

**Ce que ça ne fait pas** :

| Composant | État |
|---|---|
| Parser | partiel (`lib/heaven_parse.hvn`, HP) |
| Évaluateur | 17 prims, V0.4 |
| Type-checker | absent |
| Codegen | absent |
| Compilateur complet | absent |

L'évaluateur importe `lib/heaven_parse.hvn` — donc la chaîne `parse → eval` est
**partiellement** en Heaven. Mais elle n'est pas selfhost : le binaire `heaven`
principal utilise le parser Zig (`heaven_expr.zig`), pas `lib/heaven_parse.hvn`.

Le test `tests/test_heaven_eval_prims.hvn` couvre les 17 primitives. C'est la
seule preuve automatisée du selfhost.


## 4. Piège : selfhost ≠ interpréteur

On confond souvent trois niveaux :

| Niveau | Définition | Heaven |
|---|---|---|
| **Interpréteur** | évalue un AST | ✅ `heaven_eval.hvn` (96 l.) |
| **Compilateur** | AST → code exécutable | ❌ (Zig → QBE) |
| **Selfhost** | le compilateur est écrit dans le langage | ❌ (0 %) |

Un interpréteur en Heaven est une **brique**. Il prouve que Heaven peut
représenter et manipuler son propre AST. Il ne prouve **pas** que Heaven peut
compiler Heaven — il faudrait un codegen en Heaven, qui n'existe pas.

**L'analogie** : avoir un interpréteur Lisp en Lisp, c'est vieux (McCarthy,
1960). Avoir un compilateur Lisp en Lisp qui produit du code natif, c'est un
projet d'une autre ampleur (SBCL, plusieurs décennies).

## 5. Capot : ce qu'il faudrait pour du vrai selfhost

Pour passer de 15 + 96 lignes à un vrai compilateur selfhosté, il faudrait :

| Étape | Effort estimé | État |
|---|---|---|
| Parser complet en Heaven | 2–3 sessions | partiel (`lib/heaven_parse.hvn`) |
| Type-checker en Heaven | 2–3 sessions | absent |
| Codegen QBE en Heaven | 3–5 sessions | absent |
| Bootstrap (compiler le tout) | 1–2 sessions | absent |
| **Total** | **~10 sessions** | **0 %** |

**Conséquence honnête** : le selfhost de Heaven n'est pas « en cours ». C'est un
**jalon futur** (roadmap dans `_roadmap_v2.md`), et les 15 + 96 lignes actuelles
sont des **preuves de concept** — des briques qui existent pour valider que
Heaven *peut* manipuler son AST, pas pour valider qu'il le fait.

> **Capot final.** Le selfhost est un objectif **à long terme**, pas un état
> actuel. Tant que `heaven parse` appelle `heaven_expr.zig`, le projet n'est
> pas selfhost. Les briques existent, l'édifice non.


## Exercices

### Ex. 1 — Étendre `bin/heaven.hvn` (guidé)

Le fichier fait 15 lignes avec 5 clauses. Ajoutez `fmt` (exit 5) et `bench`
(exit 6). Testez avec `./bin/heaven-natif fmt` (doit exit 5).

**Question** : que se passe-t-il si on passe deux arguments ? `(@argv 1)` ne lit
que le premier — que faudrait-il pour lire le second ?

### Ex. 2 — `heaven_eval` sur une expression (libre)

Chargez `lib/heaven_eval.hvn` dans un test et évaluez `(+ 1 2)` via
`parse → eval`. Le résultat doit être `VInt 3`.

**Indice** : `tests/test_heaven_eval_prims.hvn` fait exactement ça pour chaque
primitive. Copiez le pattern.

### Ex. 3 — Ajouter une primitive (libre)

Ajoutez `string_length` aux 17 primitives de `lib/heaven_eval.hvn`. Trois
changements : `prim_ops`, `eval_apply` case correspondant, test.

**Question** : que se passe-t-il si l'argument n'est pas une `VStr` ? Comment le
gérer sans `panic` ?

### Ex. 4 — Le piège de la frontière (casse)

`lib/heaven_eval.hvn` importe `lib/heaven_parse.hvn`. Si vous remplacez
`lib/heaven_parse.hvn` par le parser Zig (`src/compiler/ast_bridge.zig`),
qu'est-ce qui change ?

**Question** : le binaire `heaven` peut-il utiliser `lib/heaven_eval.hvn` à la
place de `engine_expr.zig` ? Qu'est-ce qui manque pour que ce soit possible ?

---

## Ce qu'il faut retenir

1. **Selfhost ≠ interpréteur** : `heaven_eval.hvn` est un interpréteur,
   `bin/heaven.hvn` est une CLI. Ni l'un ni l'autre n'est un compilateur.
2. **15 + 96 lignes** prouvent que Heaven peut manipuler son AST. Pas plus.
3. **Le compilateur est en Zig.** `heaven parse` appelle `heaven_expr.zig`.
   C'est la frontière à date.
4. **Roadmap selfhost** : ~10 sessions pour un vrai compilateur. Pas commencé.
5. **Piège du vocabulaire** : « selfhost partiel » ne veut rien dire. Soit le
   compilateur s'écrit lui-même, soit il ne le fait pas.

Le chapitre suivant ouvre la voie vers le futur : le langage est **conçu** pour
être selfhosté (les primitives, l'AST, les 6 formes canoniques), mais il ne
l'est pas encore. La différence est importante pour un lecteur qui arrive dans
le projet : ce n'est pas un langage fini, c'est un langage qui **tend** vers
quelque chose.
