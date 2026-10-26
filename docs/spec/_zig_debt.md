# Dette Zig — inventaire (2026-10-26)

## Fichiers obèses (>1500 lignes)

| Fichier | Lignes | Verdict |
|---|---|---|
| heaven_expr.zig | 5498 | **Critique** : contient le bug lambda (case 2b), 8 sous-systèmes (eval, interpForAssert, evaluateExpr, evalSExpr, evalSkill, evalProve, evalTheorem, evalTypeExpr, evalGreenExpr) |
| engine_expr.zig | 3474 | Élevé : evalMagic, parseLetExpr, countSymUses |
| expr.zig | 2676 | Élevé : NativeParser (parseUnary, parsePrimary, parseLambdaExpr, parseLetExpr) |
| peano.zig | 1973 | Moyen : kernel Peano |
| elab.zig | 1913 | Moyen : élaboration tree-sitter |
| commands.zig | 1724 | Moyen : shell |
| mir.zig | 1722 | Moyen : MIR |
| math.zig | 1654 | Bas : math |

## Stubs par catégorie

### Stubs légitimes (interfaces platform)
- wasm32_freestanding.zig : 17 `_ = self` (interface WASM, normal)
- shell_parser_types.zig : 4 (générique)
- mir_wat.zig : 3 (backend secondaire)

### Stubs réels (implémentation manquante)
- types.zig : 15 (`DependentChecker.piType/sigmaType` = 0,
  `TypeEnv.infer` = "Int")
- elab.zig : 5 (`tparams` ignorés)
- heaven_expr.zig : 4 (interpForAssert case 2b incomplet)
- expr.zig : 4 (parseLambdaExpr dispatch partiel)

### Stubs doc (TODO/FIXME)
- 18 TODO, 9 stub_comment, 1 not_impl
- À trier : résoudre ou supprimer

## Priorités de nettoyage

### P1 — heaven_expr.zig (5498)
Extraction par sous-système :
- interpForAssert → interp.zig (~500 lignes)
- evalSExpr / evalTypeExpr → eval_special.zig (~300)
- evalSkill / evalProve / evalTheorem → proof.zig (~400)
- evaluateExpr + case lambda → closure.zig (~200)
- Reste eval → heaven_expr.zig (~2000)

Chaque extraction = 1 session, tests obligatoires (18/18).

### P2 — engine_expr.zig (3474)
evalMagic à extraire (magics par catégorie : syscall, string, math, net).
~1000 lignes dans engine_expr.zig après extraction.

### P3 — expr.zig (2676)
NativeParser à extraire (parser.zig).
Les expressions (Pratt) dans expr.zig (~500).

### P4 — types.zig stubs
DependentChecker réel (P5 dans la roadmap).
TypeEnv.infer réel (après DependentChecker).

## Contrainte

**Aucun refactor sans tests 18/18 après.**
**Aucun refactor en fin de session.**
**Un sous-système par session, pas deux.**

## Voir aussi

- `_claims_vs_reality.md` : RFC-0001 modules partiels
- `_decisions.md` : D5 (parseurs fusionnés), D7 (Result explicite)
