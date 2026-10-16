# A-3b : reprise exacte (plan)

**Date** : 2026-10-16
**Effort** : 2-3 sessions.
**Statut** : planifie, pas demarre.

## Constat

`Frame` a seulement `{prompt, position, env}`. Insuffisant pour
reconstituer une evaluation suspendue au milieu d'un arbre.

Les 4 sites `pending_capture` (engine_expr.zig:1077, 1244,
1319, 2134) posent un marqueur mais ne capturent pas la pile.

## Approche

Transformer `evaluate` en machine a etats explicite :

    Frame = struct {
        id: Id,              // expression en cours
        depth: u32,
        env: u64,            // pointeur env
        args_done: []Id,     // args deja evalues (pour .apply)
        op: ?Id,             // operateur en attente
    }

Chaque appel `evaluate` empile une Frame. Un `SuspendRequested`
devient une CaptureStack entiere, sauvegardee dans la tache.

## Cible test

    test "resume at depth":
      let t = add_task (lambda s -> rec_cd50 50) 0 in
      schedule 5 then schedule 10000 then task_state t == 0

Aujourd'hui : la tache est perdue (bloquee). Apres A-3b :
elle reprend a profondeur 5.

## Etapes (2-3 sessions)

1. **A-3b-1** : struct Frame enrichi + push/pop dans evaluate
   (aucun changement de comportement, hook A-2 actif).
2. **A-3b-2** : sites pending_capture -> captureCont reel.
3. **A-3b-3** : throwCont dans schedule + test resume.

Chaque etape commitable, tests C3 existants doivent rester verts.

## Risque

Eleve. `evaluate` est appele 56 fois, le hook A-2 est inerte
mais pas verifie sous charge.
