# Chapitre 31 — SICP, quarante ans plus tard

> **Piège d'entrée.** Structure and Interpretation of Computer Programs
> (Abelson & Sussman, 1985) a posé trois idées qui ont l'air d'exercices
> de style, et qui sont en réalité des **choix architecturaux** : la
> dérivation symbolique, les machines à registres avec contrôle explicite,
> et la programmation logique. Heaven implémente les trois. Le livre v2
> ne les avait pas racontées. C'est l'objet de ce chapitre.

## 1. Dérivation symbolique : `derive`

SICP chapitre 2.3.2 pose une question simple : peut-on écrire une
fonction `deriv` qui prend une **expression algébrique** et une
**variable**, et rend une autre expression ? Pas une valeur numérique,
pas une approximation : **une expression symbolique**.

Heaven a `derive` dans le noyau. Test (`core/test_suite.hvn:7`) :

```heaven
test "derive_x2": (derive x^2) == (* 2 x)
test "derive_sum": (derive (+ x 3)) == 1
```

`(derive x^2)` rend `(* 2 x)`, une **nouvelle expression**.
`(derive (+ x 3))` rend `1`. Le résultat est un arbre, pas un float.

Comment ça marche ? `derive` est une fonction récursive sur la structure
de l'expression :

- `derive x` → `1` (dérivée de la variable)
- `derive (const c)` → `0` (dérivée d'une constante)
- `derive (+ a b)` → `(+ (derive a) (derive b))` (règle de la somme)
- `derive (* a b)` → `(+ (* (derive a) b) (* a (derive b)))` (règle du produit)
- `derive (^ a n)` → `(* n (* (^ a (- n 1)) (derive a)))` (règle de puissance)

Le second test illustre l'autre moitié du problème :

```heaven
test "simplify_0_add": (simplify (+ x (+ 0 x))) == (* 2 x)
```

`simplify` élimine les `(+ e 0)`, `(* e 1)`, `(* e 0)`, `(+ e e)` redondants.
C'est indispensable : sans simplification, `derive (* 2 x)` produit
`(+ (* 0 x) (* 2 1))`, correct mais illisible.

**Ce qui est absent du livre v2 avant ce chapitre** : `derive` et
`simplify` n'apparaissaient nulle part. Le code existe
(`core/test_suite.hvn:7-9`), mais le lecteur ne savait pas que Heaven
avait un moteur de calcul symbolique.

> **Capot pratique.** `simplify` n'est pas magique. Elle doit être
> **idempotente** (`simplify (simplify e) == simplify e`) et **correcte**
> (`simplify e` a la même valeur que `e`). Les deux propriétés sont
> testées (`core/test_suite.hvn`), mais un bug dans l'une des deux règles
> (`+ 0`, `* 1`, `* 0`) se propage silencieusement dans toute dérivation.

## 2. Programmation logique : `query` et `@prolog_*`

SICP chapitre 4.4 pose une deuxième question : peut-on écrire une base
de faits et de règles, et **demander** au système quelles solutions
satisfont une requête ? Pas une fonction à appeler, pas une boucle à
écrire : **une déclaration**.

Heaven a **deux** implémentations, pour deux cas d'usage :

- **Kanren** (`lib/heaven_propagator.hvn`) : unify + propagation.
  Syntaxe `(query pred arg1 arg2 ...)`.
- **Prolog** (`prolog.zig`) : SLD basique sur clauses linéaires.
  Syntaxe `(@prolog_fact pred args)` et `(@prolog_query pred args)`.

Les deux retournent un **nombre de solutions**, pas un binding. C'est
une différence majeure avec SICP qui renvoie un stream de substitutions.

```heaven
-- Kanren : nombre de solutions à (test_mortel ?)
test "kanren_socrate": (query test_mortel Socrate) == 1
test "kanren_aristote_absent": (query test_mortel Aristote) == 0
test "kanren_wildcard": (query test_2args _ _) == 2
```

```heaven
-- Prolog : faits + requête
(@prolog_fact test_mortel socrate)
(@prolog_fact test_mortel platon)
test "prolog_socrate": (@prolog_query test_mortel socrate) == 1
```

**Pourquoi deux ?** Kanren gère l'**unification** (variables libres,
propagation), Prolog gère la **résolution SLD** (règles, clauses).
SICP ch. 4.4 fait les deux dans un seul `query`. Heaven les a séparés
pour deux raisons : Kanren est plus expressif sur les contraintes
(unification, propagation), Prolog est plus rapide sur les bases de
faits simples (SLD, cut possible).

