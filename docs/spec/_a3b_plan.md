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

## Etat d'avancement (2026-10-16)

### A-3b-2c TERMINE

Sous-etapes commitees :
- 3320722 : Frame +args_done +args_left (champs declaratifs)
- 0dad51c : hook push remplit args_left pour .apply
- d69e801 : Frame.args_done_len:u8 (R2) + CaptureStack.topMut()
- 0d42d4b : markArgDone + instrumentation ctor
- 591e40d : markArgDone dans evalFunction
- b2911b7 : markArgDone dans la boucle TCO
- 4c9700c : markArgDone sur tous les sites d'eval d'args (11 total)
- <a_venir> : test unitaire args_done_len survit a captureCont

Strategie retenue : R2 (voir _a3b_resume_strategy.md).
args_done_len est rempli (compteur), captureCont le preserve (test).
Contrainte : args supposes purs (re-eval au resume).

### A-3b-2d (a venir)

Brancher captureCont dans les 4 sites pending_capture :
- engine_expr.zig:1086 (yield_task)
- engine_expr.zig:1253
- engine_expr.zig:1328
- engine_expr.zig:2143

Chaque site : remplacer le marqueur par un appel reel a
captureCont(capture_stack, prompt, allocator), stocker le
Continuation dans la tache ou le CaptureRecord.

## Etat d'avancement (2026-10-16, 2d)

### A-3b-2d TERMINE

Sous-etapes commitees :
- 210a9b8 : PendingCapture +cont:?Continuation + releasePendingCapture
- b5a7a26 : captureCont dans @throw (throw_to_prompt)
- b545709 : captureCont dans resume_from_k + perform

**Decision yield (2d-4)** : Option A — pas de capture pour `yield`.
Raison : le scheduler (engine_expr.zig:1183) traite yield_task en
lisant `cap.new_state` puis `task.state = .ready` ; il ne consomme
jamais de Continuation. Une capture pour yield serait morte et
couteuse. Documente ici, skip.

**Test d'integration (2d-5)** : differe a A-3b-3. Le champ
`pending_capture.cont` n'est pas observable depuis un test .hvn ;
il sera teste en A-3b-3 quand throwCont du scheduler sera cable et
qu'un resume produira un effet observable.

### A-3b-3 (prochain)

Cabler throwCont dans le scheduler : remplacer le `releasePendingCapture`
brut par une vraie reprise (deplacer le Continuation dans la tache,
re-executer les frames capturees). Necessite de definir :
- Representation du resume dans SchedulerTask.
- Politique de duree de vie de la Continuation.

## Risque

Eleve. `evaluate` est appele 56 fois, le hook A-2 est inerte
mais pas verifie sous charge.
