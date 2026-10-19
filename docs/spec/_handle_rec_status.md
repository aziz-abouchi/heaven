# handle_rec / effects — état et chantier parallèle (2026-10-19)

**Statut** : parallèle à D9/E4/E5. Non bloquant. Chantier de
consolidation estimé 1-2 sessions.

## Ce qui existe (prouvé)

- `perform` reconnu comme mot-clé (`engine_expr.zig:982`,
  `isMagic`). Capture dans `pending_capture` kind `.perform`.
- `handle_rec` et `__handle_rec_k` dans la liste magics.
  Signature probable : `(handle_rec prompt thunk handler)`.
- `yield` (l.1152) : pose une `pending_capture` kind `.yield_task`.
- `prompts` : pile des frontières `handle_rec` ouvertes.
  `@prompt_depth`, `@prompt_current`, `@prompt`, `@throw`.
- Scheduler coopératif : `add_task`, `schedule`, `task_state`,
  `.preempted` vs `.blocked` (A3A-PREEMPT).
- Tests verts : `test_effects_rec` 4/4, `test_continuations`
  15/15, `test_prompt_depth` 13/13.

## Ce qui manque (spec `_effects.md`)

- **`handle` inspecte `last_performed`** au lieu de capturer une
  continuation. Ce n'est ni un shallow handler ni un deep handler.
  La spec est explicite : « le mécanisme actuel ne doit pas être
  décrit comme un shallow/deep handler ».
- **`resume` public** : `resume_from_k` est un enum interne
  (`pending_capture.kind`), pas un magic exposé.
- **Pas d'interface `.hvn` stable** : `stdlib/effects.hvn` ?
  Aujourd'hui, tout passe par des magics.
- **Composition** `handle (handle e h1) h2` : non testée, non
  spécifiée.

## Prérequis (prompt de continuité)

- effects-consolidation = prérequis de MPST-V2 et A-3b-3.
- À faire **après** E4/E5 si on suit l'ordre actuel, ou **en
  parallèle** si D9 est bloqué (ce qui est le cas : B3 let-chain).

## Plan proposé (session dédiée)

1. Discriminant : `handle` capture-t-il `perform` en isolation ?
   (test `_disc_handle.hvn`).
2. Si non, choisir : shallow vs deep handler, écrire la sémantique
   dans `_effects.md` (décision).
3. Exposer `resume` comme magic public (façade sur
   `resume_from_k`).
4. `stdlib/effects.hvn` : façade `.hvn` pour `perform`/`handle`/
   `yield`/`resume`.
5. Tests composition + baseline.

**Ne pas** bricoler à chaud : le système de prompts est câblé avec
le scheduler préemptif et `SuspendRequested`. Un fix à moitié casse
`test_preemptive_coop` et `test_scheduler`.

## Références

- `docs/spec/_effects.md` (285 l.), `_continuations.md` (303 l.),
  `_concurrency.md` (467 l.).
- `src/core/engine_expr.zig:187-350` (PendingCapture, prompts,
  scheduler).
- `tests/test_effects_rec.hvn`, `test_continuations.hvn`,
  `test_prompt_depth.hvn`.