> **Capot.** Les deux implémentations sont **incomplètes** : pas de cut
> dans Prolog, pas de négation, pas de SLD général. Une règle
> `grandparent X Z :- parent X Y, parent Y Z` marche, mais une règle
> récursive avec coupure ne marche pas. Le chapitre 7 (modules) renvoie
> à ces magics ; ce chapitre donne les deux syntaxes, pas la sémantique
> complète.

## 3. Récursion sans nom : `VRecClosure`

SICP chapitre 4.1.3 pose une troisième question : **peut-on écrire une
fonction récursive sans jamais nommer la fonction elle-même** ? La
réponse classique est le combinateur Y :

    Y = λf. (λx. f (x x)) (λx. f (x x))
    Y f = f (Y f)

Heaven n'expose **pas** `Y` en surface. Mais son évaluateur métacirculaire
utilise un mécanisme équivalent : `VRecClosure`. Quand on écrit
`let f = (lambda x -> … f …) in …`, le binding ne crée pas une `VClosure`
ordinaire, mais une `VRecClosure n p b env` où `n` est le nom `f`. Au
moment de l'application (`lib/heaven_eval.hvn`) :

```heaven
eval_apply2 (VRecClosure self p b cenv) a env =
  (eval b (EnvCons self (VRecClosure self p b cenv)
            (EnvCons p (eval a env) cenv)))
```

`self` est **re-lié à lui-même** dans l'environnement de la closure. C'est
le fixpoint de SICP, encodé dans la structure de données au lieu d'être
une expression. `VRecClosure self p b cenv` joue le rôle de `(Y f)` :
à chaque appel, `self` pointe vers la même closure.

> **Capot.** `VRecClosure` **n'est pas** le Y combinator de Church. C'est
> un fixpoint de **premier ordre**, câblé dans l'évaluateur, qui ne
> fonctionne que pour les fonctions nommées (`let f = …`). Le vrai `Y`
> est un terme du langage, applicable à **n'importe quelle** lambda. Si
> vous voulez écrire `Y` en Heaven, il faut passer par un codage
> explicite, et il ne sera pas typable sans `fix` primitif.

## 4. Machines à registres : MIR

SICP chapitre 5 pose la dernière question : peut-on **expliciter le
contrôle** d'un évaluateur, c'est-à-dire décrire son exécution comme une
machine à registres avec des sauts conditionnels et des étiquettes ?
SICP le fait pour Scheme (`explicit-control evaluator`). Heaven le fait
pour Heaven : c'est le MIR (`src/core/mir.zig`, ~20 instructions).

Une fonction MIR est une suite de `BasicBlock`. Chaque bloc est un
`ArrayListUnmanaged(Instr)` qui se termine par un `terminator` (jump,
branch, ret, fallthrough). Les instructions sont :

```heaven
const_int, const_str, add, sub, mul, div, cmp_lt, cmp_eq,
jump, branch, ret, phi, load, store, alloc, load_at, store_at,
call_user, extern_call
```

C'est **exactement** l'`explicit-control evaluator` de SICP : registres
numérotés (`Reg`), comparaisons, sauts, appels. La différence est que
Heaven le fait en Zig pour le compilateur (`mir.zig`) et en Heaven pour
l'évaluateur métacirculaire (`heaven_eval.hvn`, `VRecClosure`).

Les mêmes instructions servent deux backends (`bench/run.sh`) :

- **QBE** (`mir_qbe.zig`) → binaire natif (x86-64, ARM, RISC-V)
- **WASM** (`mir_wat.zig`) → WebAssembly

