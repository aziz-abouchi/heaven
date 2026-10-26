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

## Catégorisation précise (2026-10-26, après inventaire)

### types.zig — 15 stubs, le vrai chantier
- Lignes 39-66 : `DependentChecker` (piType/sigmaType/vecType retournent 0)
- Ligne 96 : `infer` retourne `"Int"` pour tout
- Lignes 209, 259 : `_ = self` (TypeEnv)
**Verdict** : bloc P5 (DependentChecker réel). Déjà dans la roadmap.
**Coût** : 2-3 sessions. Pas de raccourci.

### elab.zig — 5 TODO structurels
- 234 : annotation type vs valeur
- 244 : désucrer `+= -= *= /=`
- 477, 522 : `tparams` ignorés (data + class)
- 1018 : extraire `GlobalProtocol` depuis l'Id
**Verdict** : bloc P2 (élaboration). Chacun 1-2 blocs.
**Coût** : 5-10 blocs total. Pas prioritaire.

### heaven_expr.zig — 1 TODO critique
- 2842 : `ProofTerm` verify (extraction + traduction + verify)
**Verdict** : P1 (proof), bloqué par kernel CIC réel.
**Coût** : session dédiée après P5.

### Réseau / WebRTC / WASM — 5 TODO
- webrtc.zig:50 (router handlers)
- wasm32_freestanding.zig:399 (JSON JavaScript)
- signaling_server.zig:80 (map connexions)
- network/handlers.zig:134 (Tree-sitter vers Id)
- engine_expr.zig:2560 (egraph connect)
**Verdict** : P2-P3, dépendent de dépendances externes (WebRTC, tree-sitter).

### Connaissance / MLCPD — 5 TODO
- turtle_parser.zig:449 (datatype custom)
- mlcpd_equiv.zig:297, 309, 323, 385
**Verdict** : P3, recherche.

### Stubs légitimes (ne pas toucher)
- wasm32_freestanding.zig : 14 `_ = self` (interface WASM)
- shell_parser_types.zig : générique
- abi/metric.zig : interface
- inference/forge/engine.zig : interface
- syntax/ast.zig : helpers

### Stubs à examiner (faux positifs probables)
- kernel/typechecker.zig (2 `_ = self`)
- kernel/conversion.zig
- runtime/shell/interactive.zig
- runtime/shell/run.zig
- runtime/shell/commands.zig
- runtime/autofab.zig

**Verdict** : à grep ligne par ligne, pas urgent.

## Plan de nettoyage par ordre

1. **P1 (1 session)** : extraction `interpForAssert` → `interp.zig` (bloqué par couplage 7 méthodes, voir session 2026-10-26)
2. **P2 (1 session)** : elab.zig `tparams` (2 TODO, 477 + 522)
3. **P3 (1 bloc)** : `_ = self` faux positifs (grep + vérifier)
4. **P5 (2-3 sessions)** : `types.zig` DependentChecker réel
5. **Hors priorité** : TODO réseau, connaissance, MLCPD

## Contrainte

**Un fichier par session, 18/18 après.**
**Pas de nettoyage cosmétique sans test.**
**Pas de refactor en fin de session.**

## Mise à jour 2026-10-26 : 3 stubs vides identifiés

### commands.zig : cmdQuery, cmdRun, cmdInject
Ces 3 commandes shell sont **complètement vides** (`_ = self; _ = arg;`
puis rien). Elles ne font rien quand appelées (`:query foo`,
`:run file.hvn`, `:inject code` → no-op silencieux).

**Action** : TODO(stub) ajoutés dans le code. À implémenter ou à
retirer du dispatcher.

**Verdict** : stubs réels, pas faux positifs. Coût : 1 bloc chacun
si on implémente, 5 min si on retire du dispatcher.

### 6 autres `_ = self` sont légitimes
typechecker.zig, conversion.zig, interactive.zig (×2), run.zig,
autofab.zig : méthodes qui n'utilisent pas `self` (API stable,
délégation). Ne pas toucher -- Zig exige `_ = self` pour compiler.

**Verdict** : faux positifs confirmés.

## Mise à jour 2026-10-26 : formatJudgment explicite

### types.zig formatJudgment
Retourne maintenant `"[STUB] judgment non verifie (DependentChecker stub)"`
au lieu de `"Judgment stub"`. Les commandes shell `:dep Vec/Pi/Sigma`
affichent maintenant clairement l'état réel (stub, pas vérifié).

**Action** : la commande `:dep` est honnête (affiche STUB). Le vrai
DependentChecker (P5) reste 2-3 sessions.

**Verdict** : B pour cette session terminé. Ne pas implémenter un
demi-typechecker sans typechecker qui le consomme (théâtre).
