# Capture dans evaluate : plan de branchement

**Date** : 2026-10-14
**Statut** : analyse pre-vol. Implementation a planifier.
**But** : documenter le branchement de CaptureStack dans
evaluate, pour la preemption native (A / 3a-3b).

## Probleme

Le tree-walker evaluate (engine_expr.zig) est recursif direct :
chaque appel cree une frame native Zig. Sur SuspendRequested,
la pile native se defait via try, et l'etat intermediaire est
perdu.

Resultat : une tache suspendue au milieu d'une expression ne
peut pas reprendre. Le fix A+B (D31) masque ce probleme en
marquant .blocked -- la tache est perdue.

## Objectif

Faire que evaluate empile une frame logique sur une
CaptureStack a chaque descente, et que cette pile devienne
un objet Continuation sur SuspendRequested. throwCont restaure.

## Obstacles chiffres (inventaire 2026-10-14)

| Site | Nombre |
|---|---|
| Magics evalues par evalMagic | 77 |
| Sites try evaluate(args_snap[i]) dans evalMagic | 30+ |
| Sites try evaluate dans .apply | 3 |
| Boucles for args dans evalMagic | 2 |

## Decision proposee

Wrapper conditionnel dans evaluate :

    if (engine.capturing) {
        try engine.capture_stack.push(.{
            .prompt = engine.current_prompt,
            .position = id,
            .env = @intFromPtr(env),
        });
    }
    defer if (engine.capturing) _ = engine.capture_stack.pop();

Un seul hook, active uniquement par le scheduler (flag
engine.capturing). Overhead nul en usage normal.

## Etapes

- A-1 : pre-vol (ce document).
- A-2 : flag engine.capturing + push/pop conditionnel.
- A-3 : captureCont sur SuspendRequested + reprise.
- A-4 : tests preemptive_split + non-regression complete.
