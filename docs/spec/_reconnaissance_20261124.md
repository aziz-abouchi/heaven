# Reconnaissance Heaven — 2026-11-24 14:43

> État du projet avant session de travail. Mis à jour 2026-11-24 14:43.

## État Git

```
fe0a78d feat(mir,qbe,wasm): compile peek_byte et string_ptr (diff 28-peek-byte)
574d522 test(diff): remove obsolete 09-string.hvn.skip covered by 27-str-concat
51b11f4 test(import): verify qualified ctor dispatch preserves arity under collision
9f880d2 chore: correct fd643ca message (claimed one-line, delivered 54 lines)
6317197 test(import): add collision, alias, and path resolution tests
fd643ca fix(import): remove pointless discard of const in test (Zig 0.15)
ecd2807 docs(wasm): mark heavenTheorems as dead code, harmonize axiom label
9d00c41 docs(doctest): record v2 coverage, 271 commands 0 errors (3af5b4e)
b1e3dfd test(diff): add string_concat differential test across backends
0118477 mir: factor emitExternCall helper and add string_length diff test
```

## Build

```
```

## Tests

```
✓ test "addition": (+ 1 2) == 3 → test addition: ✓ passed (0.63ms, cpu 0.63ms)
✓ test "multiplication": (* 3 4) == 12 → test multiplication: ✓ passed (0.55ms, cpu 0.55ms)
✓ test "derive_x2": derive x^2 == (* 2 x) → test derive_x2: ✓ passed (2.98ms, cpu 2.98ms)
✓ test "simplify_0_add": simplify (+ x (+ 0 x)) == (* 2 x) → test simplify_0_add: ✓ passed (28.04ms, cpu 28.04ms)
✓ test "distributivity": simplify (* 2 (+ x 3)) == (+ (* 2 x)  → test distributivity: ✓ passed (e-graph) (214.59ms, cpu 214.59ms)
✓ test "factorization": simplify (+ (* 3 x) (* 3 y)) == (* 3 ( → test factorization: ✓ passed (73.26ms, cpu 73.26ms)
✓ test "factor_common_left":  simplify (+ (* 3 x) (* 3 y)) ==  → test factor_common_left: ✓ passed (74.04ms, cpu 74.05ms)
✓ test "factor_common_right": simplify (+ (* x 3) (* y 3)) ==  → test factor_common_right: ✓ passed (74.24ms, cpu 74.24ms)
✓ test "factor_common_mix":   simplify (+ (* 3 x) (* y 3)) ==  → test factor_common_mix: ✓ passed (74.45ms, cpu 74.45ms)
✓ test "macro_double": (double 21) == 42 → test macro_double: ✓ passed (0.74ms, cpu 0.74ms)
✓ test "proto1_spawn_tell_recv": (let many p = (spawn (lambda  → test proto1_spawn_tell_recv: ✓ passed (1.49ms, cpu 1.50ms)
✓ test "proto1_fifo_order": (let many p = (spawn (lambda x x)  → test proto1_fifo_order: ✓ passed (2.22ms, cpu 2.22ms)
✓ test "proto1_two_procs": (let many p1 = (spawn (lambda x x)  → test proto1_two_procs: ✓ passed (2.29ms, cpu 2.30ms)
✓ test "proto2_run_drains": (let many p = (spawn counterHandle → test proto2_run_drains: ✓ passed (1.96ms, cpu 1.96ms)
✓ test "proto2_two_procs_run": (let many p1 = (spawn counterHa → test proto2_two_procs_run: ✓ passed (2.93ms, cpu 2.93ms)
✓ test "scoped_bracket_returns_body": (bracket 0 42 99) == 42 → test scoped_bracket_returns_body: ✓ passed (0.69ms, cpu 0.69ms)
✓ test "scoped_catch_default": (catch (/ 1 0) 42) == 42 → test scoped_catch_default: ✓ passed (0.86ms, cpu 0.86ms)
✓ test "scoped_catch_success": (catch (+ 1 2) 0) == 3 → test scoped_catch_success: ✓ passed (0.85ms, cpu 0.85ms)
✓ test "scoped_local_bind_and_restore": (let many x = 5 in (le → test scoped_local_bind_and_restore: ✓ passed (0.99ms, cpu 0.99ms)
✓ test "scoped_local_visible_inside": (let many x = 5 in (loca → test scoped_local_visible_inside: ✓ passed (0.89ms, cpu 0.89ms)
✓ test "actor_state": state(Counter) == 15 → test actor_state: ✓ passed (0.69ms, cpu 0.69ms)
✓ test "effect_handle": handle (perform "Log" 42) logHandler = → test effect_handle: ✓ passed (1.43ms, cpu 1.43ms)
✓ test "div_by_zero": assert_err (/ 5 0) → test div_by_zero: ✓ assert_err passed (0.48ms, cpu 0.49ms)
✓ test "actor_not_found": assert_err (send 999 5) → test actor_not_found: ✓ assert_err passed (0.48ms, cpu 0.48ms)
✓ test "type_mismatch": assert_err (+ 1 true) → test type_mismatch: ✓ assert_err passed (0.48ms, cpu 0.49ms)
✓ test "simplify_double":     simplify (+ x x) == (* 2 x) → test simplify_double: ✓ passed (29.52ms, cpu 29.52ms)
✓ test "simplify_egraph_double": simplify (+ x (+ 0 x)) == (*  → test simplify_egraph_double: ✓ passed (29.61ms, cpu 29.62ms)
✓ test "simplify_add_zero":   simplify (+ x 0) == x → test simplify_add_zero: ✓ passed (8.00ms, cpu 8.00ms)
✓ test "simplify_mul_one":    simplify (* x 1) == x → test simplify_mul_one: ✓ passed (7.96ms, cpu 7.96ms)
✓ test "simplify_mul_zero":   simplify (* x 0) == 0 → test simplify_mul_zero: ✓ passed (7.99ms, cpu 7.99ms)
✓ test "simplify_double_add": simplify (+ (+ x 0) 0) == x → test simplify_double_add: ✓ passed (8.23ms, cpu 8.24ms)
✓ test "simplify_double_mul": simplify (* (* x 1) 1) == x → test simplify_double_mul: ✓ passed (8.23ms, cpu 8.23ms)
✓ test "derive_power2": derive x^2 == (* 2 x) → test derive_power2: ✓ passed (3.35ms, cpu 3.35ms)
✓ test "derive_power3": derive x^3 == (* 3 (^ x 2)) → test derive_power3: ✓ passed (4.54ms, cpu 4.54ms)
✓ test "square_detection": simplify (* x x) == (^ x 2) → test square_detection: ✓ passed (41.61ms, cpu 41.61ms)
✓ (assert_err (let-linear x 5 (+ x x))) → ✓ assert_err passed (0.37ms, cpu 0.38ms)
✓ (assert_err (let-linear x 5 42)) → ✓ assert_err passed (0.19ms, cpu 0.20ms)
✓ (assert_eq (let-linear x 5 (+ x 1)) 6) → ✓ assert_eq passed (0.66ms, cpu 0.67ms)
✓ (assert_err (let-erased x 5 (+ x 1))) → ✓ assert_err passed (0.37ms, cpu 0.37ms)
✓ (assert_eq (let-erased x 5 42) 42) → ✓ assert_eq passed (0.33ms, cpu 0.33ms)
✓ (assert_eq (let-many x 5 (+ x x)) 10) → ✓ assert_eq passed (0.66ms, cpu 0.66ms)
✓ (assert_err (let linear x = 5 in (+ x x))) → ✓ assert_err passed (0.41ms, cpu 0.42ms)
✓ (assert_err (let linear x = 5 in 42)) → ✓ assert_err passed (0.23ms, cpu 0.23ms)
✓ (assert_eq (let linear x = 5 in (+ x 1)) 6) → ✓ assert_eq passed (0.70ms, cpu 0.70ms)
✓ (assert_err (let erased x = 5 in (+ x 1))) → ✓ assert_err passed (0.41ms, cpu 0.41ms)
✓ (assert_eq (let erased x = 5 in 42) 42) → ✓ assert_eq passed (0.37ms, cpu 0.37ms)
✓ (assert_eq (let many x = 5 in (+ x x)) 10) → ✓ assert_eq passed (0.70ms, cpu 0.70ms)
✓ assert_eq (+ 1 2) == 3 → ✓ assert_eq passed (0.56ms, cpu 0.57ms)
✓ assert_err (/ 5 0) → ✓ assert_err passed (0.36ms, cpu 0.36ms)
✓ assert_eq test_env_var == 42 → ✓ assert_eq passed (0.25ms, cpu 0.26ms)
✓ assert_eq typed_var == 42 → ✓ assert_eq passed (0.24ms, cpu 0.24ms)
✓ test "infix_add": 2 + 3 == 5 → test infix_add: ✓ passed (0.88ms, cpu 0.88ms)
✓ test "infix_precedence": 2 * 3 + 1 == 7 → test infix_precedence: ✓ passed (1.07ms, cpu 1.07ms)
✓ test "infix_div": 10 / 2 == 5 → test infix_div: ✓ passed (0.91ms, cpu 0.91ms)
✓ test "if_true": (if (> 3 2) 1 0) == 1 → test if_true: ✓ passed (0.90ms, cpu 0.90ms)
✓ test "if_false": (if (< 2 1) 10 20) == 20 → test if_false: ✓ passed (0.92ms, cpu 0.92ms)
✓ test "fn_infix_body": (double 21) == 42 → test fn_infix_body: ✓ passed (0.69ms, cpu 0.70ms)
✓ test "fn_walrus_body": (triple 21) == 63 → test fn_walrus_body: ✓ passed (0.86ms, cpu 0.87ms)
✓ test "derive_poly": derive x^2 + 2*x + 1 == (+ (* 2 x) 2) → test derive_poly: ✓ passed (5.70ms, cpu 5.70ms)
✓ test "let_bind_basic": (let linear x = 5 in (+ x 1)) == 6 → test let_bind_basic: ✓ passed (0.77ms, cpu 0.77ms)
✓ test "let_bind_identity": (let linear x = 42 in x) == 42 → test let_bind_identity: ✓ passed (0.44ms, cpu 0.44ms)
✓ test "let_bind_shadowing_linear_rejected": assert_err (let l → test let_bind_shadowing_linear_rejected: ✓ assert_err passed (0.46ms, cpu 0.46ms)
✓ test "let_bind_shadowing_many_ok": (let many x = 1 in (let m → test let_bind_shadowing_many_ok: ✓ passed (0.55ms, cpu 0.55ms)
✓ test "let_bind_two_vars": (let linear x = 3 in (let linear y → test let_bind_two_vars: ✓ passed (0.85ms, cpu 0.85ms)
✓ test "bind_core_probe": (let linear x = 7 in (+ x 0)) == 7 → test bind_core_probe: ✓ passed (0.75ms, cpu 0.75ms)
✓ test "type_lambda_identity": type (λx.x) == "_t0 -> _t0" → test type_lambda_identity: ✓ passed (0.79ms, cpu 0.79ms)
✓ test "type_lambda_applied": type ((λx.x) 42) == "Int" → test type_lambda_applied: ✓ passed (0.84ms, cpu 0.84ms)
✓ test "tco_small": (count_down 100 0) == 100 → test tco_small: ✓ passed (31.61ms, cpu 31.60ms)
✓ test "tco_deep": (count_down 100000 0) == 100000 → test tco_deep: ✓ passed (32031.52ms, cpu 32030.15ms)
✓ test "stdlib_my_not": (my_not true) == false → test stdlib_my_not: ✓ passed (0.96ms, cpu 0.96ms)
  ✓ 98 passed
  Total: 98 / 98
```

