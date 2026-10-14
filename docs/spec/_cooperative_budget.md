# Budget cooperatif : @budget_left

**Date** : 2026-10-14
**Statut** : livre. Implementation partielle de C3.
**But** : permettre a une tache CPU-bound de cooperer avec le
scheduler en yieldant quand son budget est epuise.

## Primitives

- `(@budget_left)` : retourne `engine.reductions` (u64).
  Retourne 0 quand le budget est epuise.

## Exemple

    rec_coop n =
      (if (= n 0)
        0
        (if (= (@budget_left) 0)
          (yield n)
          (rec_coop (- n 1))))

Une tache `(add_task (lambda s -> (rec_coop 50)) 0)` split en
plusieurs `schedule` progresse et termine.

## Tests

`tests/test_preemptive_coop.hvn` : 3/3 ✓
- 1 schedule suffit (budget 10000).
- Split en 3 schedules (budgets 8, 8, 10000).
- 2 taches entrelacees sur split.

## Note : budget top-level vs budget tache

`@budget_left` au top-level (hors tache) retourne toujours 0 :
le budget est deja consomme par le harness (parser, setup). Le
budget controle existe uniquement dans `evalWithBudget`, appele
par `schedule` sur une tache. Ne pas tester ce magic au top-level.

## Limite

Ce n'est PAS de la preemption. Une tache NON-cooperative
(`rec_cd50 50` sans yield) est bloquee `.blocked` apres
epuisement du budget (fix A+B de D31). La preemption fine
exige `captureCont` (3a-3b), chantier separe.

## Suite

- A (3a-3b) : brancher `CaptureStack` dans `evaluate`, rendre
  `@budget_left` obsolete (yield automatique).
- let : spec `_let_syntax.md` separee, a traiter dans une
  session dediee.
