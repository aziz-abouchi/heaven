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
