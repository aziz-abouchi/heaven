# Chapitre 28 — Mémoire : QTT, la spécification qui n'est pas (encore) un vérificateur

> **Piège d'entrée.** Vous avez lu le ch. 3 (« QTT spec/runtime »), et vous vous
> attendez à ce que le ch. 28 vous montre comment Heaven libère la mémoire.
> **Il ne le fera pas**, parce que Heaven ne le fait pas encore. La syntaxe QTT
> est reconnue par le parser, les types sont propagés, mais **aucun vérificateur
> de multiplicité n'est branché sur le pipeline**. Ce chapitre explique QTT, ce
> qu'il promet, et pourquoi la promesse n'est pas tenue.

## 1. Le problème : qui libère ?

Un langage fonctionnel pur alloue. `map f xs` produit une nouvelle liste.
`filter p xs` une autre. Sans précaution, il y a deux options :

| Option | Coût | Prévisibilité |
|---|---|---|
| **GC** (Haskell, OCaml, JS) | variable (pauses) | faible |
| **Refcount** (Swift, ObjC) | constant mais cher | élevée |

QTT (*Quantitative Type Theory*, Atkey 2018) propose une **troisième voie** :
la signature du type **dit** qui possède quoi. Si `f : A → B` est linéaire, le
runtime sait qu'il doit libérer `A` après l'appel, et qu'aucune copie n'est
nécessaire. Pas de GC, pas de refcount, pas de fuite — **en théorie**.

> **État réel (2026-10-26).** La syntaxe `let linear x = ...` est reconnue par
> le parser. Les types `.linear` / `.erased` / `.many` sont présents dans
> `types.zig`. Mais **aucun check n'est fait** sur le nombre d'usages réels.
> `LinearChecker` est branché sur `cmdQTT` shell uniquement, pas sur le
> pipeline d'élaboration. Un `let linear x = 42 in x + x` (violation) passe
> **sans erreur**.

## 2. Les trois multiplicités en Heaven

Syntaxe actuelle (testée via `heaven run`) :

```heaven
let erased proof = (big_computation 0) in 42   -- proof jamais lu
let linear x = 42 in x + 1                     -- x utilisé une fois
let many x = 42 in x + x                       -- x utilisé deux fois
```

Les trois formes s'analysent et s'évaluent, **sans contrainte** :

```
heaven> let linear x = 42 in x + 1
"43"
heaven> let erased proof = 99 in 42
"42"
heaven> let many x = 42 in x + x
"84"
```

**Attention** : `let linear x = 42 in x + x` (deux usages, violation de
linéarité) passe **aussi** sans erreur. C'est exactement ce que « pas enforced »
signifie. La syntaxe est correcte, le runtime ne vérifie rien.

## 3. Erasure : la promesse à coût zéro

Le régime `erased` est le plus ambitieux : un terme marqué `erased` **n'existe
pas au runtime**. Il est utilisé uniquement pour la vérification (par exemple,
une preuve de taille sur un `Vec`), et le compilateur doit l'éliminer.

```heaven
let erased proof = (proof_of_length n xs) in
  head (Vec n+1 xs')
```

`proof` est une preuve, pas une donnée. Après vérification, elle disparaît.
`head` ne coûte rien de plus que le `head` non prouvé.

**Ce que ça donne en pratique** : zéro octet alloué, zéro cycle CPU. C'est le
vrai intérêt de QTT — faire payer les preuves une fois, à la compilation, et
plus jamais à l'exécution.

**Ce que ça donne en Heaven (2026-11-05)** : rien. `erased` est reconnu comme
mot-clé, mais le terme est évalué **normalement**. Si `(proof_of_length n xs)`
alloue, l'allocation a lieu. Pas de passe d'érasure.

## 4. Ownership linéaire : pas de refcount, pas de GC