## Structure

| Métrique | Valeur |
|---|---|
| Fichiers Zig | 232 |
| Lignes de code | 72434 |
| Taille WASM | 607K |

## Modules principaux

| Fichier | Lignes |
|---|---|
| src/core/expr.zig | 2941 |
| src/core/heaven_expr.zig | 6188 |
| src/core/elab.zig | 1969 |
| src/core/commands.zig | 652 |
| src/core/proof_core.zig | 678 |
| src/core/math.zig | 1654 |
| src/core/canon.zig | 241 |
| src/kernel/kernel.zig | 41 |

## ROADMAP — Jalons

## Jalon Reseau (Oct 2026)
## Etat 2026-10-07 — decisions structurantes actees
### Ferme
## Plan auto-hebergement (2026-11-10, session 47)
### Phase A — Fondations qui bloquent le self-hosting
### Phase B — Etapes de l'auto-hebergement
### Parallele semantique
### Ce qui n'est pas prioritaire avant Phase A+B
### Decisions liees (etat 2026-11-10)
### Documents de reference
### Pistes actives (reordonnees 2026-11-10, session 47)
## Specs plus anciennes (v0/v1 fermes, v2+ ouvertes)
## #io — Entrées/Sorties par effets algébriques  ✅ *fait*
### Objectif
### Design
### v2 — à faire
## #holes — v2 : affichage interactif  *(v1 ✅, v2 ouverte)*
### État v1 (déjà implémenté)
### v2 — manque
## #runner — Tests multi-lignes & par fichier  ✅ *fait*

