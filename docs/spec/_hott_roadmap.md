# HoTT / HIT rank-2 -- roadmap (2026-10-23)

## Decisions actees
- Q1(a) : Path facade rank-1 (refl/sym/trans/ap) + HIT, sans univalence.
- Q2(A) : Hierarchie cumulative Type_0 : Type_1 : Type_2 : ... (Agda-like).

## Etat du codebase

| Composant | Etat |
|---|---|
| lib/hott/path.hvn | LIVRE -- facade rank-1 (witness int, start, end) |
| src/core/types.zig:33-73 DependentChecker | STUB (piType/sigmaType retournent 0) |
| src/core/types.zig:222 TypeEnv.infer | STUB (retourne "Int") |
| src/core/types.zig:145 LinearChecker | Existe (QTT), non branche |
| src/core/elab.zig:465 elabDataDecl | tree-sitter, tparams IGNORES |
| src/core/expr.zig NativeParser | if + let (fix 1672ce8) -- lambda GAP |
| refl/sym/trans runtime | lib/hott/path.hvn (nouveau) |

## Chantiers (5-6 sessions)

1. (FAIT) path.hvn facade -- 14 tests
2. (FAIT 2026-10-23) grammar : path_constructor. elab.zig ignore from/to (a faire)
3. DependentChecker reel : piType/sigmaType non-stub
4. Typechecker HIT : verifier loop : base = base
5. Eliminateur + computation rules (ap_loop, transport_loop)
6. Rank-2 : hierarchie Type_n cumulative

## Gap parser lambda
parsePrimary ne gere pas lambda. Contournement id_f x = x.
Fix 5-10 lignes dans parsePrimary, session dediee.
