# Chapitre 28 — `heaven_eval` : un interpréteur en 96 lignes

> **Piège d'entrée.** `lib/heaven_eval.hvn` fait 96 lignes et évalue des
> expressions Heaven en Heaven. On pourrait croire que c'est le début du
> selfhost — non. C'est un **interpréteur** : il prend un AST déjà parsé et
> le réduit. Il ne parse pas, il ne compile pas, il n'est pas auto-suffisant.
> Ce chapitre montre ce que 96 lignes peuvent faire, et ce qu'elles ne peuvent
> pas.

## 1. L'architecture : trois types, une fonction

`heaven_eval.hvn` repose sur deux `data` et une fonction :

```heaven
data Value = VInt Int | VStr Str | VClosure Str Expr Env
           | VRecClosure Str Str Expr Env | VPrim Str | VListNil | ...

data Env   = EnvNil | EnvCons Str Value Env

eval (HP.ELitI n) env  = (VInt n)
eval (HP.ELitS s) env  = (VStr s)
eval (HP.ESym s) env   = (eval_sym s env)
eval (HP.EApply f a) env = (eval_apply f a env)
eval (HP.ELambda p b) env = (VClosure p b env)
eval (HP.EBind n b) env  = (eval_bind n b env)
```

Trois choses à remarquer :

1. **`Env` est une liste persistante** (`EnvNil`, `EnvCons`). Chaque closure
   capture son environnement par référence — pas de mutation, pas de copie.
2. **`Value` distingue closure et recclosure** : `VClosure` pour `lambda`,
   `VRecClosure` pour les fonctions nommées. La différence est l'**auto-nommage**.
3. **`eval` dispatch sur 6 formes** : `ELitI`, `ELitS`, `ESym`, `EApply`,
   `ELambda`, `EBind`. C'est l'AST de `lib/heaven_parse.hvn` (HP).

La signature `eval : Expr -> Env -> Value` est celle d'un interpréteur
classique — même structure que McCarthy 1960, en 6 lignes de dispatch.

## 2. `eval_apply` : le cœur de l'évaluation

`eval_apply` est la partie la plus dense du fichier. Elle gère **l'application**
d'une fonction à un argument. C'est là que se joue la différence entre
interpréteur et compilateur.

```heaven
eval_apply (HP.ESym "λ") a env = (VLam1 a)
eval_apply (HP.ESym "fn") a env = (VLam1 a)
eval_apply (HP.ESym s) a env =
  (if (= s "if") (VIf1 a) (eval_apply2 (eval_sym s env) a env))
eval_apply f a env = (eval_apply2 (eval f env) a env)
```

Trois cas notables :

1. **`λ` et `fn` explicites** : `(λ x → body)` est reconnu comme une lambda
   en attente d'un second argument (le paramètre).
2. **`if` paresseux** : `(if c t e)` est traité comme une application
   partielle. `VIf1 a` puis `VIf2 c a`, puis `eval_if` décide. C'est du
   **curryfying** d'opérateur pour rester en 2 args max.
3. **Cas général** : `eval_apply2 (eval f env) a env` — on évalue la fonction,
   puis on applique.

### `VRecClosure` : l'auto-nommage

```heaven
eval_bind n (HP.ELambda p b) env = (VRecClosure n p b env)
eval_bind n b env = (eval b env)
```

Quand on lie `f = (λ x → body)`, on ne stocke **pas** une `VClosure`, mais une
`VRecClosure n p b env` où `n` est le nom `f`. Au moment de l'application :

```heaven
eval_apply2 (VRecClosure self p b cenv) a env =
  (eval b (EnvCons self (VRecClosure self p b cenv)
            (EnvCons p (eval a env) cenv)))
```

`self` est **re-lié à lui-même** dans l'environnement de la closure. C'est ce
qui permet la récursion sans `letrec` explicite : le nom `f` est toujours
visible dans le corps de `f`.

## 3. Les 17 primitives

Les primitives sont représentées par `VPrim op` et `VPrim1 op x` (application
partielle). L'arité est **encodée dans le type** : `VPrim "cons"` attend un
argument de plus que `VPrim1V "cons" x`.

| Catégorie | Primitives |
|---|---|
| Arithmétique | `+`, `-`, `*` |
| Comparaison | `=`, `<`, `==`, `!=`, `>`, `<=`, `>=` |
| Listes | `cons`, `head`, `tail` |
| Pairs | `pair`, `fst`, `snd` |
| Strings | `string_concat` |
| Contrôle | `if` |

Total : **17**. Les listes utilisent `VListCons`/`VListNil`, les pairs sont des
alias (`pair = cons`, `fst = head`, `snd = tail`). C'est un choix : les pairs
ne sont pas un type distinct, elles sont des listes de 2 éléments.

## 4. Piège : interpréteur ≠ langage

Voici une question piège : si `heaven_eval.hvn` peut évaluer `(+ 1 2)` et rendre
`VInt 3`, est-ce que Heaven peut s'évaluer lui-même ?

**Réponse courte : non.** Trois raisons :

1. **Le parser est en Zig.** `heaven parse` appelle `heaven_expr.zig`, pas
   `lib/heaven_parse.hvn` (HP). L'évaluateur HP n'est utilisé que dans les
   tests de `heaven_eval.hvn`.
