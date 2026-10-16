# Session 2026-10-16 — Changelog marathon

**~48 commits poussés** sur `origin/main`. Session longue, trois
chantiers structurels + quatre quarantaines résolues.

## Chantiers livrés

### 1. Refactor plateforme (11 commits)
`src/platform/x86_64_linux.zig` : **591 → 113 lignes** (-81%).
Modules extraits : `parser_ts`, `io_console`, `process`, `time`,
`net_sockets`. Orphelins supprimés : `native.zig` (347 l.),
`network.zig` (39 l.). Zone WebRTC morte purgée (108 l.).

Plan : `docs/spec/_platform_refactor_plan.md`.

### 2. wasm32-wasi opérationnel (5 commits)
Stub 53 l. → impl WASI preview1 réelle. **Exécutable sous Wasmtime** :
    wasmtime run --dir=. ./zig-out/bin/heaven-wasi.wasm "1 + 2"  # → 3
Root `src/vessel/wasi_main.zig`. Stubs conditionnels (`js_ollama_query`).

### 3. A-3b-2c + 2d + 2e (12 commits)
- `Frame.args_done_len` (R2), 11 sites `markArgDone` instrumentés.
- `PendingCapture.cont` (capture sur @throw, resume_from_k, perform).
- `Env` ref-compté dans `expr.zig` (0 leak sur test-files complet).
- `CaptureStack.topMut()`.
- Blocage R1 documenté (`_a3b_resume_strategy.md`) : reprise exacte
  nécessite un trampoline `evaluate` (2-3 sessions).

### 4. Parser — sucre tuple (2 commits)
`(a, b)` → `(tuple a b)` via `rewriteTupleCommas` dans
`heaven_expr.zig`. Cas testés : `(1, 2)`, `(1, 2, 3)`,
`(1, (2, 3))`. Skip strings et lambdas.

### 5. Quarantaines résolues (5 commits)
- `test_io_stream.hvn` : fixture versionnée (`tests/fixtures/`).
- `test_bigint.hvn` : `bdigit_choice` sans `let-in` (TCO préservé).
- `test_bigint_d20.hvn` : isolé (170 Mo).
- CI : `test-files` en `ReleaseFast` (Debug-only memory).

## Dettes tracées (avec piste)

### Bug selfrecursion if-else (CRITIQUE)
**Doc** : `docs/spec/_selfrecursion_bug.md`
**Script** : `scripts/debug-selfrecursion.sh`
**Symptôme** : `count n = if (= n 0) then 0 else (count (- n 1))`,
`(count 1) != 0`.
**Pré-existant** : confirmé sur `b3ac888` (avant nos commits).
**Discriminant** : arg direct dans self-call → KO ; via let/helper → OK.
**Localisation** : nœud `(- n 1)` = `[-, lit 0, apply]` au lieu de
`[-, sym n, lit 1]`.
**Reste à faire** : dumper l'AST après `parseExpression`, avant éval.
1 session.

### R1 trampoline evaluate (ÉLEVÉ)
**Doc** : `docs/spec/_a3b_resume_strategy.md`
**Effort** : 2-3 sessions. Refactor hot path (56 sites).
**Débloque** : A-3b-3 (reprise exacte).

### Stubs macOS + Windows (FAIBLE)
**Doc** : `docs/spec/_stub_macos_status.md`
**Blocage** : SDK requis, non testable sur Guix/Linux. 4-6h × 2,
à faire sur machine cible.

## Garde-fous ajoutés

- `scripts/ci-preflight.sh` : simule un checkout propre.
- `docs/spec/_ci_checklist.md` : 5 commandes obligatoires.
- `scripts/debug-selfrecursion.sh` : repro + checklist.

## Roadmap non entamée

T1 (TLS), M1-M4 (Memcached, Diameter, AMQP, Cassandra),
P1-P3 (Bitcask, Vector DB, ONNX). Aucune ligne cette session.

## Leçon méthodologique

Deux incidents CI évités par vérif tardive :
1. Fixture non versionnée (`test_io_stream`, c03c1aa).
2. `zig build test` non vérifié (ad24926).
Coût : ~3h. Formalisation : `_ci_checklist.md`.

Piège découvert : **retirer une définition Heaven (même morte) peut
casser via l'attribution d'Ids**. Ménage limité en conséquence.
