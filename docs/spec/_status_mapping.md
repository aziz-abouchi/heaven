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

## Phase D status (2026-11-16)

### D.1 -- formatAll (shell :theorems) DONE

Verified end-to-end with ed181d4. `:theorems` on two theorems now shows:

    ═══ Theorems ═══
    [ ] theorem t_proposed : 1 + 1 = 2
    [EQ] theorem t_solved : x + 0 = x

[EQ] on t_solved (proved by simplify, so canonically_equivalent not
kernel_certified) and [ ] on t_proposed (declared, no proof). Before
ed181d4, `:theorems` called ProofEnv.formatAll which returned the
literal string "ProofEnv: stub". Two prior commits (2df2b0a, 3e96f09)
modified ProofCore.formatAll but neither was reached: the stub was
the entire visible output. Same triple-correction pattern as
a9ee9c9/f1c0b33->cf38591.

### D.2 -- WASM heavenTheorems NOT WIRED, do not patch

grep heavenTheorems in site/, vessel/, src/vessel/public/ returns
zero callers. site/repl/repl-frame.html uses `prove NAME by METHOD`
(l.138) and displays proof results via data.result (l.157), which
comes from proofResult (heaven_expr.zig), not from heavenTheorems.
Patching wasm_entry.zig:673 ([P]/[ ] -> displayLabel) would be a
4th unreachable commit. Skip until a web UI adds a "list theorems"
button that actually calls heavenTheorems.

### D.3 -- site/repl proof display NOT a status reader

repl-frame.html:157 shows `data.result` from a prove action
(`✓ [name] proved (method)`). This is proofResult output, not the
theorem's persistent status. Phase D does not need to touch it:
verifyBy* already returns the method name, and the format is honest
(it names what ran, not what is certified). No change.

### D -- remaining work before Phase E

Only formatAll (shell) is bridged. Session.save/load still uses
verified:bool AND status (B3 dual-field). Phase E (retrait verified)
will need:

1. session.zig: drop `verified` from save JSON, keep only status
2. session.zig load: migrate old JSON (verified:true -> legacy_unclassified)
3. 5 tests in session.zig that read thm.verified -> switch to status checks
4. proof_core.zig:269 `if (thm.verified) thm.status = ...` -> status only
5. Independent test: old .heaven_session.json with verified:true only,
   load, verify status == legacy_unclassified and verified is gone

Estimated: 1.5-2h with migration tests. Session dedicated.

### Summary

| Step | Status | Commit |
|---|---|---|
| D.1 formatAll shell | DONE | ed181d4 |
| D.2 WASM heavenTheorems | NOT WIRED (skip) | n/a |
| D.3 site/repl proof | NOT A READER (skip) | n/a |
| E retrait verified | TODO | n/a |

