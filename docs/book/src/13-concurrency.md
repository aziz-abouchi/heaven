# Chapitre 14 — Concurrence coopérative

Heaven fournit un **scheduler coopératif** dans le noyau. Plusieurs
tâches partagent le thread principal, chacune cédant la main à des
points explicites (`yield`).

## Le modèle

Une **tâche** est une fonction `state -> résultat` qui peut céder la
main. Sa signature :

    body s = ...
      si fini : retourne le résultat
      sinon   : (yield new_state)

Le scheduler alterne entre les tâches à chaque `yield`.

## Créer une tâche

    t = (add_task body init_state)

`add_task` retourne un **task_id** (entier). L'état initial est
passé en second argument.

## Exécuter les tâches

    (schedule budget)

`schedule` boucle : pour chaque tâche prête, l'évalue avec un
budget de `budget` réductions. Quand le budget est épuisé, la
tâche est remise en queue. Quand toutes les tâches sont finies,
`schedule` retourne.

## Exemple : compter jusqu'à 5

    body s = (if (= s 5) s (yield (+ s 1)))
    main u =
      let t = (add_task body 0) in
      let _ = (schedule 1000) in
      (task_state t)

`task_state` lit l'état courant d'une tâche. Résultat : `5`.

## Exemple : deux tâches entrelacées

    b1 s = (if (= s 3) 99 (yield (+ s 1)))
    b2 s = (if (= s 5) 99 (yield (+ s 1)))
    main u =
      let t1 = (add_task b1 0) in
      let t2 = (add_task b2 0) in
      let _ = (schedule 1000) in
      (+ (task_state t1) (task_state t2))

Résultat : `99 + 99 = 198`. Le scheduler a alterné entre les deux
tâches : chaque `yield` a cédé la main à l'autre.

## Combien de temps une tâche tourne-t-elle ?

`schedule` prend un **budget de réductions**. Chaque appel à
`evaluate` décrémente le compteur. À 0, la tâche est suspendue.

Un budget de 1000 signifie : "laisse la tâche faire ~1000 appels
d'évaluation avant de redonner la main". Utile pour borner les
tâches qui font du calcul lourd sans `yield`.

## Modèle coopératif, pas préemptif

Le scheduler **n'interrompt pas** une tâche arbitrairement. Deux
cas de cession :

1. **`yield` explicite** dans la tâche.
2. **Budget épuisé** → la tâche est relancée depuis le début à la
   prochaine itération (modèle *redémarrable*).

Ce n'est donc pas du **vrai** multitâche préemptif : une tâche qui
ne fait aucun `yield` et dépasse son budget redémarre. Pour du
préemptif exact, il faudrait capturer la pile Zig — c'est le
chantier Voie B (continuations délimitées complètes).

## Limites v0

- **Redémarrage, pas reprise** : si le budget épuise une tâche,
  elle recommence depuis son état initial au prochain tour.
- **Pas de priorités** : la structure `Policy` existe (`.priority`,
  `.edf`) mais n'est pas encore utilisée par `schedule`.
- **Pas d'intégration avec `spawn`/acteurs** : deux modèles
  concurrents qui coexistent.

## Pour aller plus loin

- `tests/test_scheduler.hvn` : 3 tests (sans yield, avec yield,
  deux tâches entrelacées).
- `docs/DECISIONS.md` D8 : la décision de design.
- `docs/spec/_concurrency.md` : plan complet (C1-C5, Voie B).

---

Treize chapitres plus tard, tu sais écrire, typer, prouver, exécuter,
et faire coopérer. Il est temps d'**ouvrir le capot**. Le dernier
chapitre montre comment tout cela tient ensemble : les 6 primitives
du noyau, le tree-walker, le compilateur, et pourquoi ces choix
pèsent sur chaque décision du langage.
