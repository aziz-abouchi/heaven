# Roadmap v2 (2026-10-20)

## Vague 1 -- bugs .zig, cause identifiee (1 session chacun)

| # | Chantier | Cause | Effort |
|---|---|---|---|
| S1 | QTT bind runtime | `.bind` eval `env.put(node.payload)`, `buf` lie a `unit` -> ArityMismatch | 1 session |
| S2 | TLS `@tls_read` | `SSL_read` -> 0, handshake OK, plain HTTP 8/8 | 1 session |
| S3 | Leak `engine.fns` | `Heaven.deinit` complet, leak dans `engine` | 0.5 session |

Baseline complete requise (.zig touche).

## Vague 2 -- features (scope defini)

| # | Chantier | Etat | Effort |
|---|---|---|---|
| S4 | MPST V1 multipartite | V0.5 10/10 | 2 sessions |
| S5 | HKT rank-2 | `_hkt_rank2_plan.md` | 1-2 sessions |
| S6 | HIT V0 exposition | kernel pret | 1-2 sessions |

## Vague 3 -- recherche, RFC AVANT code

| # | Chantier | Effort |
|---|---|---|
| S7 | Higher-order category | 1 session cadrage |
| S8+ | HoTT / Cubical | RFC 2-3 sessions avant code |

## Vague 4 -- ecosystem .hvn (voir `_ecosystem_plan.md`)

1. `lib/random.hvn` (1 bloc) -- FAIT ce jour
2. `lib/time.hvn` (1 bloc si clock magic dispo)
3. `lib/json_rpc.hvn` (1 bloc)
4. `lib/lsp/` (2-3 sessions)
5. `lib/mcp/` (2 sessions)
6. `lib/linter.hvn` (1-2 sessions)
7. `lib/fmt.hvn` (2 sessions)
8. `compiler/transpiler` (RFC d'abord)

## Regles de discipline (lecons 2026-10-20)

1. UN chantier par session.
2. Cutoff 3 blocs diagnostic, puis rollback + doc + pause.
3. Style infixe TOUJOURS.
4. Verifier dans 25 fichiers auto-loades avant de creer.
5. Baseline complete avant commit .zig.


## Vague 2.5 -- DX (apres bugs, avant features)

| # | Chantier | Effort | Note |
|---|---|---|---|
| S6.5 | Messages d'erreur enrichis | 1-2 sessions | ErrorKind + location + expr |
| S6.6 | `target_os` fix (symbol/string) | 1 session | Voir _target_os_bug.md |



## Vague 1.5 -- bug unifie `(print (f 0))` (URGENT)

RecursionLimitExceeded ou silence quand `print` recoit une expression
qui implique un `let-in`, `raw_syscall`, ou autre evaluation non
triviale. Bloque :
- QTT runtime (vision memoire)
- lib/time.hvn
- lib/random.hvn OS (print de debug)
- Toute expression complexe a debugger

Effort : 1 session .zig, haute priorite. Piste dans
_qtt_runtime_bug.md section "CORRECTION MAJEURE".


## Mise a jour 2026-10-20 (fin session, P0 vu autrement)

### P0 = parser S-expr multi-appels sur meme ligne
Pas perform/evaluate/toStringInfix. Voir `_p0_parser_bug.md`.
Effort : 5-15 lignes dans parse.zig. Priorite HAUTE.

### Baseline : 2 fails pre-existants
`zig build test` : 405/407. Fails :
- `tests.test_full_pipeline` (Node.js .wasm execution)
- `kernel.typechecker.test` (refl typechecks)

PAS causes par les changements 2026-10-20. A documenter + fixer
en session dediee (priorite moyenne).

### Workaround actuel
- Un appel par ligne (`.hvn`)
- Infixe `print (h 0)` sans parens externes
- `HEAVEN_DEBUG=1` pour activer `platform.dbg`


## Fails pre-existants (a fixer, session dediee)

`zig build test` = 405/407 :
- `tests.test_full_pipeline` : Node.js .wasm execution
- `kernel.typechecker.test` : refl typechecks

Pas causes par session 2026-10-20. A documenter + fixer.
