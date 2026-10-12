# Continuations — conception

**Date** : 2026-09-29
**Statut** : analyse + décision. Aucune implémentation.
**But** : débloquer `handle-rec` et le scheduler préemptif (C3).

## Constat

`engine_expr.zig::evaluate` est un tree-walker récursif direct.
Chaque appel crée une frame native Zig (pile). Aucun moyen de
suspendre au milieu d'une expression : on perd le contexte.

C'est acceptable pour `bracket`/`local`/`catch` (livrés en 97b42b6).
Pas pour `handle-rec` ni pour le scheduler préemptif (C3).

## Trois options

### A — CPS-transform intégral
Toute `evaluate` devient `evaluate(..., k)`. ~500-800 lignes,
+10-20% perf, tous les call sites touchés. 2 sessions.

### B — Continuations délimitées (RECOMMANDÉE)
Style OCaml 5 (Dolan/Madhavapeddy). Primitives :
- `pushPrompt(tag)` / `popPrompt(P)` : frontière
- `captureCont(tag) → k` : capture jusqu'au prompt
- `throwCont(k, v)` : reprend

Tree-walker direct **sauf** aux frontières. ~200-300 lignes.
Compatible magic symbols existants.

### C — Coopératif strict
Pas de capture. `yield` = signal scheduler. Un process CPU-bound
bloque jusqu'au prochain yield. ~80 lignes. Ne débloque rien de plus.

## Décision

**Option B.**

Raisons : effort/portée, compatible existant, mature (OCaml 5),
débloque handle-rec + scheduler préemptif (C3).

## Plan (Prototype 3a)

### 3a-1 — Prompts (1 session)
- `src/core/continuation.zig` : `Prompt` (u32), `PromptStack`.
- `pushPrompt`/`popPrompt` API Zig.
- Test trivial (push; push; pop; pop).

### 3a-2 — captureCont (1 session)
- `captureCont(prompt_id) → Continuation`.
- Segment copié en heap : `(env, id, depth, position)` par frame.
- `throwCont(k, v)` reconstruit et reprend.

### 3a-3 — Branchement (1 session)
- `handle-rec` magic symbol via captureCont/throwCont.
- Scheduler C3 : suspend/queue/reprend.
- Tests : handle-rec simple, yield dans scope, préemption.

## Incertitudes

1. Rejouer `evaluate` depuis un point d'arrêt : side effects,
   allocations. Journal par frame ou sémantique best-effort.
2. Coût du captureCont (copie de stack) à mesurer.
3. Interaction `Store` : pool peut réallouer entre capture/throw,
   mais les `Id` (indices) restent valides.
4. Interaction `env` : unifié à faire.

## Pré-requis

- ✅ handle/perform existants
- ✅ bracket/local/catch (97b42b6)
- ✅ tree-walker stable
- ⏳ Décision finale : prompt-copy vs full CPS
- ⏳ Scheduler squelette (runtime/scheduler/, actuellement
  métadonnée pure)

## Ne pas faire

- CPS pur (Option A) avant d'essayer B
- Scheduler préemptif avant captureCont stable
- Distribution (C2) avant Prototype 3 complet

## Décision

**Option B retenue** le 2026-09-29. Voir D8 dans `docs/DECISIONS.md`.

Prototype 3 = 3 sous-sessions (3a-1, 3a-2, 3a-3).
Contrainte d'ordre : ne pas démarrer 3a-2 avant 3a-1 vert.
Ne pas démarrer C3 (scheduler préemptif) avant 3a-2 stable.

## Note 3a-3 (2026-09-30) — abort coopératif ≠ scheduling

Le prototype 3a-3-lite (`Engine.evalWithBudget` dans
`engine_expr.zig`) implémente un **abort coopératif** : un budget
de réductions est décrémenté à chaque entrée de `evaluate`, et
une fois épuisé, `error.SuspendRequested` est propagée jusqu'au
caller, qui reçoit `EvalOutcome.suspended`.

**Ce n'est pas un primitif de scheduling.**

Un test naïf (round-robin entre 3 tâches avec budget=1) a montré la
limite : appeler `evalWithBudget(t, 1)` N fois suspend N fois à
l'entrée, sans jamais progresser dans l'évaluation. Il n'y a pas
de reprise au point de suspension.

Deux usages légitimes :
- **Timeout** : abandonner une évaluation après N réductions.
- **Budget explicite** : un appelant qui veut borner le coût d'une
  évaluation et décider quoi faire en cas d'épuisement.

