# Let : syntaxe et unification

**Date** : 2026-10-14
**Statut** : analyse. Aucune implementation.
**But** : clarifier pourquoi le mot-cle let a plusieurs dialectes,
trancher la forme canonique, preparer l'unification.

## Constat

Le mot-cle let est reconnu par au moins trois chemins distincts :

| Chemin | Fichier | Regle |
|---|---|---|
| S-expr | parse.zig:496 | op=let et num_parts >= 3 |
| Infixe court | parse.zig:325 | prefix "let " (5 chars) |
| Infixe long | expr_parser.zig:670 | let IDENT = VALUE in BODY |
| Infixe alternatif | expr_parser.zig:690 | pattern different |
| Infixe alternatif 2 | expr_parser.zig:717 | encore un |

## Resultats empiriques (2026-10-14)

| Forme | Inline | Multiline |
|---|---|---|
| (let x 1 x) | OK | OK |
| (let x 1 in x) | KO | KO |
| (let x 1 in (let y 2 in ...)) | OK | OK |

La regle sous-jacente n'est pas documentee. Elle est vecue
comme une incoherence.

## Forme cible (a trancher)

### Option A : S-expr pur
(let IDENT VALUE BODY). Uniforme, mais verbeux pour des
chaines longues.

### Option B : Infixe Haskell (RECOMMANDE)
let x = 1 in body
let x = 1
    y = 2
in body
Le parser expr_parser.zig:673 attend deja cette forme
(items[3] == "=" and items[5] == "in"). Coherent avec
D18 (Haskell multi-ligne) et if/then/else.

### Option C : Les deux, S-expr tolere comme fallback
A et B acceptes. Plus permissif, mais perpetue l'ambiguite.

**Recommandation** : B, avec A tolere en lecture pour la
compatibilite bootstrap.

## Breaking changes si B

- Tous les tests .hvn avec (let x 1 body) a migrer.
- test_scheduler.hvn, test_preemptive.hvn, test_effects*.
- Le WASM parser et le tree-sitter grammar.
- Documentation (book, exemples).

## Tests de conformite a creer

- (let x = 1 in x) == 1
- (let x = 1 in (let y = 2 in x + y)) == 3
- Multi-binding : let x = 1 y = 2 in x + y
- Shadowing : (let x = 1 in (let x = 2 in x)) == 2
- Formes rejetees : (let x 1 x) si B strict.

## Etapes

1. Spec (cette session) : documenter, cartographier.
2. Session dediee : implementer B, migrer les tests.
3. Deprecation : si C, retirer progressivement le S-expr.

## Hors scope

- letrec, where, do : formes connexes, a traiter separement.
- Pattern matching dans let : chantier separe.

## Etat 2026-10-15 — let-infixe operationnel

Test `/tmp/t_let.hvn` (6 cas) : **5/6 verts**.

### Formes supportees

| Forme | Etat |
|---|---|
| `(let x 1 x)` S-expr 3-args | OK |
| `(let x = 1 in x)` infixe inline | OK |
| `(let x = 1 in\n x)` multiligne | OK |
| `let x = 1 in x` sans parens | OK |
| `(let x = 1 in (let y = 2 in ...))` chaine | OK |
| `let x = 1 y = 2 in body` multi-binding | KO |

### Decision

Les formes B (infixe Haskell) et C (les deux) de la spec sont
**operationnelles**. La forme multi-binding dans un seul `let`
n'est PAS supportee — la chaine se fait par imbrication, ce qui
est plus simple a parser et aussi lisible.

### Implementation

- `parse.zig:496` : branche S-expr 3-args (avec et sans `=`).
- `expr_parser.zig:673` : infixe QTT (`let linear/many/erased`).
- `expr_parser.zig:690` : infixe `let x = v in body` standard.
- Le multi-binding single-let n'est pas traite — chaque `let`
  ouvre une nouvelle portee.
