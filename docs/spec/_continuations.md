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

## Décision à valider

Option B acceptable ?

Si oui : Prototype 3 = 3 sous-sessions (3a-1, 3a-2, 3a-3).
Si non : préciser A ou C.
