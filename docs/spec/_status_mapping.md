# Status mapping -- Phase 3 classification (2026-11-16)

## Statuts (7) et invariants

| Statut | Condition obtention | Affichage |
|---|---|---|
| proposed | theorem initial, aucune preuve tentee | [ ] |
| solved | tactique terminee OU test fini, kernel non appele | [SOLVED] |
| axiom | declaration axiome (postulat) | [AXIOM] |
| canonically_equivalent | convergence rewriter interne OU test syntaxique | [EQ] |
| trusted | confiance externe (aucun site aujourd hui) | [TRUSTED] |
| kernel_certified | kernel.verify retourne true | [PROVED] |
| legacy_unclassified | verified:true sans status, origine inconnue | [LEGACY] |

Invariant : seul kernel_certified autorise [PROVED] public.

## Writers (17 sites)

| Site | Evenement | Statut |
|---|---|---|
| proof.zig:78 | axiom() | axiom |
| proof_core.zig:79 | axiom() | axiom |
| proof_core.zig:92 | theorem() | proposed |
| session.zig:78 | load axiome | axiom |
| session.zig:89 | load theoreme (pattern verified:true) | legacy_unclassified ou proposed |
| wasm_entry.zig:500 | ctor theoreme non prouve | proposed |
| wasm_entry.zig:544 | ctor axiome | axiom |
| wasm_entry.zig:628 | induction finie 0..11 + swap syntaxique (D1) | solved propose |
| heaven_expr.zig:3010 | tactiques resolues (TODO noyau) | solved |
| heaven_expr.zig:3091 | ProofSession.finish | solved |
| proof_core.zig:164 | verifyByEval: booleans egaux | canonically_equivalent |
| proof_core.zig:169 | verifyByEval: ints egaux | canonically_equivalent |
| proof_core.zig:193 | verifyBySimplify: structural eql apres rewrite | canonically_equivalent |
| proof_core.zig:263 | verifyBySynthesis: eclass match | canonically_equivalent |
| proof_core.zig:546 | verifyByInduction (3 booleens en scope) | kernel_certified / solved / proposed |
| proof_core.zig:568 | verifyByRewrite: canonEqStr | canonically_equivalent |
| heaven_expr.zig:3342 | mirror qualified name | inherit source (pas de statut propre) |

Note proof_core.zig:542 : les 3 booleens step_ok, structural_ok, type_ok
sont locaux. Le mapping peut recuperer l info perdue par le bool :
  step_ok ET structural_ok ET type_ok  ->  kernel_certified
  step_ok ET NON(...)                  ->  solved
  NON step_ok                          ->  proposed

## Readers (7 sites)

| Site | Role | Changement |
|---|---|---|
| session.zig:27 | save JSON | ecrit status au lieu de verified:bool |
| session.zig:82 | load (indexOf verified:true) | lire 2 formats (status prioritaire) |
| wasm_entry.zig:666 | WASM display [P] | [PROVED]/[AXIOM]/[EQ]/[SOLVED]/[ ] |
| heaven_expr.zig:3342 | mirror | inherit source |
| proof_core.zig:260 | verifyBySynthesis return bool | status == canonically_equivalent |
| proof_core.zig:543 | verifyByInduction return bool | status == kernel_certified |
| proof_core.zig:580-581 | shell display checkmark/proved | mapper 7 statuts |

## Migration legacy

- save : ecrire status=enum systematiquement
- load : si status present, utiliser tel quel
- load : si verified:true sans status, -> legacy_unclassified
- load : si verified:false sans status, -> proposed

## Decisions Phase A

D1 (wasm_entry.zig:628) : induction finie 0..11 = test, pas preuve.
Statut propose : solved. Alternative canonically_equivalent rejetee (boucle
0..11 est approximation, pas equivalence prouvee).

D2 (wasm_entry.zig:602) : swap syntaxique a-b vs b-a -> commutativite.
Pas une convergence canonique, une regle ad-hoc non documentee.
Statut propose : solved, commentaire ad-hoc a revoir.

## Phase A terminee quand

- 7 statuts valides (D1/D2 tranches)
- 17 writers + 7 readers mappes
- migration legacy acceptee
- Phase B (enum + migration JSON) peut demarrer
