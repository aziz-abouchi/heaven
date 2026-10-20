# Actors a la Erlang + green threads -- plan (2026-10-20)

## Etat actuel

Scheduler cooperatif (src/runtime/scheduler/) : tasks, add_task,
schedule, yield, task_state, budget de reductions, .preempted
vs .blocked (A3A-PREEMPT). Teste (test_scheduler, test_preemptive_coop).

Magics existants :
- @spawn : dummy (retourne 1, n'execute rien).
- @go : dummy (retourne SUCCESS_FROM_ZIG).
- add_task, schedule, yield, task_state : fonctionnels.

Ce qui manque :
- Pas de mailbox par actor.
- Pas de @send / @recv.
- Pas de receive bloquant (yield + retry).
- Pas de table PID -> task_id -> mailbox.
- Pas de supervision (link, monitor, exit signal).
- Pas de distribution reseau.

## Architecture cible (5-10 sessions)

### Phase 1 -- actor minimal (2 sessions)

Zig (engine_expr.zig) :
- @spawn f args : cree une task avec body = (f args), retourne task_id.
- Table engine.actors : AutoHashMap(u64, Actor) avec
  Actor { pid, task_id, mailbox: ArrayListUnmanaged(Id), status }.
- @send pid msg : append msg a mailbox[pid], reveille l'actor si endormi.
- @recv pid : si mailbox non vide, pop ; sinon yield + retry (cooperatif).

.hvn (stdlib/actors.hvn) :
  actor_start f = (@spawn f unit)
  actor_send pid msg = (@send pid msg)
  actor_recv pid = (@recv pid)

Test : producer/consumer minimal, 2 actors, 10 messages.

### Phase 2 -- receive + supervision (2 sessions)

- receive avec pattern matching sur messages.
- link / monitor / exit (signal de mort propage).
- Actor restart sur crash (1 strategie : one-for-one).

### Phase 3 -- green threads (2-3 sessions)

Le scheduler actuel est cooperatif sur AST. Pour de vraies green
threads :
- Stack switching (ucontext, ou CPS transform).
- Ou : garder CPS + yield explicite (pas de preemption reelle).

Effort : 2-3 sessions. Decision archi a trancher.

### Phase 4 -- distribution (5+ sessions)

- Serialisation messages (JSON ou binaire).
- Transport TCP (@net_* existant).
- Table peers distribuee (ex-net2.known_peers).
- Sync / handshake / cluster membership.

## Effort total

- Phase 1 (actor minimal) : 2 sessions.
- Phase 2 (receive + supervision) : 2 sessions.
- Phase 3 (green threads reelles) : 2-3 sessions.
- Phase 4 (distribution) : 5+ sessions.

Total : 11-14 sessions. Hors scope court terme.

## Priorite vs autres chantiers

La closure capture (section 2 de _closure_capture_bug.md) et
effects-consolidation sont prioritaires (debloquent Fantasy Land
complet, Classy Optics, semantique handle_rec). Actors = chantier
separe, peut demarrer apres.

## Faisable maintenant (1 session) ?

Non. Phase 1 = 2 sessions minimum (Zig + tests). Le dummy @spawn
retournant 1 est un placeholder ; le remplacer necessite la table
actors + mailbox + receive cooperatif.

Trace : plan ci-dessus. Session fraiche.