Deux usages **impossibles** sans 3a-3-complet :
- **Round-robin** (scheduling coopératif fin).
- **Préemption native** (C3 de `_concurrency.md`).

Raison : le safepoint ne capture pas la pile au point d'abandon.
`captureCont`/`throwCont` existent (`continuation.zig`, 3a-2),
mais sur une pile *symbolique* non branchée sur `evaluate`. Le
branchement réel reste à faire (3a-3-complet).

Décision : le scheduler (`_concurrency.md` Prototype 2 « vrai »)
ne peut pas être construit sur `evalWithBudget` seul. Il exige le
branchement de `captureCont` dans le tree-walker.

## Note 3a-3 (2026-10-02) — evalWithRetry, borne du modèle redémarrable

Ajout de `Engine.evalWithRetry(id, initial_budget, max_budget)` dans
`engine_expr.zig` : boucle qui relance `evalWithBudget` avec un
budget doublé jusqu'à `done` ou épuisement du max. Retourne l'`Id`
du résultat ou `null`.

Ce n'est **pas** 3a-3. C'est le premier consommateur réel du
safepoint, qui borne son domaine :

- **Utilisable** : timeout, budget explicite, calcul pur redémarrable.
- **Inutilisable** : scheduling, `handle-rec`, tout ce qui produit
  des effets. Le redémarrage rejoue les effets.

Ceci confirme la note du 2026-09-30 : le vrai 3a-3 exige le
branchement de `captureCont` dans `evaluate`, avec restructuration
des corps de handler en unités réévaluables. Effort 2-3 sessions
(voir D8 dans `docs/DECISIONS.md`, révisée le 2026-10-02).

---

## 3a-3a — Prompts branchés (2026-10-12)

**Statut** : ✅ Fait

Modifications dans `src/core/engine_expr.zig` :

1. `Engine.prompts: PromptStack` — pile dédiée aux frontières
   `handle_rec`, distincte de `capture_stack` (réservée à 3a-3b).
2. `handle_rec` : push/pop du prompt via `defer`. L'`init_state`
   est évalué **avant** l'ouverture de la frontière.
3. `RecCtx.prompt: Prompt` — porte l'id du prompt courant.
4. Deux magics d'introspection :
   - `@prompt_depth` — nombre de prompts ouverts
   - `@prompt_current` — id du prompt au sommet (0 si aucun)
5. `isMagicSymbol` : ajout de `@prompt_depth`, `@prompt_current`.

**Tests** : `tests/test_prompt_depth.hvn` (6 tests).
**Non-régression** : `test_effects_rec.hvn` (4/4),
`continuation.zig` (9/9).

**Bugs test runner découverts** (à tracer) :
- `let-in` non évalué dans une expression de test
- `(if int a b)` refuse un int comme condition
- `(@magic)` 0-arg strippé en symbole nu

---

## 3a-3b — Migration HandleRecYield → SuspendRequested (2026-10-12)

**Statut** : ✅ Fait

Le mécanisme d'exception Zig dédiée (`error.HandleRecYield`) est
remplacé par un signalement non-exceptionnel via
`error.SuspendRequested` (déjà présent pour le budget de reductions)
+ un champ `engine.pending_capture: ?PendingCapture`.

Modifications dans `src/core/engine_expr.zig` :

1. **Nouveaux types** :
   - `CaptureKind = enum { perform, resume_from_k }`
   - `PendingCapture = struct { kind, handler, value, new_state, prompt }`

2. **Engine** : champ `pending_capture: ?PendingCapture = null`.

3. **`perform`** : au lieu de `return error.HandleRecYield`, pose
   `pending_capture = .{ .kind = .perform, .handler, .value, .prompt }`
   et remonte via `error.SuspendRequested`.

4. **`handle_rec`** : boucle discriminée par prompt. Attrape
   `SuspendRequested`, vérifie que `pending_capture.prompt == my_prompt`,
   traite selon `kind` (perform → handler / resume_from_k → reboucler).
   Les captures pour d'autres prompts sont **propagées**.

5. **`__handle_rec_k`** : au lieu de `ctx.k_signaled = true`, pose
   `pending_capture = .{ .kind = .resume_from_k, .new_state, .prompt }`.

**Non-régression** : `test_effects_rec.hvn` 4/4 sans modification,
`test_prompt_depth.hvn` 13/13, `continuation.zig` 9/9.

