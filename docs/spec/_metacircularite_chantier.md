<!-- HEAVEN:metacircularite -->
# Metacircularite Heaven — chantier (constat 2026-10-19)

## Etat actuel

Briques existantes (Heaven pur) :
- `lib/heaven_parse.hvn` (180 l.) : lexer + parser fusionne. Gere
  `test`, `import`, `data`, `def`. Produit `ELitI`, `ELitS`, `ESym`,
  `EApply`, `ELambda`, `EBind`, **`EData`**.
- `lib/heaven_eval.hvn` (60 l.) : evaluateur. Gere 6 tags
  (`ELitI`, `ELitS`, `ESym`, `EApply`, `ELambda`, `EBind`).
  **N'a PAS de cas pour `EData`** -> `data` silencieusement ignore.
- `tests/test_eval.hvn` : 13 tests verts (prim, if, closures,
  `fac 5 = 120`, `fac 6 = 720`). Donc la recursion simple marche
  dans l'interpreteur.

## Manques pour `run self` (E.run (read_file "lib/heaven_eval.hvn"))

### 1. `data` non evalue (bloquant)
`data_scan` produit `EData name`. L'evaluateur n'a pas de cas
`eval (HP.EData ...)`. Le `data` est parse puis ignore.
**Besoin** : enregistrer les constructeurs dans l'Env (au minimum
un tag par constructeur), + matcher les patterns constructeurs.
Effort : 1 session pour `data` simple (constructeurs 0-arg).

### 2. Patterns constructeurs non supportes (bloquant)
L'evaluateur matche uniquement `(EnvCons n v rest)` par egalite
de sym. Les patterns comme `(Just x)` / `(Cons h t)` demandent un
matcher structurel recursif.
**Besoin** : etendre `match_pattern` pour decomposer les apply de
constructeurs. Effort : 1-2 sessions.

### 3. `import` non resolu (bloquant)
`import_scan` gere le parsing mais `eval_file` ne traite pas
`EImport` (pas de cas). `run self` crash ou ignore tous les
`import "lib/..." as X`.
**Besoin** : charger et evaluer l'import avant de continuer.
Effort : 30 min si on a `read_file` (oui, `stdlib/fs.hvn`).

### 4. Fossile "exit 0 silencieux" (bloquant)
Documente dans `lib/heaven_parse.hvn:4` : un import dont une clause
a un pattern de constructeur 0-arg **qualifie** en tete fait sortir
le process silencieusement (exit 0, aucun message). Contourne en
fusionnant les fichiers. `run self` ne peut pas fonctionner tant
que ce bug n'est pas corrige (ou contourne par fusion).
**Besoin** : fix du parse import (ou maintenir la fusion).
Effort : 1 session (bug parser profond).

### 5. `let`, `if/then/else` infixe
L'evaluateur ne connait pas `let ... in ...` (il voit `bind`).
`heaven_parse.hvn` produit-il `EBind` pour `let` ? A verifier.
Le fix selfrecursion (011d934) permet maintenant a
`heaven_eval.hvn` d'utiliser `if then else` en surface — pas
teste. A valider en premier avant d'attaquer les manques.

## Total effort

3-4 sessions (1 par manque bloquant). Pas un chantier d'une heure.

## Ce qui est debloque

- Fix selfrecursion (011d934) : la recursion utilisateur marche
  maintenant dans les `.hvn` reels. `heaven_eval.hvn` peut
  passer de "if/else via VIf1/VIf2" a `if then else` direct.
- N2 (DNS resolve) : debloque.
- JSON, HTTP body, AST walkers : debloques.

## Prochaines etapes suggerees

1. **Session 1** : valider que `heaven_eval.hvn` accepte maintenant
   `if then else` (test simple, 10 min). Si oui, simplifier le
   fichier (supprimer VIf1/VIf2, utiliser if direct).
2. **Session 2** : `eval (HP.EData ...)` + constructeurs 0-arg.
3. **Session 3** : patterns constructeurs.
4. **Session 4** : `import` + fix fossile silencieux -> `run self`.

## Decision

Mettre le chantier en pause apres session 1 (validation). Faire
N2 (DNS) d'abord — livrable concret, debloque par le fix
selfrecursion. La metacircularite complete quand on aura 4 sessions
devant nous.


## Manque #5 RESOLU (2026-10-19)

`if then else` en syntaxe de surface fonctionne dans l'interpreteur
Heaven-pur.

**Fix** : ajout de `parse_if` dans `heaven_parse.hvn` (def_body
dispatche vers `parse_if` si le premier token du corps est `if`).
Consomme `if` explicitement (pas via `parse_one`), puis parse
cond / `then` / a / `else` / b, produit `EApply (EApply (EApply
(ESym "if") c) a) b` — curry 3 compatible VIf1/VIf2 de l'evaluateur.

**Premier essai (rollback)** : `parse_one` consommait `if` en
`ESym "if"`, `parse_if_c` ne trouvait pas `then` -> PErr. Deuxieme
essai : `parse_if (TCons (TSymTok "if") rest) = (parse_if_c (parse_one rest))`.

**Tests** : tests/test_meta_if.hvn (7 cas : then, else, recursion,
fac 5, fac 6, parens `(if c a b)` toujours OK, imbrique). Tous
verts. Non-regression : test_parser 22/22, test_eval 13/13.

**Reste a faire (manques 1-4)** :
1. `data` -> `eval (HP.EData ...)` + constructeurs 0-arg (1 session).
2. Patterns constructeurs (1-2 sessions).
3. `import` non resolu dans eval_file (30 min).
4. Fossile 'exit 0 silencieux' (1 session).

Estimation : 2-3 sessions.