`bench/progs/` contient six programmes (`arith`, `count_down`, `fib`,
`loop`, `mutual`, `triple`) qui passent par les trois backends
(interpréteur, QBE, WASM) avec le même résultat. Le chapitre 30
(conclusion) renvoie à ces tests.

> **Capot.** MIR est un **sous-ensemble**. Pas de GC, pas de closure
> enregistrée, pas de types dans les registres (tout est `i64`). Ce
> n'est donc pas un compilateur général, c'est un `explicit-control
> evaluator` pour un sous-ensemble. SICP ch. 5 est aussi un
> sous-ensemble (Scheme sans `call/cc`), mais Heaven le dit.

## 5. Ce que SICP a laissé aux autres chapitres

Trois idées de SICP sont traitées ailleurs dans le livre v2, et ce
chapitre ne les répète pas :

- **Delay / force / streams** (SICP ch. 3.5) : chapitre 11 (`11-streams.md`).
  `SNil | SCons a (Stream a)` est l'équivalent de `(cons-stream a b)`.
- **Effets / CPS explicite** (SICP ch. 4.3, amb) : chapitre 17
  (`17-handlers.md`). `perform` + `handle_rec` est un CPS délimité.
- **Évaluateur métacirculaire** (SICP ch. 4.1) : chapitre 28
  (`28-eval.md`). `heaven_eval.hvn` est un `eval` Scheme-like en Heaven.

## 6. L'évaluateur métalinguistique : de SICP ch. 4 à `heaven_eval`

SICP ch. 4.1 pose l'évaluateur comme un programme parmi d'autres :
`eval` dispatch sur la syntaxe, `apply` applique une procédure. Le
chapitre 28 a montré la version 96 lignes ; cette section relie les deux.

Côté SICP :

    (define (eval exp env)
      (cond ((self-evaluating? exp) exp)
            ((variable? exp) (lookup-variable-value exp env))
            ((application? exp)
             (apply (eval (operator exp) env)
                    (list-of-values (operands exp) env)))
            ...))

    (define (apply procedure arguments)
      (cond ((primitive-procedure? procedure)
             (apply-primitive-procedure procedure arguments))
            ((compound-procedure? procedure)
             (eval-sequence (procedure-body procedure)
                            (extend-environment ...)))))

Côté Heaven (`src/core/heaven_expr.zig`, `engine_expr.zig`) :

    eval  : Id  -> Engine!Id
    apply : Id, args -> Engine!Id

La différence structurelle : SICP manipule des **valeurs Scheme**
directement, Heaven manipule des **`Id`** (index dans un `Store`
hash-consé). L'égalité structurelle devient gratuite (deux
`Cons 1 Nil` construits séparément partagent le même Id), mais
l'évaluation doit consulter le store à chaque nœud.

Voir `28-eval.md` pour la version 96 lignes, `27-selfhost.md` pour
le chemin vers l'auto-hébergement.

## 7. De `analyze` à l'effacement QTT

SICP exercice 4.1 demande d'écrire `analyze` : une fonction qui prend
une expression et retourne une procédure d'exécution pré-compilée.

    (define (analyze exp)
      (cond ((self-evaluating? exp)
             (analyze-self-evaluating exp))
            ((definition? exp)
             (analyze-definition exp))
            ...))

    (define (analyze-self-evaluating exp)
      (lambda (env) (eval exp env)))

L'idée : transformer l'arbre en une closure qui capture la sémantique.
Plus d'`eval` à chaque appel, plus de dispatch dynamique sur le type.

Heaven implémente cette idée sous une autre forme : **QTT erasure**.
Un paramètre marqué `erased` (multiplicité 0) n'est pas passé à
l'exécution. Le compilateur construit une version du corps sans les
paramètres effacés, et cette version est exécutée à chaque appel.

    -- Source
    f (erased n : Nat) (x : Int) = x + 1

    -- Après erasure
    f (x : Int) = x + 1

C'est `analyze` à une autre échelle : SICP compile *l'expression*,
QTT efface *le paramètre*. Les deux visent le même objectif —
supprimer le dispatch dynamique là où le type permet de le faire.

Voir `29-memoire.md` pour QTT.

