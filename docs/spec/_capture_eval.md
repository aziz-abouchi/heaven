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

## Etat 2026-10-14 (soir)

**A-2 livre** : hook conditionnel `engine.capturing` + push/pop
dans `evaluate`. Inerte en usage normal (capturing=false par
defaut). Non-regression validee.

**A-3a livre** : `TaskState.preempted` + reprise par redemarrage.
`test_preemptive_split` 0/2 -> 3/3.

**Note tests Zig** : les tests unitaires A-2 places dans
`engine_expr.zig` cassaient bigint/hashmap/parser. Hypothesis :
specialisation `CaptureStack.init(std.testing.allocator)` fuit
dans le binaire ReleaseFast. Tests retires (commit bbaa798).
Tests d'integration `.hvn` couvrent la fonction.

**A-3b (prochain)** : reprise exacte via `captureCont`.
Effort 2-3 sessions. Voir les 4 obstacles chiffres ci-dessus.
