# Walker unbound — gaps mesurés et résiduels (2026-11-10)

**Statut** : walker opt-in, résiduels documentés.
**Fichier** : `src/core/scope_check.zig`, `src/commands/check.zig`.
**Voir aussi** : `_check_v2_plan.md`, `_check_validator_bug.md`.

## Mesure initiale (avant fix du 2026-11-10)

Mode `HEAVEN_CHECK_STRICT=1` sur tous les fichiers de `lib/` :

    349 diagnostics "unbound variable"

Répartition par cause :

| Cause | Nb | % |
|---|---|---|
| Nœud `ERROR` (tree-sitter) | 60 | 17 % |
| Alias d'import non résolu (`R`, `D`, `HP`) | 20 | 6 % |
| Cascade tree-sitter (`data X = A \| B` non parsé) | 269 | 77 % |

**Correction du rapport Session 44** : « le walker est à 12 unbound
de la complétude » était faux. La vraie mesure est 349 sur `lib/`,
pas 12 sur `scheduler.hvn` + `test_stream.hvn`. Le chiffre de 12
était une extrapolation de 2 fichiers, pas une mesure. Erreur
signalée par audit externe (2026-11-10).

## Fix du 2026-11-10 (commit `3dba5e5`)

### 1. Nœuds `ERROR` (60 diagnostics)

`Bridge.buildFile` émet `sym("ERROR")` quand tree-sitter ne peut pas
récupérer. Le walker le traitait comme une variable.

Fix : `isFilteredV2` rejette `name == "ERROR"` et tout payload
contenant des caractères non-ident (sauts de ligne, espaces, `+`,
`(`, `)`). Les fragments multi-lignes de source brute sont éliminés.

### 2. Alias d'import (20 diagnostics)

`Bridge.buildFile` ne traite pas `import_decl`. Le scope ne contient
donc jamais `R` (alias de `lib/std/result.hvn`). Le walker voit
`R.Ok` comme unbound.

Fix : scan source pour `" as X"` avant l'appel au walker, passage
des alias via `extra_defined` (nouveau paramètre de
`checkUnboundV2`).

### Résultat mesuré

| Métrique | Avant | Après |
|---|---|---|
| Diagnostics sur `lib/` | 349 | **269** |
| `ERROR` | 60 | **0** |
| Alias (`R`, `D`, `HP`) | 20 | **0** |
| Unitaires STRICT (6 cas) | 6/6 | 6/6 |
| Registry 24/24 | ✓ | ✓ |
| Build | 0 | 0 |

## Résidu (269, 77 %) — tree-sitter, pas le walker

Le walker est **correct sur l'AST qu'il reçoit**. L'AST est incomplet
pour les fichiers qui contiennent :

- `data X = A | B` — `heaven parse` montre `ERROR [1:12-1:13] a`
  pour `data Stream a = ...` (paramètre de type non parsé)
- Clauses multi-lignes, `where`, guards composites
- Certains constructeurs user (`VPrim`, `MkPath`, `IErr`)

Conséquence : les fonctions déclarées **dans la cascade** de l'erreur
ne deviennent jamais des `bind` dans `Bridge.roots`. Le walker les
voit unbound (correct sur l'AST reçu, faux sur le fichier source).

Noms résiduels les plus fréquents :

| Nom | Occurrences |
|---|---|
| `ERROR` | 0 (fixé) |
| `member` | 23 |
| `eval` | 22 |
| `eval_apply2` | 21 |
| `let_expr` | 10 |
| `VPrim` | 9 |
| `parse_id_from` | 9 |
| `p` | 8 |

## Décision `HEAVEN_CHECK_STRICT`

**Maintenu opt-in.** Le taux de faux positifs sur `lib/` reste
269/349 ≈ 77 %. Activer par défaut serait une régression immédiate
sur tout code qui utilise `data X = ...` ou des clauses multi-lignes.

Activation par défaut quand **les 3 conditions** sont réunies :

1. Grammaire tree-sitter supporte `data X a = ...` (au moins ce cas)
2. Cascade post-`data` disparaît (`scheduler.hvn` → 0 unbound)
3. Taux de faux positifs mesuré sur `lib/` < 5 %

## Prochains chantiers (par priorité)

### Court terme — Session 46+

1. **Grammaire tree-sitter `data X a = ...`** — 1-2h, dépendance
   externe (`vendor/tree-sitter-heaven/grammar.js`). Débloque la
   cascade sur `test_stream.hvn`, `scheduler.hvn`, plusieurs `lib/`.
2. **Clauses multi-lignes** — si la grammaire ne les gère pas,
   cascade résiduelle. Diagnostic à faire après (1).

### Moyen terme — Session 47+

3. **Test de régression walker** — un fichier `.hvn` par catégorie
   (unitaires STRICT déjà couverts, manque cascade et alias).
4. **Benchmark faux positifs** — mesure sur `lib/` + `tests/` dans
   la CI, seuil < 5 % avant activation par défaut.

### Long terme

5. **Fallback `nativeToSExpr`** quand `ts_node_has_error(root)` —
   plus radical, mais permet de parser ce que tree-sitter ne sait
   pas. Effort : plusieurs sessions. À considérer si (1) ne
   suffit pas.

## Références

- `_check_v2_plan.md` — plan et historique
- `_check_validator_bug.md` — bug tree-sitter vs native parser
- Commit `3dba5e5` — fix ERROR + alias
- Commit `c69bfd0` — fix `buildEqDecl` (name + body + patterns)
- Commit `46e1a70` — implémentation walker v2 opt-in
- Commit `7430b15` — `Bridge.roots`