**Dette restante** (3a-3b.3) : `HandleRecYield` toujours dans
`EvalError`, `RecCtx.{pending_value, k_signaled, next_state}` toujours
présents (utilisés par le scheduler, ligne 954-955 + 1003-1005).

**Suite** : 3a-3b.4 (test nested), 3a-3c (magics @capture/@throw).

---

## 3a-3b.3 — Cleanup dead code (2026-10-12)

**Statut** : ✅ Fait

Purge du code mort issu de la migration 3a-3b :

1. **`EvalError.HandleRecYield` supprimé** — plus utilisé nulle part
   après la migration vers `pending_capture` + `SuspendRequested`.

2. **`RecCtx.pending_value` supprimé** — champ mort, remplacé par
   `PendingCapture.value`.

3. **`RecCtx.{next_state, k_signaled}` conservés** — toujours
   utilisés par le scheduler (`yield`/`schedule`), qui n'utilise
   pas encore `pending_capture`. Documenté comme dette 3a-3b.5.

**Non-régression** : 4/4 + 13/13 + 3/3 + 18/18 = **38/38**.

**Dette restante** :
- 3a-3b.5 : migrer le scheduler sur `pending_capture` puis
  supprimer `RecCtx.{next_state, k_signaled}`.
- 3a-3c : exposer `@capture`/`@throw` comme magics Heaven.

---

## 3a-3b.5 — Scheduler sur pending_capture (2026-10-12)

**Statut** : ✅ Fait

Le scheduler coopératif utilise maintenant le même mécanisme que
`handle_rec` : `pending_capture` + `SuspendRequested`. Plus de
`RecCtx` ad-hoc, plus de champs `next_state`/`k_signaled`.

Modifications dans `src/core/engine_expr.zig` :

1. **`CaptureKind.yield_task`** — nouveau variant pour signaler un
   yield de tâche (vs perform/resume_from_k pour handle_rec).

2. **`yield`** : pose `pending_capture = .{kind=.yield_task, .new_state, .prompt=0}`
   et remonte via `SuspendRequested`. Ne dépend plus de
   `engine.rec_ctx`.

3. **Scheduler** : ne crée plus de `RecCtx`. Après
   `evalWithBudget`, discrimine via `engine.pending_capture` :
   - `yield_task` → requeue avec nouvel état
   - autre kind (inattendu) → reset + requeue
   - null + `.suspended` → budget épuisé, requeue avec état inchangé

4. **`RecCtx`** : réduit à `{body_fn, handler, state, prompt}` —
   supprimés : `next_state`, `k_signaled`.

**Non-régression** : 4/4 + 13/13 + **3/3** (scheduler) + 18/18
= **38/38**.

**Bénéfice** : un seul mécanisme de suspension dans tout le noyau.
`_continuations.md` Option B (delimited continuations style OCaml 5)
est maintenant **opérationnel pour handle_rec et le scheduler**.

**Suite** : 3a-3c (magics @capture/@throw, débloque préemptif C3).

---

## 3a-3c — Magics @prompt / @throw (2026-10-12)

**Statut** : ✅ Fait

Continuations délimitées utilisables depuis Heaven. One-shot.

**Syntaxe** :
- `(@prompt (lambda k -> body))` : ouvre une frontière, passe un
  token `k` au body. Retourne le résultat du body, ou la valeur
  throwée si le body fait `(@throw k v)`.
- `(@throw k v)` : invalide le token `k` (one-shot), remonte vers
  son `@prompt` avec la valeur `v`.

**Modifications** :
1. `CaptureKind.throw_to_prompt` — nouveau variant.
2. `CaptureRecord { prompt, env }` — one-shot, indexé par token u32.
3. `Engine.captures: AutoHashMapUnmanaged(u32, CaptureRecord)` +
   `next_capture_id`.
4. Magics `@prompt` / `@throw` dans `evalMagic`.
5. `EvalError.InvalidCapture` — token inconnu/expiré.
6. `isMagicSymbol` étendu.

**Tests** : `tests/test_continuations.hvn` (5 tests).
**Non-régression** : 4/4 + 18/18 + 3/3 + 13/13 + 15/15 = **53/53**.

**Limites V0** :
- One-shot : le token est invalide après usage. Multi-shot demande
  clonage env + store (complexe).
- Pas de `@prompt` avec valeur de retour typée (le résultat reste
  un Id Store).
