# Registre de Vérité : Claims vs Reality (P0a)

| Fonctionnalité | Spécification / Livre | Implémentation réelle (v0.1.0) | Statut |
|---|---|---|---|
| **6 Primitives & Lowering** | Core irréductible | `lit, sym, apply, bind, lambda, relation` + `Store.lower()` | **VALIDÉ** |
| **Types Dépendants (v2f)** | `Vec (n : Nat)` & `:norm` | HIR + Unification `Vec (n + m)` | **VALIDÉ** |
| **Backends QBE / WASM** | Compilation native & WASM | QBE 1.2 + `emitWat` + TCO mutuelle (SCC) | **VALIDÉ** |
| **Knowledge / RDF / Prolog** | Turtle, `:p-fact`, `?-` | `triple_store` + `kanren_expr` | **VALIDÉ** |
| **QTT & Zero-GC** | Multiplicités (0, 1, ω) | Vérification HIR OK, Réutilisation In-Place en cible | **PARTIEL** |
| **Noyau CIC & Quotients** | TCB certifiant complet | TCB minimal (~780 L), Quotients hors TCB principal | **PARTIEL** |
| **HoTT / Path / HIT** | Égalité homotopique a = b | Égalité propositionnelle Peano (`refl`/`eq`) | **ROADMAP** |
| **Acteurs Distribués** | Swarm P2P réactif | Acteurs séquentiels mono-thread avec mailbox | **ROADMAP** |
