<!-- HEAVEN:a3b-resume-strategy -->
# A-3b : stratégie de reprise au milieu d'un `.apply`

**Date** : 2026-10-16
**Statut** : décision à valider (R2 pressenti)

## Constat

`evaluate` est un tree-walker récursif. Aucun point unique n'observe
"arg i vient d'être évalué". Les args sont consommés magic par magic
(`if` évalue args[0], `tuple` itère, `seq` itère), via `evalFunction`
(user fns), dans la boucle TCO, dans le dispatch ctor, dans le
dispatch env.

Conséquence : au moment d'un `SuspendRequested`, remonté par `try`
à travers N frames, on ne sait pas quel arg du `.apply` parent
était en cours.

## Trois stratégies

### R1 — Trampoline explicite
Chaque magic évalue **un seul** arg par appel. Boucle externe pilote.
Machine à états complète.

- ✅ Reprise exacte, robuste.
- ❌ Réécrit ~50 magics. Effort 1-2 sessions. Risque élevé (hot path).
- ❌ Modifie la structure de contrôle ; incompatible avec le hook
  push/pop actuel en une passe.

### R2 — Marqueur par frame (recommandé)
Chaque `Frame` de type `.apply_op` porte `args_done_len: u8`.
Avant `evaluate(arg_i)`, on met à jour `frame.args_done_len = i`
sur le top de la pile (mutable). Au suspend, la pile contient
l'info exacte.

- ✅ Un seul point d'écriture par magic (le `for` d'éval des args).
- ✅ Zéro allocation, POD pur.
- ✅ Compatible avec le hook push/pop actuel.
- ⚠️ Sur resume, args 0..i-1 doivent être **ré-évalués** (on n'a que
  le compte, pas les valeurs). Implique : args doivent être **purs**
  (pas de `yield`, `@prompt`, `delay` non forcé, effets de bord).
- ⚠️ Nécessite `topMut() *Frame` sur `CaptureStack`.
- ⚠️ Instrumentation à faire sur ~5 sites d'éval d'args (ctor, magic,
  evalFunction, TCO, dispatch env). Un oubli = reprise partielle.

### R3 — Replay intégral (voie B)
Au suspend, on jette l'éval du `.apply` en cours. Au resume, on
rejoue l'appel entier depuis le début.

- ✅ Zéro instrumentation. Implémentation triviale.
- ✅ Fonctionne même pour args impurs.
- ❌ Pas de reprise "exacte". Le budget "doublant à chaque retry"
  mentionné dans le contexte initial.
- ❌ Incompatible avec l'objectif A-3b (reprise exacte).

## Décision

**R2 retenu (à valider).** Compromis acceptable : reprise exacte au
niveau du **compteur d'args**, avec la contrainte "args purs" à
documenter dans le langage.

## Points à trancher en 2c-3

1. `Frame.args_done: []const u64` (plan A-3b initial) devient
   `args_done_len: u8` seul. Les valeurs ne sont pas stockées.
2. `CaptureStack.topMut() *Frame` à ajouter.
3. Les 5 sites d'éval d'args à instrumenter :
   - `evalMagic` ctor branch (engine_expr.zig ~1708)
   - `evalMagic` `.apply` args (engine_expr.zig ~890 pour TCO)
   - `evalFunction` (à localiser)
   - dispatch env (engine_expr.zig ~1740)
   - `evalMagic` magic par magic (if/seq/tuple/...)
4. Test : sur suspend, dump `capture_stack` et vérifier que le frame
   `.apply_op` a bien `args_done_len == i` attendu.

## Effort restant

- 2c-3 : `topMut` + `args_done_len` par frame (1 commit, ~1h).
- 2c-4 : instrumentation des 5 sites (1-2 commits, ~2h).
- 2d : `pending_capture → captureCont réel` (session suivante).
- A-3b-3 : `throwCont` dans schedule + test resume.

## Risque résiduel

Args impurs. Il faudra soit interdire `yield`/`@prompt`/`delay` en
position d'arg dans `.apply`, soit accepter la duplication d'effets
sur resume. À documenter dans `DECISIONS.md` (D-A3B-ARGS-PURITY).


## LIMITE STRUCTURELLE (constat 2026-10-16, post-2d)

Le champ `Frame.env: u64` est un pointeur **brut** vers un `*Env`.
Or `evalFunction` (engine_expr.zig:605) cree son Env **stack-local** :

    var new_env = Env.init(self.allocator);
    defer new_env.deinit();

Quand la pile unwind sur `SuspendRequested`, ces Env sont detruits.
La Continuation capture leurs adresses, mais a la reprise elles
pointent vers de la memoire reutilisee ou invalide.

**Consequence** : R2-strict « resume a l'id du frame » ne peut PAS
fonctionner tel quel. Le 2c-5 (« args_done_len survit a captureCont »)
prouve que la donnee survit ; il ne prouve pas que la pile est
reutilisable. C'est une omission du plan initial.

**Decision** : ouvrir le chantier A-3b-2e (ownership des Env) AVANT
A-3b-3. Voir ci-dessous.

## A-3b-2e : ownership des Env (chantier)

Objectif : rendre les Env capturables sans dangling pointer.

### Option B1 — Arena dediee par capture
Chaque captureCont cree une arena, deep-copie les Env, les stocke dans
la Continuation. A la reprise, l'arena est utilisee. Au deinit() de la
Continuation, l'arena est liberee.

- Avantage : pas de changement global.
- Inconvenient : cout memoire O(N) par capture, N = profondeur.

### Option B2 — Ref-counting global
Env devient `*Env` avec compteur de references. Chaque push de frame
incremente. Chaque pop decremente (et libere si 0). La Continuation
possede ses propres refs.

- Avantage : pas de copie.
- Inconvenient : touche tous les sites Env (init/deinit/get/put), risque
  de fuite ou double-free.

### Option B3 — Arena unique pour l'Engine
Tous les Env vivent dans une arena possedee par l'Engine. Les Env ne
sont jamais deinit() individuellement. L'arena est reset entre deux
« mondes » d'evaluation (top-level, avant un schedule, apres un resume).

- Avantage : zero cout par capture.
- Inconvenient : politique de reset a definir (quand peut-on liberer ?).
  Necessite un invariant clair : aucun Env ne survit au-dela d'un cycle.

### Recommandation
B1 d'abord (local, sur, non intrusif). B3 ensuite en optimisation si
le profiling montre que B1 coute trop.
