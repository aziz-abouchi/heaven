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
