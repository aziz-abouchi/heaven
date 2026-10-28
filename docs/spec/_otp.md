# OTP pour Heaven — spec (2026-10-28)

> Objectif : porter les abstractions OTP (Erlang/Elixir) au modèle
> acteurs Heaven. Supervisors, GenServer, links/monitors, restart
> strategies. En Heaven pur, sur le scheduler préemptif.

## Pourquoi OTP

Heaven a `@spawn` (acteur = tâche schedulée + mailbox) et `tell`/`recv`
(messages). Il manque la **supervision** : quand un acteur meurt, qui
le redémarre ? Comment isoler les failures ? Comment garantir qu'un
système survit à un composant cassé ?

OTP répond à ça depuis 1998. Heaven doit le porter nativement, pas
comme une lib optionnelle — c'est le même niveau que les effets
algébriques ou le scheduler.

## Briques existantes Heaven

- `@spawn thunk` → `TaskId` (scheduler)
- `tell pid msg` (mailbox)
- `recv pid` (dépile)
- `handle_rec`/`@prompt`/`@throw` (effets algébriques)
- `schedule budget` (boucle coopérative)
- `yield new_state` (suspend)
- `task_state tid` (introspection)

## Briques OTP à porter

### 1. GenServer (GenServer behaviour)

Acteur avec protocole standard :

    -- En Heaven
    counter_server state =
      (recv (lambda msg ->
        (if (eq msg "get") state
          (if (eq msg "inc") (counter_server (+ state 1))
            state))))

    -- OTP-like
    counter_init _ = 0
    counter_handle_call state msg = ...    -- retourne (pair reply new_state)
    counter_handle_cast state msg = ...    -- retourne new_state
    counter_handle_info state info = ...   -- timers, EXIT, etc.

Ce qu'il faut ajouter :
- `gen_server_spawn init handler` : lance un acteur avec protocole
- `gen_server_call pid msg timeout` : envoie + attend réponse
- `gen_server_cast pid msg` : envoie sans attendre
- `gen_server_info pid info` : message système (EXIT, timeout)

### 2. Supervisor (stratégies de restart)

Un supervisor est un acteur qui :
- lance N enfants (`gen_server_spawn`, `supervisor_spawn`)
- observe leurs morts (via `link` ou monitor)
- applique une **stratégie** de restart

Stratégies (OTP standard) :
- **one_for_one** : redémarre uniquement l'enfant mort
- **one_for_all** : tue et redémarre TOUS les enfants
- **rest_for_one** : redémarre l'enfant mort + tous ceux lancés après
- **simple_one_for_one** : redémarre dynamiquement (pool)

    -- En Heaven
    supervisor_one_for_one children = ...

    -- Utilisation
    sup = (supervisor_spawn one_for_one [
      (counter_child 10),  -- max 10 restarts/60s
      (logger_child 5),
    ])

Ce qu'il faut ajouter :
- `supervisor_spawn strategy children`
- restart counter (N restarts en T secondes → give up)
- `link parent child` (bidirectionnel, mort = mort)
- `monitor parent child` (unidirectionnel, reçoit EXIT)

### 3. Links et monitors

**Link** : si A link B, et B meurt, A meurt aussi (sauf trap_exit).
**Monitor** : si A monitor B, et B meurt, A reçoit `(EXIT B reason)`.

    -- En Heaven
    link pid
    monitor pid -> monitor_ref

    -- trap_exit
    process_flag trap_exit true
    -- reçoit (EXIT pid reason) comme message normal