2. **Les 17 primitives sont un sous-ensemble.** Pas de `case`, pas de `data`
   dans l'évaluateur (il consomme l'AST, pas la syntaxe). Un programme Heaven
   réel utilise ces formes — `heaven_eval` ne les évalue pas.
3. **Pas de codegen.** L'évaluateur rend une `Value`, pas un binaire. Pour
   compiler, il faudrait une étape supplémentaire (MIR, QBE, WASM) — voir
   ch. 30 (hors v2).

**Analogie** : `heaven_eval` est au compilateur Heaven ce qu'un émulateur
NES est à un émulateur de PS5. C'est de l'**interprétation**, pas de la
**traduction**.

## 5. Capot : ce que 96 lignes peuvent vraiment faire

Ce que `heaven_eval` fait **bien** :

- Évaluer des expressions arithmétiques et logiques simples
- Gérer les closures et les listes (`cons`, `head`, `tail`)
- Détecter les erreurs (`VErr` pour application invalide, string_concat sur
  non-string, etc.)
- Persister l'environnement (`EnvCons` — pas de mutation, pas de fuite)

Ce que `heaven_eval` ne fait **pas** :

| Limitation | Raison |
|---|---|
| `let` désucré | TODO explicite dans la roadmap |
| `case`/`match` | Pas dans l'AST HP |
| Imports (`@import`) | `EImport` → `VErr "non supportee en .hvn"` |
| TCO | Pas implémenté (stack overflow sur récursion profonde) |
| `@magic` | Non reconnu |
| Multi-args natif | `eval_apply2` est binaire, curry manuel |

**Conséquence** : `heaven_eval.hvn` est un **jouet pédagogique**. Il prouve
que Heaven peut représenter et réduire son propre AST. Il ne prouve **pas**
que Heaven peut être son propre compilateur — c'est le sujet du ch. 27
(« selfhost »), et la réponse reste la même : **non, pas encore**.

> **Capot final.** Ne confondez pas « interpréteur qui évalue Heaven » et
> « compilateur qui compile Heaven ». 96 lignes prouvent la première chose,
> pas la seconde. Le jour où `heaven parse` utilisera `lib/heaven_parse.hvn`,
> on aura un début de selfhost — pas avant.

## Exercices

### Ex. 1 — `eval` sur une expression (guidé)

Évaluez `(+ 1 2)` avec `heaven_eval.hvn` :

```heaven
import "lib/heaven_parse.hvn" as HP
import "lib/heaven_eval.hvn" as HE

HE.eval_file (HP.parse_file (HP.lex "(+ 1 2)")) HE.EnvNil
-- => (VInt 3)
```

**Question** : que se passe-t-il si vous remplacez `(+ 1 2)` par `(+ 1 "a")` ?
Regardez `prim_fin`, ligne par ligne.

### Ex. 2 — Récursion avec `VRecClosure` (libre)

Définissez `fact` dans un fichier `.hvn` :
```heaven
fact n = (if (= n 0) 1 (* n (fact (- n 1))))
```

Évaluez `(fact 5)` avec `heaven_eval`. Le résultat doit être `(VInt 120)`.

**Question** : si vous supprimez la clause `eval_bind n (HP.ELambda p b) env`,
le résultat sera-t-il le même ? Pourquoi ? (Indice : `VRecClosure` vs `VClosure`.)

### Ex. 3 — Ajouter `string_length` (libre)

Ajoutez `string_length` aux primitives de `heaven_eval.hvn` :
1. `prim_ops` : ajouter `"string_length"` à la liste
2. `eval_apply2` : case `(VPrim "string_length")` → `VPrim1V ...`
3. `vstr_concat` : ajouter `vstr_length`
4. Test dans `tests/test_heaven_eval_prims.hvn`

**Question** : que fait `vint_of` sur une `VErr` ? (Indice : `-1`.)

### Ex. 4 — Le piège du parser (casse)

Chargez `lib/heaven_eval.hvn` dans un test et appelez `HP.parse_file` sur :
```heaven
(lambda x -> x)
```

**Question** : que renvoie HP ? Regardez `docs/spec/_runtime_gaps.md` §3 sur
les pièges G.37/G.38/G.39. Pourquoi `heaven_eval` préfère-t-il un AST
hardcodé au lieu d'appeler `HP.parse_file` sur du vrai code ?

---

## Ce qu'il faut retenir

1. **`heaven_eval` = interpréteur** : `Expr → Env → Value`, 6 formes de
   dispatch, 17 primitives. Pas plus.
2. **`Env` est une liste persistante** (`EnvNil`/`EnvCons`). Les closures
   capturent, pas de mutation.
3. **`VRecClosure`** permet la récursion en re-liant `self` à la closure.
   `VClosure` = `lambda` anonyme, `VRecClosure` = nom lié.
4. **17 primitives** — arithmétique, comparaison, listes, pairs, strings, `if`.
   Pas de `case`, pas de `data`, pas d'`@import`.
5. **Interpréteur ≠ compilateur** : 96 lignes prouvent la réduction, pas la
   traduction. Le selfhost reste un jalon futur (ch. 27).

Le chapitre suivant ferme la boucle : après avoir vu l'interpréteur et la
preuve de concept de selfhost, on se demande ce qui manque **concrètement** pour
passer de 96 lignes à un vrai compilateur. Spoiler : beaucoup de choses.
