# Scheduler préemptif — conception (C3)

**Date** : 2026-10-14
**Statut** : analyse + décision. Implémentation partielle.
**But** : clarifier l'état de C3 (préemption native), ce qui
existe déjà, ce qui manque, et les tests qui spécifient la cible.

## 1. Ce que "préemptif" veut dire

En C1, la sémantique du scheduler est **coopérative** : une tâche
cède la main explicitement via `yield`. Un `process` qui ne cède
jamais bloque son worker.

La **préemption** consiste à **interrompre une tâche** sans son
consentement. En V0, c'est du **confort** (pas un contrat) : on
veut éviter qu'une tâche CPU-bound affame les autres.

## 2. Décision actée dans `_concurrency.md`

> **C3 — Préemption native (TRANCHÉE : reduction budget + safepoints)**

Trois options étaient sur la table :
1. Safepoints instrumentés par le compilateur (~5 % surcoût)
2. Signaux + timer (fragile, plateforme-spécifique)
3. Coopératif pur (yield explicite)

**Décision** : option 1. Le compilateur insère des **safepoints**
dans le code généré, et l'interpréteur décrémente un **budget de
réductions** à chaque pas d'évaluation. À 0, la tâche est
suspendue — exactement comme un `yield` implicite.

## 3. Ce qui existe déjà (2026-10-14)

L'infrastructure de C3 est **en place** dans `engine_expr.zig` :

| Composant | Localisation | État |
|---|---|---|
| Champ `engine.reductions: u64` | ligne 295 | ✅ |
| Safepoint dans `evaluate` | lignes 689-692 | ✅ |
| `error.SuspendRequested` | `EvalError` | ✅ |
| `evalWithBudget(id, budget)` | ligne 408 | ✅ |
| `evalWithRetry(id, init, max)` | ligne 431 | ✅ |
| Scheduler requeue sur `.suspended` | depuis 3a-3b.5 | ✅ |

Le safepoint est **déjà dans `evaluate`** (pas seulement à l'entrée
`eval`) — c'est exactement ce que C3 demandait. Chaque pas
d'évaluation consomme 1 réduction.

## 4. Ce qui manque

### 4.1 Modèle de suspension : restart vs resume

Quand une tâche est suspendue par épuisement du budget (sans avoir
fait de `yield`), le scheduler actuel la **requeue avec état
inchangé**. La tâche suivante démarre ensuite normalement.

**Problème** : si la tâche CPU-bound a besoin de plus que `budget`
réductions pour terminer, elle **redémarre du début** à chaque
tour. Pas de progrès. Boucle infinie tant que `budget < N`.

**Deux solutions** :
- **A. Budget croissant** : à chaque requeue, doubler le budget
  pour la tâche. C'est le modèle d'`evalWithRetry`. Simple, mais
  perd le calcul entre les tentatives.
- **B. Reprise (continuations)** : capturer le point d'évaluation
  courant via `@prompt`/`@throw` et le reprendre au tour suivant.
  Le calcul n'est pas perdu. **Débloqué** par 3a-3c.

La voie B est désormais techniquement possible (continuations
délimitées opérationnelles depuis le 12 octobre).

### 4.2 Safepoints dans le code compilé

En interprété, le safepoint est **par pas d'évaluation** — parfait.
En natif (QBE/WASM), il faut insérer des safepoints dans le MIR.
**Non fait** : la préemption native pour code compilé reste à
implémenter.

## 5. Plan technique

**Étape 1 — Budget croissant (30 min)**
- Modifier le scheduler : tâche suspendue par budget → requeue
  avec `budget *= 2`.
- Simple, immédiat, débloque la progression.
- Modèle B de `_continuations.md`.

**Étape 2 — Tests explicites (1 h)**
- `tests/test_preemptive.hvn` : 6-8 tests qui vérifient la cible
  (voir section 6).
- Écrits en `.hvn` (pas `.skip` si étape 1 faite).

**Étape 3 — Reprise par continuations (2-3 sessions)**
- Capturer l'état d'évaluation via `@prompt`/`@throw`.
- Reprendre au lieu de redémarrer.
- Bénéfice : pas de perte de calcul, budget constant possible.
- Prérequis : `captureCont` multi-shot (clonage env + store) pour
  répéter une continuation sans la détruire.

**Étape 4 — Safepoints MIR (3-4 sessions)**
- Insérer des safepoints dans le MIR (`mir.zig`).
- Un safepoint = check `fuel--` + saut conditionnel.
- Cible : QBE, WASM.

**Étape 5 — Safepoints natifs compilateur (chantier long)**
- Le compilateur (pipeline Heaven → MIR) doit insérer des
  safepoints **à chaque point de boucle**.
- Coût : ~5 % d'overhead, comme annoncé.

## 6. Tests attendus (cible C3)

`tests/test_preemptive.hvn` — 6 tests :

| # | Test | Cible |
|---|---|---|
| T1 | budget 10000 : 2 tâches simples finissent | ✅ aujourd'hui |
| T2 | tâche récursive pure (50 appels) termine | ✅ aujourd'hui |
| T3 | 2 tâches récursives : les 2 finissent | ✅ aujourd'hui |
| T4 | tâche yield + tâche récursive : les 2 finissent | ✅ aujourd'hui |
| T5 | budget 0 : toutes suspendues, pas de boucle infinie | 🟡 à valider |
| T6 | 3 tâches : ordre d'exécution entrelacé | 🟡 à valider |

T1-T4 testent **la robustesse** de l'existant. T5-T6 testent les
**cas limites** et révèlent d'éventuels bugs.

## 7. Décision

**C3 est partiellement implémenté** : safepoint, budget,
`evalWithBudget`, requeue automatique. La préemption **fonctionne
pour des tâches dont le coût total < budget**.

**Deux limites connues** :
1. Tâches longues (coût > budget) : boucle infinie tant qu'on ne
   fait pas l'étape 1 (budget croissant) ou 3 (reprise).
2. Code compilé : pas de safepoint MIR → préemption absente en
   natif compilé.

**Priorités recommandées** :
1. **Étape 1** (budget croissant) : 30 min, débloque la robustesse.
2. **Étape 2** (tests) : 1 h, fige le comportement.
3. **Étape 3** (reprise) : chantier structurant, dépend de
   `captureCont` multi-shot (dette connue de `_continuations.md`).
4. **Étape 4-5** (MIR) : après stabilité de l'interprété.

## 8. Références

- `docs/spec/_concurrency.md` §Préemption, §C1, §C3.
- `docs/spec/_continuations.md` — continuations délimitées,
  opérationnelles depuis le 12 octobre 2026.
- `docs/DECISIONS.md:243-245` — décisions C3 et voie B.
- `src/core/engine_expr.zig` — `Engine.reductions`, `evalWithBudget`,
  `evalWithRetry`, safepoint ligne 689.
- `tests/test_scheduler.hvn` — 3 tests coopératifs (sans préemption).

## Mise a jour 2026-10-14

**Livre** :
- Safepoint + budget (`engine.reductions`).
- Fix livelock budget insuffisant (D31).
- `@budget_left` (cooperation).
- A-2 : hook capture conditionnel.
- A-3a : `TaskState.preempted` (reprise par redemarrage).

**Tests** : scheduler 3/3, preemptive 12/12, coop 4/4, split 3/3.

**Modele actuel** : redemarrable. La tache repart du debut sur
budget insuffisant. Pas de reprise exacte -- cout quadratique
mais correct.

**Cible** : reprise exacte via `captureCont` (3a-3b), plan dans
`_capture_eval.md`.