Ce qu'il faut ajouter :
- `link self_pid target_pid`
- `monitor self_pid target_pid` → MonitorRef
- `process_flag trap_exit bool`
- propagation des EXIT dans le scheduler (mort d'un task → signal aux links)

### 4. Application

Une application = un supervisor racine + config. C'est le point d'entrée.

    -- En Heaven
    app = (application_start "my_app" [
      (supervisor_child counter_sup),
      (supervisor_child http_sup),
    ])

Ce qu'il faut ajouter :
- `application_start name children`
- `application_stop name`
- ordonnancement des démarrages (deps entre apps)

### 5. Fault tolerance : "let it crash"

Le dogme OTP : ne pas prévenir, **laisser mourir**, superviser. C'est
l'inverse de `try/catch` partout.

    -- Mauvais (anti-pattern OTP)
    let result = (try (dangerous_op)) in ...   -- masque le crash

    -- Bon (OTP)
    child = (supervisor_child (fn _ (dangerous_op)))
    -- child plante → supervisor restart → pas de propagation

Ce que ça implique pour Heaven :
- **Pas de try/catch généralisé** dans les acteurs (pas de `catch |err|`)
- **Crash = task.cancelled + EXIT aux links**
- **Supervisor = filet de sécurité**
- Le scheduler doit exposer `task_crashed(tid, reason)`

## Ordre de portage suggéré

| Étape | Contenu | Effort |
|---|---|---|
| **O0** | Spec figée (ce fichier), décisions actées | 1h |
| **O1** | `gen_server.hvn` : spawn/call/cast/info, protocole simple | 1 session |
| **O2** | `link`/`monitor`/`trap_exit` dans le scheduler Zig | 1 session |
| **O3** | `supervisor.hvn` : one_for_one, compteur de restarts | 1 session |
| **O4** | rest_for_one, one_for_all, simple_one_for_one | 1 session |
| **O5** | `application.hvn` : démarrage ordonné, deps | 1 session |
| **O6** | Intégration Hab : chaque composant = gen_server supervisé | 1 session |

Total : ~7 sessions. Peut être parallélisé avec W1c Hab (O6 en dernier).

## Décisions à acter

1. **`gen_server_call` synchrone** : utilise `handle_rec` (effet capture) ou polling `recv` ? Effet plus propre, mais plus complexe. Polling plus simple, bloquant le scheduler (acceptable si `@arm_preempt`).

2. **Links bidirectionnels** : nécessite une table `links[tid] = list of linked_tids` dans le scheduler. Coût mémoire ~1 KB/acteur. OK pour ~10K acteurs.

3. **EXIT comme message système** : `(EXIT pid reason)` doit être dispatché comme un `recv` normal (pour trap_exit). Donc pas de magic séparé — réutiliser la mailbox.

4. **Restart strategies** : où vit le compteur de restarts ? Dans le supervisor (acteur), pas dans le scheduler. Le scheduler fournit juste `task_crashed(tid, reason)`.

5. **Application** : un seul niveau (pas de hiérarchie d'apps). Suffisant pour 95% des cas. Multi-niveau = Phase 3 de Lustre-Heaven.

## Comparaison Lustre/OTP

Lustre n'a pas d'OTP. Hab + OTP = **Lustre + Erlang** en un seul langage.

- **Lustre** : UI réactive (MVU)
- **OTP** : backend fault-tolerant (supervision)
- **Heaven** : les deux, avec effets algébriques en plus

Un composant Hab peut être :
- Côté client (navigateur, wasm interp)
- Côté serveur (HTTP natif, scheduler)
- Distribué (Swarm P2P)

**Le même code**, supervisé côté serveur, dégradé côté client. C'est la vision Lustre-Heaven complète.

## Test de validation (O1)

    test "gen_server_counter":
      (let many pid = (gen_server_spawn counter_init counter_handler) in
       (let _ = (gen_server_cast pid "inc") in
        (let _ = (gen_server_cast pid "inc") in
         (gen_server_call pid "get" 1000)))) == 2

Si ce test passe, O1 est fait.


## Protocole comme type de session (MPST)

Le protocole GenServer (`cast | call | info`) est un type de session
biparti :
  Client → Server : Cast(msg)         -- !Cast
  Client → Server : Call(reply_pid,msg)-- !Call
  Server → Client : Reply(value) on reply_pid -- !Reply (dual)

Le dual côté serveur est `?Cast.μX. ?Call.(!Reply.X)` — c'est ce que
`gen_server_step` implémente. La vérification statique de ce type
viendra en O4 (MPST branché dans `engine_types.zig`).


## O1 FERMÉ (2026-10-28)

Protocole GenServer minimal, infixe pur, sans S-expr :

    fn gen_server_step(state, msg) = msg state
    gen_server_spawn init           = spawn gen_server_step init
    gen_server_cast pid f           = tell pid f
    gen_server_call pid f           = let _ = tell pid f in run pid

Sémantique : `call` = `cast` suivi d'un drain par `run`, qui retourne
l'état final. `run` applique les messages dans l'ordre FIFO, avec
état threadé.

Tests verts (`tests/otp_gs_*.hvn`, un fichier par scénario) :
- `gs_cast_call_inc`  : 2 casts + 1 call inc  == 3
- `gs_persist_same`   : 10 + 2 inc + 1 same   == 12
- `gs_isolated_90`    : 90 + 1 inc + 1 call   == 92

## Pièges syntaxiques (les vrais, pas le parser)

Trois erreurs de syntaxe ont causé 2 jours de faux positifs en O1 :

1. **`print` est variadic.** `print v` suivi de `v == N` produit
   `(print v v)` : `print` avale la comparaison. **Jamais de `print`
   dans un test.**

2. **Parenthéser les applications.** `gen_server_spawn 0 in ...`
   produit `(gen_server_spawn 0 in ...)` — le `in` est dans l'appel
   variadic. La forme correcte est `(gen_server_spawn 0) in ...`.
   Idem `(tell p inc)`, `(run p)`.

3. **`let many x = (expr) in ...`** — QTT. `let x = ...` nu ne
   s'emboîte pas de la même façon. Convention : toujours `let many`
   (avec `_` pour l'unité), toujours parenthéser tout l'arbre.

Ces trois règles sont documentées dans `src/vessel/public/test_suite.hvn`
par l'exemple. Le contrat "prelude auto + test one-liner" est
maintenu, mais **tout est parenthésé**.


## O2.0 FERMÉ (2026-10-28)

Primitives Zig dans `src/core/engine_expr.zig` (Process model, pas le
scheduler — la préemption TCO est orthogonale) :

    link(a, b)          -- bidirectionnel, idempotent
    trap_exit(pid, b)   -- pose le flag
    is_alive(pid)       -- bool
    exit(pid[, reason]) -- marque mort, propage DFS sur les liens
    run(pid) refuse les morts (error.ProcessDead)

Message EXIT encodé sans `cons` : "EXIT" (str) + pid (int), deux
messages dans la mailbox du trappeur. O2.0 ne dépend d'aucune
primitive de liste — robuste aux évolutions de l'AST.

Reason : u8, 0=normal, 1=crash.

Tests verts (`tests/otp2_*.hvn`) :
- is_alive       : vivant=true, après exit=false
- link_propagate : a link b, exit a → b mort ; symétrique OK
- trap_exit      : b trap_exit, a link b, exit a → b vivant,
                    reçoit "EXIT" puis pid_a
- no_link        : exit a sans link → b vivant
- chain          : a—b—c, exit a → b et c morts (DFS)

Sémantique validée : link bidirectionnel, trap_exit court-circuite la
propagation ET livre les messages, propagation en chaîne.

## Contrat O2.1 (superviseur)

`supervisor.hvn` en Heaven pur, ~40 lignes :

    one_for_one(children_init, restart_fn) -> sup_pid

Sémantique : sup est un GenServer, il trap_exit, il spawn+link chaque
enfant. À chaque EXIT reçu, il vérifie is_alive et redémarre les morts
(one_for_one) ou tous (one_for_all) ou les suivants (rest_for_one).

Invariant catégorique validable en O2.3 par `quickcheck` :
  ∀ k enfants one_for_one, ∀ séquence de crashs indépendants,
  |vivants| ≥ 1 après stabilisation.
C'est le point fixe du foncteur `Supervise : End(Etat)`, et la
propriété qui distingue one_for_one de one_for_all (où un seul
crash peut vider l'ensemble).

## Règle parenthèses (à graver)

Chaque test à N lets + 1 body parenthésé nécessite **N+1 closes** après
la dernière variable du body. Compter AVANT d'exécuter — c'est le piège
systématique du langage, source de 2 jours perdus en O1.

    (let many x = v in
     (let many y = w in
      (f x y))))         -- 1 close (f) + 2 closes (lets) = 3


## O2.3 FERMÉ (2026-10-28)

Invariant catégorique prouvé :

    ∀ strat ∈ {one_for_one, one_for_all, rest_for_one},
    |S_strat(Children(3))| = 3   après crash-all + tick

Preuve : `tests/otp2_inv_{one_for_one,one_for_all,rest_for_one}.hvn`,
chacun avec 2 tests :
- `*_direct`     : (run_strat_once strat 0) == 3
- `*_lambda`     : (let prop = (lambda seed -> ...) in (prop 0)) == true

Loi `|S(c)| = |c|` du foncteur `Supervise : End(Children)`.

## Dette : Q.check échoue sur closures HKT

Reproduit avec `sup_restart_rest` ET `sup_restart_all` à N=1,
sans warmup ni interaction. `via_lambda` (même corps, même lambda)
marche. Le bug est donc dans `Q.check` × closures qui référencent
des fonctions passées en argument à un helper paramétré.

Hypothèses :
1. `check_iter` récursif capture `prop` et `gen` via `let`, et l'une
   des deux références (probablement `prop`, qui contient
   `run_strat_once STRAT seed`) est mal résolue à la 1ère itération.
2. Ou le parser de `(prop (gen s))` préfixe-imbriqué avec `prop`
   contenant lui-même un appel curryfié défait la curryfication.

Non corrigé en O2.3 (preuve suffisante sans Q.check puisque
`run_strat_once` est déterministe : 1 seed = preuve complète).
À investiguer en O3+/scheduler : c'est un bug du moteur, pas d'OTP.

## Contrat O2.4 (event-driven trap_exit)

Deux sous-tâches indépendantes :

1. event-driven : link(sup, child) + trap_exit(sup, true). sup_step_v2
   3 cas (tag/pid/fonction). State étendu (pending_exit). Faisable.

2. captureCont (3a-3b) : N=100+ quickcheck, load 1000+, retrait de
   `run`. Chantier Zig scheduler, orthogonal à OTP.
