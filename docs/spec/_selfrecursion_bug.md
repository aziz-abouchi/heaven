<!-- HEAVEN:selfrecursion-bug -->
# Bug : auto-recursion dans if-else retourne une valeur fausse

## Constat

    count n = if (= n 0) then 0 else (count (- n 1))
    (count 0)  -- OK : 0
    (count 1)  -- KO : != 0
    (count 2)  -- KO : != 0

Teste sur HEAD~20 (20510f5) : meme comportement. **Pre-existant**.

## Perimetre

- Fonctions qui appellent **d'autres** fonctions : OK (twice x = inc (inc x)).
- Auto-recursion **hors if** : OK (g n = (g ...) s'enregistre).
- Auto-recursion dans if-else : **KO**.
- Non-tail (avec + 0 autour) : KO aussi. **Ce n'est pas le TCO**.

## Impact

Tout parcours recursif en Heaven :
- DNS parser (dns_qname_end scan de labels).
- JSON parser (nested values).
- HTTP body parser.
- AST walkers.
- BigInt bdiv/bmod (D20 connexe).

## Hypotheses

1. Le binding du parametre n'est pas refait au self-call -> n reste
   a sa valeur initiale -> boucle detectee comme infinie -> retour
   d'une valeur sentinelle.
2. Le TCO (self-tail-call) est mal resolu et renvoie une valeur
   partielle.
3. Le cache d'appel (spine TCO) confond le frame courant et la cible.

## A reproduire

    count n = if (= n 0) then 0 else (count (- n 1))
    test "c1": (count 1) == 0

## Chantier

Session dediee 2-4h. Priorite haute (bloque N2 self-hosting).
Tracer dans engine_expr.zig : evaluer (count 1) en mode debug,
voir si le parametre est bien rebinde lors de l'auto-appel.

## Contournements connus

- Derouler la recursion (bounded, max N niveaux).
- Utiliser une boucle via add_task/schedule (scheduler).
- Ecrire le parser en natif (Zig) et l'appeler via FFI (pas Heaven pur).

## Workaround dns_v1 (non retenu)

Derouler dns_qname_end sur 8 niveaux (couvre QNAME < 255 bytes a
labels courts). Non retenu : masque le bug, ne resout rien pour les
chantiers suivants.


## Indices supplementaires (2026-10-16)

Traces ajoutees a evalFunction + evaluate + evalMagic. Resultat sur
`c4 n = if (= n 0) then 0 else (c4 (- n 1))` :

    [evalFunction] EVAL_ARG c4[0] arg_id=5756     -- litt. 1 passe au test
    [evalFunction] EVAL_ARG_RESULT c4[0] val_id=5756
    [evalFunction] ENTER c4 args_len=1
    [evalFunction] LOOP c4 arg0=5756
    [evalMagic] dispatch c4 env.n=5756            -- env A BIEN n binde
    [evalFunction] EVAL_ARG c4[0] arg_id=5752     -- (- n 1)
    [evaluate] ENTER id=5752 depth=0
    [evaluate] ENTER id=5748 depth=1              -- n
    [evaluate] ENTER id=5751 depth=1              -- 1
    [evaluate] ENTER id=5758 depth=0              -- ???
    (pas de EVAL_ARG_RESULT, pas de 2e ENTER c4)

### Observations

1. Le binding `n=5756` dans l'env du self-call est **correct**.
2. `evaluate(5752)` (= `(- n 1)`) entre mais **ne retourne pas**.
3. `evaluate(5758)` a depth=0 depuis un calcul imbrique — incoherent,
   sauf si le TCO a saute un `evalFunction`.

### Discriminants

| Forme | Resultat |
|---|---|
| `f x = x`, `(f (- 5 1))` | OK |
| `count_lit n = if (= n 0) then 0 else (count_lit 0)` | OK |
| `c4 n = if (= n 0) then 0 else (c4 (- n 1))` | KO |
| `v3 n = if (= n 0) then 0 else (let m = (- n 1) in (v3 m))` | OK |
| `v1 n = if (= n 0) then 0 else (v1 (sub1 n))` | OK |

**Discriminant net** : self-call avec arg = expression **directement**
dans l'apply : KO. Meme expression dans un `let` ou via un helper : OK.

### Hypothese la plus probable

Le TCO_BOUNCE saute l'appel `evalFunction` sous certaines conditions,
ou bien `evalMagic` (branche TCO l.885) reevalue l'arg dans le mauvais
env (`env` au lieu de `new_env`). La trace ne permet pas de trancher.

### Prochaines etapes

1. Instrumenter `evalMagic` TCO l.886 : tracer `env == new_env` ?
2. Instrumenter le retour `TCO_BOUNCE` : qui le consomme ?
3. Tests de bisection sur `evalCmp` / `store.int` sur un Id `-`.

Chantier dedie 2-4h. Bloque N2, JSON, HTTP body, AST walkers.


## Decouverte majeure (2026-10-16)

Traces ajoutees dans le TCO (l.885 engine_expr.zig). Sur :
    c4 n = if (= n 0) then 0 else (c4 (- n 1))

L'argument du self-call est le noeud 5752, un `.apply` avec :
    span[0] = sym "-"       (op)
    span[1] = lit int=0     (devrait etre `n` binde a 1)
    span[2] = apply 5751    (devrait etre le litt. 1)

**La structure `(- n 1)` est corrompue.** `n` est devenu un `lit 0`
et `1` est devenu un `.apply`. C'est un bug de **reecriture d'Id**
(probablement dans `store.substSym` ou l'equivalent TCO), pas
d'evaluation.

Le TCO tente alors `evaluate(5752)` -> `-` recoit `[0, <apply>]`
-> ArityMismatch silencieux.

## Piste precise pour le chantier

1. Chercher qui reecrit les args du self-call dans `evalMagic` TCO.
2. Comparer avec la voie `let m = (- n 1) in (v3 m)` (qui marche).
3. Voir si `store.substSym` (utilise pour beta-reduction) est appele
   ici a tort et reecrit la structure du sous-arbre.
4. Verifier que les Ids 5756 (n binde) / 5748 (lit 0) / 5751 (apply)
   ne sont pas confondus par un reuse d'Id.

## Indice add.

Le TCO trace `env.n=5756`, mais la structure passee a `evaluate` a
`span[1]=5748` (`lit 0`). Donc l'env est correct (n=1), mais le
**sous-arbre a ete altere** avant l'appel. C'est bien une
substitution qui a touche l'AST, pas l'env.


## Impasse (2026-10-16, session 2)

Nouvelles investigations :
- `substSym` (expr.zig:936) semble correct.
- `apply` (expr.zig:1074) avec guard inconditionnel ne signale
  aucun Id invalide -> les Ids sont valides.
- Fix TCO_ARGS_COPY (copie stack-local des args) : aucun effet.
- Le noeud 5752 = `(- n 1)` a `span = [-, lit 0, apply]` au lieu de
  `[-, sym n, lit 1]`. Structure corrompue.

**Hypothese revisee** : la corruption n'est pas a l'evaluation, mais
au **parse**. Le parser produit un AST `[-, lit 0, apply]` pour la
source `(- n 1)`. Verifier le pipeline :

   heaven_expr.parseExpression -> expr_parser.parseExpression ->
   parse.zig (rewriteTupleCommas ?) -> Store

Piste concrete : `rewriteTupleCommas` (commit b4ca12f, aujourd'hui)
injecte `tuple ` apres `(` quand il voit une virgule. Verifier qu'il
ne corrompt pas les sous-arbres en bordure de `(- n 1)`.

**Test discriminant a faire** :
- `count n = if (= n 0) then 0 else (count (- n 1))` -> KO
- `count n = if (= n 0) then 0 else (count (sub1 n))` -> OK
  (avec `sub1 n = (- n 1)`)

Si `sub1` fonctionne et `(- n 1)` inline casse, c'est **le parse**
qui differe entre les deux formulations.

## Cause probable identifiee

`rewriteTupleCommas` (heaven_expr.zig, ajoute ce jour) parse le
source en scannant les `(`. Il **insere `tuple `** apres un `(`
quand il rencontre une virgule a profondeur 1. Sur `(- n 1)` sans
virgule, il ne devrait rien faire. Mais il peut corrompre des cas
subtils (si le source contient `(if ... (...))`).

**ACTION** : tester le bug sur le commit precedent b4ca12f (avant
rewriteTupleCommas). Si le bug **n'existe pas** avant, c'est une
regression immediate.

## Prio

Session dediee 2-4h. Le bug peut etre une regression introduite ce
jour. Premier test : git stash + checkout b3ac888 + reproduire.


## DIAGNOSTIC FINAL (2026-10-19) — le bug est dans le PARSER, pas le moteur

Toutes les hypothèses precedentes (substSym, AST corrompu, TCO args
dangling) sont INFIRMEES. Test discriminant decisif :

| Forme | Self-call | Resultat |
|---|---|---|
| `(if c a b)` avec parens externes | oui, arg calcule | ✅ OK |
| `if c then a else b` (infixe) | aucun | ✅ OK |
| `if c then a else b` (infixe) | oui, via helper `(sub1 n)` | ✅ OK |
| `if c then a else b` (infixe) | oui, arg direct `(- n 1)` | ❌ KO |
| `(if c then a else b)` (mixte) | oui | ❌ ArityMismatch |

**Conclusion** : le bug est dans le desugare `if ... then ... else`
de `src/core/parse.zig:574-577`. Ce site :
1. Extrait `cond_str`, `then_str`, `else_str` par sous-strings.
2. Appelle `parseSExpr` sur chacune.
3. Reconstruit `store.call("if", [c, t, e])`.

Quand `else_str` contient un self-call avec arg calcule
(`(c4 (- n 1))`), le `parseSExpr` produit une structure incorrecte —
peut-etre parce que `(- n 1)` est traite differemment quand c'est
une sous-string deja extraite vs un S-expr complet.

**Pourquoi `(sub1 n)` marche** : `parseSExpr` sur `(sub1 n)` produit
un apply simple sans imbrication. Le bug ne se declenche qu'avec
des arguments calcules imbriques.

**Pourquoi `(if c a b)` avec parens externes marche** : le desugare
NE S'ENCLENCHE PAS. Le parser voit `(if` d'abord et traite comme
S-expr natif. Tout est correct.

**Pourquoi `(if c then a else b)` casse** : le desugare s'enclenche
PAS non plus (parens externes), donc `then` et `else` sont passes
comme arguments litteraux a `if` → ArityMismatch (5 args au lieu
de 3). Cas separe, non bloquant, fix trivial (detecter then/else
dans le S-expr natif ou interdire cette forme).

## Fix probable

**Option A (recommandee)** : remplacer le desugare par sous-strings
par un parsing tokenise natif. `parseSExpr` doit traiter `if` comme
mot-cle special : lire condition jusqu'a `then`, branche then jusqu'a
`else`, branche else jusqu'a fin. Une seule voie, pas de
reconstruction.

**Option B (minimale)** : forcer des parentheses autour de chaque
branche avant de rappeler `parseSExpr` :
    `if c then a else b` -> `(if c (a) (b))`
Necessite de re-tokeniser et d'equilibrer les parentheses.

**Option C (quick fix)** : dans le desugare, si `else_str` commence
par `(` et finit par `)`, retirer les deux et parser l'interieur.
Fragile, ne gere pas les imbrications.

Effort estime : 1 a 2 h pour Option A, tests de regression
obligatoires (les 6 cas du tableau).

## Tests de regression a ajouter

    -- dans tests/test_parser.hvn ou nouveau fichier
    test "if_infixe_selfcall": (count n = if (= n 0) then 0 else (count (- n 1))) ...
    test "if_infixe_no_selfcall": ...
    test "if_infixe_helper": ...
    test "if_parens_selfcall": ...

## Ce qui est FAUX dans les sections precedentes

- "AST corrompu par substitution" : non, l'AST est correct ; c'est
  le parse en amont qui produit une structure incorrecte.
- "substSym dans TCO" : non, substSym n'est pas en cause.
- "TCO args dangling" : non, la copie stack-local n'a rien change.

Ces sections sont conservees pour tracage historique mais sont
INFIRMEES. Seul le diagnostic final compte.

## Impact debloque

Une fois ce fix :
- Bug selfrecursion resolu (bloquant N2).
- Interpreteur metacirculaire Heaven (lib/heaven_eval.hvn) peut
  accepter la syntaxe de surface `if then else` — actuellement il
  marche seulement avec `(if c a b)` (cf. les commentaires
  "style une ligne, patterns plats" dans le fichier).
- JSON, HTTP body, AST walkers debloques.

## Priorite

**P0** apres le week-end. Effort 1-2h. Fix parser, pas de refactor
moteur. Le script `scripts/debug-selfrecursion.sh` reste utile pour
reproduire.
