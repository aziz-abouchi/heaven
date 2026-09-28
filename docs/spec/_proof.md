# Système de preuve — architecture et responsabilités

**Date** : 2026-09-28
**Statut** : audit descriptif. D3 du `docs/DECISIONS.md`.

## Constat

Il n'y a **PAS de double CIC** dans Heaven. Les modules de preuve
occupent **trois couches distinctes** :

| Couche | Module | Rôle |
|---|---|---|
| **Frontend** | `core/elab.zig` (1678 l.) | Élabore `.hvn` → Core Store. Vérifie Π bien formé, `Eq<lhs,rhs>`. N'utilise pas le kernel. |
| **Store** | `core/proof.zig` (181 l.) | Axiomes Peano niveau Store : `rewritePeano`, `proveByInduction`. |
| **Pont** | `core/kernel_bridge.zig` (143 l.) | Traduit `Id` (Store) ↔ `u32` (TermPool). |
| **Orchestration** | `core/proof_core.zig` (628 l.) | `verifyBySimplify`, `verifyByInduction`, etc. Appelle kernel via bridge. |
| **Helpers** | `core/proof_helpers.zig` (170 l.) | Extraction `Eq<lhs,rhs>` d'un statement, copie entre Stores. |
| **État tactique** | `core/proof_state.zig` (134 l.) | `ProofState`, `Goal`. Isolé, ne dépend que de `expr`. |
| **Kernel** | `kernel/peano.zig` (853 l.) | CIC minimaliste : `TermPool`, `eval`, `infer`, `check`, `verify`. |
| **Façade** | `kernel/kernel.zig` (41 l.) | Ré-exports. |

## Pipeline d'une preuve

    .hvn "theorem t : x + 0 = x"
       │
       ▼
    elab.elaborateSource()  ──  Store (Core)
       │
       ▼
    proof_core.verifyBySimplify()
       │
       ├── kernel_bridge.exprToTerm()  ──  Term kernel (peano)
       │
       ├── kernel.peano.verify()  ──  verdict bool
       │
       ▼
    thm.verified = true

## Points d'attention

1. **`elab` et `kernel` ne se parlent pas.** `elab` produit du Core
   (Store), `kernel` consomme du Term (TermPool). La traduction passe
   exclusivement par `kernel_bridge`.

2. **Deux niveaux d'axiomes Peano** :
   - `core/proof.zig::PeanoAxiom` : réécriture sur le Store
   - `kernel/peano.zig::initNatAxioms` : axiomes CIC

   Ce sont deux mécanismes distincts, utilisés à des niveaux différents.
   À documenter dans chaque module pour éviter la confusion.

3. **`kernel_bridge` périmètre** : uniquement `lit(int)`, `sym`,
   `apply` binop arithmétique. `bind`/`lambda`/`relation` → erreur
   explicite. Conséquence : les théorèmes contenant lambdas/relations
   ne peuvent pas être vérifiés par le kernel CIC (ils passent par
   `verifyBySimplify` au niveau Store).

## Décision D3

**Aucun refactor.** L'architecture actuelle est cohérente :
- Séparation nette entre frontend (élaboration) et kernel (vérification)
- Pont isolé dans `kernel_bridge.zig`
- Pas de duplication

**Seule action** : ce document (`_proof.md`), pour figer les rôles
et éviter que de futurs contributeurs tentent de « fusionner elab
et kernel » (ce qui n'aurait pas de sens).

D3 fermée.
