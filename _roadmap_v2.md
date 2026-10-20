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