## 8. De `amb` aux effets algébriques

SICP ch. 4.3 introduit `amb`, l'opérateur qui retourne un choix
non-déterministe :

    (define (require p)
      (if (not p) (amb)))

    (define (prime-sum-pair list1 list2)
      (let ((a (an-element-of list1))
            (b (an-element-of list2)))
        (require (prime? (+ a b)))
        (list a b)))

`amb` est implémenté par des continuations : chaque choix capture le
reste du calcul comme une continuation, qu'on peut rappeler pour
essayer une autre branche.

Heaven n'a pas `amb`. Il a `perform` et `handle_rec` (chapitres 17,
18). C'est plus général : un effet algébrique déclare une opération,
et un handler la résout avec `resume`. `amb` est un cas particulier —
un handler qui, à chaque `perform "choose" ()`, relance le calcul
avec la continuation `k` sur l'autre branche.

    -- amb, traduit en effet algébrique
    choose _ = perform "choose" ()
    fail   _ = perform "fail" ()

    -- handler qui implémente le backtracking (cf. ch. 18)

La section 3 de ce chapitre (`VRecClosure`) couvre le côté récursif ;
cette section couvre le côté non-déterministe. Les deux sont des
héritages directs de SICP ch. 4.

## Exercices

### Ex. 1 — `derive` à la main (guidé)

Sans appeler `derive`, écrivez les règles pour `x`, `(const c)`, `(+ a b)`,
`(* a b)`. Testez `(derive (+ (* x x) 3)) == (+ (* 1 x) (* x 1))`.
**Question** : `simplify` réduit-elle à `(* 2 x)` ? Pourquoi ?

### Ex. 2 — `kanren` vs `prolog` (libre)

Écrivez une base de faits `parent` (`Socrate → Platon → Aristote`), puis
`(query parent Socrate)` et `(@prolog_query parent Socrate)`.

**Question** : les deux donnent `1` (le nombre de solutions). Comment
faire pour obtenir le **nom** du fils, pas juste le compte ?

### Ex. 3 — `Y` explicite (libre)

Écrivez le Y combinator en Heaven (`let Y = lambda f -> …`). Testez
`(Y (lambda fact -> (lambda n -> (if (= n 0) 1 (* n (fact (- n 1))))))) 5`.

**Question** : `Y` est-il typable dans Heaven ? Pourquoi ?

### Ex. 4 — MIR vs `explicit-control evaluator` (casse)

Lisez `src/core/mir.zig` (union `Instr`). Comptez les instructions.
Comparez avec SICP ch. 5.6 (`explicit-control evaluator`).

**Question** : quelles instructions de SICP sont **absentes** de MIR ?
Lesquelles sont **en plus** ?

## Ce qu'il faut retenir

1. **`derive`** : Heaven a un moteur de calcul symbolique. `simplify` doit
   être idempotente et correcte.
2. **`query` / `@prolog_*`** : deux implémentations logiques, deux cas
   d'usage (unification vs SLD). Les deux renvoient un **compte**, pas
   un binding.
3. **`VRecClosure`** : fixpoint de premier ordre, câblé dans l'évaluateur.
   Pas le `Y` de Church, mais le même rôle.
4. **MIR** : `explicit-control evaluator` pour un sous-ensemble (i64, pas
   de GC, pas de closure). Deux backends (QBE, WASM) sur les mêmes
   instructions.
5. **SICP, 40 ans après** : trois idées (symbolique, registres, logique)
   qui restent des **choix architecturaux**, pas des exercices de style.

## Voir aussi

- `docs/spec/_sicp_lineage.md` — table de correspondance complète
  SICP ch. 1-5 → modules Heaven, avec ce que Heaven ajoute et ce
  qu'il perd.
- `28-eval.md` — l'interpréteur 96 lignes (SICP ch. 4.1).
- `27-selfhost.md` — le chemin vers l'auto-hébergement.
- `17-effects.md`, `18-handlers.md` — effets algébriques (SICP 4.3).
- `29-memoire.md` — QTT et effacement (SICP 4.1.6 `analyze`).
