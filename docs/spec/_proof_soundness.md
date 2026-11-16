# Soundness des preuves -- decision (2026-11-16)

**Decision engageante.** 11 sites `thm.verified = true` audites, 3 familles.

## Familles

- A) Axiome -- 4 sites (session:78, wasm:544, proof_core:75, proof:76). Legitime, mais bool ne distingue pas axiome de prouve.
- B) Solved -- 2 sites (heaven_expr:3010,3091). Tactiques resolues, code porte un TODO explicite.
- C) Canonical -- 5 sites (proof_core:160,165,189,562, wasm:628). Convergence canonique, PAS une preuve sauf si rewrite sound.

## Decision

Remplacer `verified: bool` par `status: enum { proposed, solved, axiom, canonically_equivalent, kernel_certified }`.
Seul `kernel_certified` autorise un affichage public [PROVED].

## Bugs identifies

1. proof_core.zig:543 -- `return step_ok` seul (ignore structural_ok + type_ok de L541).
2. commands.zig:437 -- ecrase la valeur correcte de L541 avec `step_ok`.

## Plan 5 phases (bloquantes)

0=ce doc, 1=false_theorems.sh (warn-only, doit echouer), 2=fix L543+L437, 3=refactor enum, 4=famille C, 5=CI bloquant.

## Lien

P0 soundness. Precede MIR multi-clauses. Voir _claims_vs_reality.md Update 5.
