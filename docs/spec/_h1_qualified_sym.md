<!-- HEAVEN:h1-qualified-sym -->
# H1 — Sym qualifié (module.Sym) (2026-10-19)

## Symptôme (récidive 4x)

    -- module L exporte : data A = ANil | ACons Int A
    (= (L.mk 0) (L.ACons 1 L.ANil))  -- → false

## Diagnostic

Deux niveaux distincts :

**N1 — Sym qualifié (RÉSOLU 2026-10-19).**
`L.ACons` (Sym qualifié) ≠ `ACons` (Sym original). `exprStructuralEq`
comparait `na.payload == nb.payload` (ids Sym bruts).

Fix dans `pattern.zig` : si un seul côté est qualifié, comparer les
suffixes après le dernier `.`. Si les deux sont qualifiés avec des
préfixes différents → false (conservateur). Si aucun n'est qualifié
et les ids diffèrent → false.

Tests : `tests/test_h1_qualified.hvn` (5 cas : eq_direct, eq_mk_self,
eq_via_let, neq_int, neq_ctor). Tous verts.

**N2 — apply curry vs n-aire (RESTE OUVERT).**
`L.mk 0` produit un apply n-aire avec payload `Sym("ACons")`.
`L.ACons 1 L.ANil` produit un apply **currifié**
`apply(apply(L.ACons, 1), L.ANil)` (parser : args successifs).
`exprStructuralEq` compare les spans → longueurs différentes → false.

Bug distinct, non résolu. Fix probable : normaliser `apply` en
comparant via `applyArgs` (aplatir), OU harmoniser le parser pour
produire un apply n-aire partout.

Effort : 1 session.

## Impact résiduel

- `(= (mk 0) (L.ACons 1 L.ANil))` → false (bug N2).
- `(= (mk 0) (mk 0))` → true (résolu par N1).
- MPST `dual_send_recv` : Sym résolu, structure reste à comparer
  correctement (curry vs n-aire).
- JSON `json_obj_get` : faux positif antérieur (c'était `jv_get`
  manquant, pas H1). Reste à revérifier après N2.

## Priorité

N1 **RÉSOLU** (commit). N2 : 1 session. Le vrai bug bloquant
(ADT importées) est à moitié fixé.
