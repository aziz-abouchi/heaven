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

## Etat Phase 2 (2026-11-16)

- Phase 2 complete: b323c41 (initial, incomplete) then 96962dc (correction).
- `verifyByInduction` returns `final_verified` (init false, set inside `if(step_ok)`), no stale value.
- `commands.zig:437` redundant assignment removed.
- Commits: 05368ec (Phase 1), b323c41 + 96962dc (Phase 2), 87d2aee (Phase 0).
- Behavior: unchanged for CLI (induction unreachable via --run-test). Corrected for MCP (no stale proof from prior simplify).
- Phase 1b (MCP discriminator) still pending: the fix is verified by reading, not by test.

## Etat Phase 1b (2026-11-16)

- 915b273: mcp_server.zig:381 method derived from labelFromEvalProve, certified:false, 11 tests unitaires.
- kernel banni des 2 branches (proved (kernel) et via kernel).
- Manque: test d integration MCP (mcp_soundness.sh).
- Cause: heaven mcp est un serveur persistant (port 9000), pas un CLI one-shot.
- Prochain essai: client Python JSON-RPC persistant, session dediee.
- Priorite: Phase 3 (enum) peut demarrer sans bloquer sur ce test.

## Correctif Phase 1b (2026-11-16, apres probe MCP)

- fe1a0c1 disait "serveur persistant (port 9000)". FAUX.
- mcp_server.zig:107-109 = while(true) avec break sur read==0 (EOF).
- heaven mcp est one-shot quand stdin ferme (printf | heaven mcp).
- Le crash terminal venait des control chars / unicode atteignant le tty,
- pas du process qui refuse de mourir. Redirection vers /tmp le confirme.
- Probe: good1 et bad1 by simplify -> proved:false, method:unverified-by-kernel.
- Fix 915b273 ACTIF: method n est jamais "kernel" (si hardcode, on aurait vu).
- Bug evalProve (parse multi-ligne) decouvert: target prend tout le statement,
- pas le nom. A documenter separement, hors Phase 1b.

## Design gap: evalProve interface (2026-11-16)

Revele par probe MCP: heaven_prove envoie statement multi-ligne
("theorem X : Y\nprove X by METHOD"). heaven_expr.evalProve ne strippe
pas "prove " (le texte commence par "theorem "), delegue a cmds.evalProve
qui split sur " by " et prend TOUT le prefixe comme target.

Consequence: target = "theorem good1 : x + 0 = x\nprove good1", le
theoreme n est jamais declare. verifyBySimplify retourne false pour
UnknownTheorem, pas pour preuve invalide. Le certificate dit "proof
failed (simplify)" -- trompeur: la preuve n a pas ete tentee.

Options: (A) extraire le dernier token avant by -- pire car masque
l erreur derriere un faux nom. (B) parser le multi-ligne dans MCP,
declarer + prouver -- vrai fix, ~1h, change contrat MCP. (C) documenter
que heaven_prove attend "prove NAME by METHOD" une ligne, theorem
declare au prealable (aucun outil MCP ne declare aujourd hui).

Phase 1b n a PAS besoin de ce fix: invariants (method != kernel,
certified=false) tiennent. Cas positif (proved=true) hors scope.
Phase 5 (CI bloquant) restera partielle jusqu a B ou C.

## Decision C (2026-11-16): heaven_prove contract is single-line

Le multi-ligne (theorem X : Y\nprove X by M) reste undefined pour MCP.
Aucun outil MCP ne declare de theoreme. mcp_soundness.sh teste donc les
invariants negatifs (method != kernel, certified=false), pas proved=true.
Cas positif differe a Phase 3+ (quand status enum permet de distinguer
resolu de certifie). Le formulaire multi-ligne est documente comme non
supporte dans _proof_soundness.md, pas silencieusement accepte.

## Resolution Option B (2026-11-17) -- DONE (d123b96)

`Heaven.evalProve` (`src/core/heaven_expr.zig`) now splits multi-line input,
evaluates preceding declarations (`theorem ...`, `axiom ...`) via `self.eval`,
and strips the `prove ` prefix before delegating to `cmds.evalProve`.
`tests/proofs/mcp_soundness.sh` now asserts both `proved:true` on `good1`
and `proved:false` on `bad1` while preserving `method != "kernel"` and
`certified:false`.