Un terme `linear` a **exactement un propriétaire** à tout instant. Si on le
passe à une fonction, on ne peut plus l'utiliser. Si on le copie, on doit le
consommer. C'est le même modèle que Rust, mais **dans le type**, pas dans le
binder.

**La promesse** : le compilateur peut insérer un `free` après le dernier usage
sans ambiguïté. Pas de fuite, pas de double-free.

**La réalité Heaven** : aucun `free` inséré. Le GC fait le travail (quand il
fonctionne — voir ch. 12, bigint, et les fuites connues). `linear` est un
**commentaire**, pas une contrainte.

## 5. Drop-reuse : réutiliser sans copier

Le cas le plus concret de QTT : `(++)` sur deux listes linéaires. Si `xs` est
linéaire, `(++) xs ys` peut **réutiliser les cellules de `xs`** au lieu de les
copier.

```heaven
(++) linear xs ys =
  match xs with
  | Nil -> ys
  | Cons x rest -> Cons x ((++) rest ys)
```

Si `xs` est linéaire, chaque `Cons` est consommé une fois, `rest` aussi. Le
runtime peut libérer les cellules de `xs` au fur et à mesure — sans copie.

**La réalité Heaven** : `(++)` copie. Pas de passe de drop-reuse. Le code
fonctionne (les tests passent), mais le coût mémoire est linéaire en la taille
de `xs`, pas constant.

## 6. Ce qui marche aujourd'hui (2026-11-05)

Voici l'état réel, sans complaisance :

| Fonctionnalité QTT | Parser | Type | Runtime | Test |
|---|---|---|---|---|
| `let erased x = ...` | ✅ | ✅ `.erased` | ⚠️ évalué normalement | partiel |
| `let linear x = ...` | ✅ | ✅ `.linear` | ❌ aucune contrainte | partiel |
| `let many x = ...` | ✅ | ✅ `.many` | ✅ comportement habituel | partiel |
| **Vérification de linéarité** | ❌ | ❌ | — | ❌ |
| **Érasure (passe runtime)** | ❌ | — | ❌ | ❌ |
| **Drop-reuse** | ❌ | — | ❌ | ❌ |
| **`LinearChecker` dans le pipeline** | — | ❌ | — | ❌ |

**Ce qui existe vraiment** :

- Les mots-clés `linear` / `erased` / `many` sont reconnus par le parser
- Les multiplicités sont propagées dans les types (`types.zig:145`)
- Un `LinearChecker` existe (`types.zig:145`), mais **branché uniquement** sur
  `cmdQTT` shell — pas dans le pipeline `elab`

**Ce qui n'existe pas** :

