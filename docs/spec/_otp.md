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