## TODOs dans le code

```
src/backend/mir_qbe.zig:97:        // par main. TODO session dédiée : pool global partagé.
src/platform/webrtc.zig:50:    // TODO: router vers handlers (comportement original inchangé —
src/platform/aarch64_macos.zig:65:// TODO: implementer avec sigaction + setitimer POSIX (meme API
src/platform/wasm32_freestanding.zig:402:        // TODO: Parser le JSON retourné par JavaScript
src/syntax/lower_test.zig:125:    // TODO: [lo-hi] n'est pas valide dans la grammaire Tree-sitter
src/runtime/shell/commands.zig:136:    // TODO(stub): query KB pour les faits de `name`. Voir _zig_debt.md.
src/runtime/shell/commands.zig:175:    // TODO(stub): executer fichier .hvn. Voir _zig_debt.md.
src/runtime/shell/commands.zig:181:    // TODO(stub): injecter code dans le REPL. Voir _zig_debt.md.
src/runtime/signaling_server.zig:80:                    // TODO: Maintenir une map de connexions persistantes
src/knowledge/turtle_parser.zig:449:            // TODO: parser datatype custom
```

## Synchronisation WASM

✓ test_suite.hvn synchronisé

## Phase A — Self-hosting

| Composant | État |
|---|---|
| QBE | ❌ absent |
| TCC | 64 fichiers |

## Prochaines étapes suggérées

1. **Phase A self-hosting** : A1 build reproductible QBE/TCC, A2 MIR closures, A3 profondeur récursion, A4 leak check
2. **Voie C** : B0 dump S-expr canonique → B3 MIR/QBE en Heaven → B2 → B1 → B4 point fixe
3. **Quick wins** : #stdlib, #type-dep v2e, optimisation EGraph