- Aucune erreur levée sur une violation de linéarité
- Aucune érasure à l'exécution
- Aucune réutilisation de cellules (drop-reuse)
- Aucun test automatisé de violation (parce que le check n'existe pas)

**Conséquence** : QTT est **une syntaxe et un type-checker partiel**, pas un
mémoire manager. Le jour où `LinearChecker` sera branché sur `elab`, on aura
un début de QTT réel — pas avant.

## 7. Piège : QTT ≠ langage linéaire

On pourrait croire que QTT = Rust. Faux. Rust a un borrow checker à
**l'exécution du compilateur**, avec des lifetimes explicites. QTT a des
**multiplicités dans le type**, et laisse au runtime le soin de décider quand
libérer. Ce sont deux modèles différents :

| Modèle | Vérifie | Libère | Quand |
|---|---|---|---|
| **Rust** | borrow checker (compilateur) | `Drop` (runtime) | à la fin de portée |
| **QTT** | multiplicités (compilateur, si branché) | `free` inséré (codegen) | au dernier usage |
| **Heaven** | rien | GC (partiel) | jamais / aléatoire |

**Analogie** : Rust est un comptable qui vérifie chaque ligne. QTT est un
notaire qui signe un contrat de propriété. Heaven aujourd'hui est un notaire
qui **signe sans lire** — la forme est correcte, la garantie non.

## 8. Capot : ce qu'il faudrait pour du vrai QTT

Le chemin vers QTT réel, en 4 étapes :

| Étape | Effort | État |
|---|---|---|
| **Brancher `LinearChecker` sur `elab`** | 1 session | absent |
| **Ajouter les tests de violation** (au moins 3 cas) | 1 session | absent |
| **Passe d'érasure au codegen** | 2–3 sessions | absent |
| **Drop-reuse** (optimisation) | 3–5 sessions | absent |
| **Total** | **~7 sessions** | **0 %** |

**Rappel** : QTT est **une direction**, pas un acquis. Les chapitres 3 (types),
12 (bigint), 24 (hab) reposent sur QTT en surface, mais leurs tests passent
**sans** vérification de multiplicité — le GC fait le travail, comme avant.

> **Capot final.** Si vous retenez une chose : **la syntaxe n'est pas la
> sémantique**. `let linear x = 42 in x + x` compile. Ce n'est pas un bug —
> c'est l'état du projet. Le jour où ce sera un bug, on aura un vérificateur.

## Exercices

### Ex. 1 — Vérifier que `linear` n'est pas enforced (guidé)

Écrivez un fichier `.hvn` :
```heaven
test "linear_violation": (let linear x = 42 in x + x) == 84
```

Lancez `heaven --run-test`. Le test passe (car aucune contrainte n'est imposée).
**Question** : que faudrait-il pour que ça **échoue** ? Décrivez le check en
3 lignes de pseudo-code.

### Ex. 2 — `LinearChecker` existe, mais où ? (libre)

Trouvez `LinearChecker` dans `src/core/types.zig`. Regardez ce qu'il vérifie
**réellement**. Regardez qui l'appelle (`grep -rn "LinearChecker" src/`).

**Question** : combien de sites d'appel ? Sont-ils dans le pipeline
`elab` / `compile` ou seulement dans `cmdQTT` shell ?

### Ex. 3 — Écrire un test de violation (libre)

Ajoutez un test à `tests/test_qtt.hvn` (s'il existe) ou créez-le :
```heaven
-- Ce test DOIT échouer quand QTT sera enforced
test "linear_violation_expected_fail":
  (let linear x = 42 in x + x) == 84
```

Le test **passe** aujourd'hui. Documentez dans un commentaire : « doit échouer
après branchement de LinearChecker ». C'est un test de dette.

**Question** : à quel endroit du pipeline faudrait-il brancher le check pour
que ce test échoue ?

### Ex. 4 — Le piège de la syntaxe (casse)

`let erased proof = (big_computation 0) in 42` est accepté et rend `42`. Mais
`big_computation` est **exécuté** — l'`erased` n'est pas érasé.

Écrivez `big_computation` qui affiche un message (`@print "computing"`), et
testez :
```heaven
test "erased_not_erased": (let erased proof = (big_computation 0) in 42) == 42
```

**Question** : voyez-vous `"computing"` ? Si oui, l'érasure n'est pas faite —
c'est exactement le point du chapitre.

---

## Ce qu'il faut retenir

1. **QTT = spécification, pas implémentation**. La syntaxe existe, le check
   n'existe pas.
2. **`linear` / `erased` / `many`** sont des mots-clés reconnus. Ils n'imposent
   **rien** au runtime aujourd'hui.
3. **`LinearChecker` existe** (`types.zig:145`) mais n'est **pas branché** sur
   `elab`. Il est appelé uniquement par `cmdQTT` shell.
4. **Le chemin vers QTT réel** : ~7 sessions (brancher check, ajouter tests
   violation, érasure codegen, drop-reuse).
5. **Syntaxe ≠ sémantique** : un `let linear x = 42 in x + x` compile. Ce n'est
   pas un bug, c'est l'état du projet.

Le chapitre suivant conclut le livre v2 : où en est Heaven, ce qui marche, ce
qui est cible, et pourquoi le langage **tend** vers quelque chose de précis.
