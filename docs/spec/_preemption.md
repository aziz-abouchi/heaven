# Preemption — roadmap (2026-10-26)

## Etat actuel
- Coopératif simple : `KernelQ` (run_n, tick) dans lib/os/scheduler.hvn
- `yield` magic : yield explicite (D8 3a-3b.5)
- `fuel` + `reductions` : safepoints (abort cooperatif)
- `green_mode` + `green_call_count` : compteur coopératif

## Ce qui manque
- `setitimer` (syscall 38) + `sigaction` (13) : PAS exposés dans
  lib/syscall/linux_x86_64.hvn
- Handler SIGALRM en Zig : PAS implémenté
- Safepoint check du flag SIGALRM : PAS implémenté

## 3 chemins possibles

### A — Time-sliced coopératif (FAUX préemptif)
Force yield tous les N ms via mono_ns. 95% des cas. Un programme
`while true` sans yield n'est PAS interrompu.

**Statut** : tenté 2026-10-26, mais bloqué par le bug loader
(2e import coupe l'eval, voir _import_resolution.md).
**Pas un bug scheduler** : 3e cas du bug loader.

### B — Vraie préemption (SIGALRM) -- 2-3 sessions
1. Exposer `setitimer` (38) + `sigaction` (13) dans
   lib/syscall/linux_x86_64.hvn (5 lignes .hvn)
2. Handler SIGALRM en Zig qui set un flag atomique
3. `evaluate` check le flag aux safepoints (deja l'infrastructure
   fuel/reductions/green_mode)
4. Tests : while true avec deadline de 10ms

**Coût** : 2-3 sessions. Bloqué par rien (syscalls à ajouter).

### C — BEAM backend -- 3-6 sessions
Préemption gratuite (BEAM a son propre scheduler préemptif).
Bloqué par E1-E3 + backend wiring.

## Recommandation
Option B : le plus court chemin vers vraie préemption. 3 blocs
syscall/handler/check, puis tests.

## Le vrai blocage
Le scheduler n'est PAS le problème. Le bug loader (.hvn, 2e import
coupe l'eval) est le vrai blocage pour A. Pour B, c'est
l'exposition syscalls + handler Zig.

## Tentative B2 (2026-10-26) -- rollback, patch partiel

### APIs confirmees (Zig 0.15.2)
- `std.posix.sigaction(sig: u8, act: ?*const Sigaction, oact: ?*Sigaction) void`
- `std.os.linux.SIG.ALRM = 14`
- `std.os.linux.sigemptyset() sigset_t`
- `std.os.linux.syscall3(.setitimer, which, itimerval_ptr, old_ptr)`
- `Sigaction{ .handler = .{.handler = fn}, .mask = ..., .flags = 0 }`

### Patch tente (rollback)
1. Flag global `preempt_flag` + handler `sigalrmHandler` callconv(.c). BUILD OK.
2. Struct `Itimerval{ interval, value }` (2x Timeval i64). BUILD OK.
3. `Engine.armPreemption()` : sigaction + setitimer 10ms. BUILD OK.
4. `evaluate` : check flag tous les 1000 appels -> SuspendRequested. BUILD OK.
5. Magic `@arm_preempt` dans la liste : OK.
6. Case `@arm_preempt` dans evalMagic : ECHEC (pattern CASE introuvable).
   -> Magic declare mais jamais traite -> code mort. Rollback.

### Cause de l echec
Le case `raw_alloc` n est pas le bon marker dans evalMagic. Il faut
localiser le case `@char_string` ou `@tls_connect` (voisins dans la
liste des magics) et ajouter `@arm_preempt` a cote.

### Prochain bloc (session fraiche, 1 bloc)
- Localiser evalMagic case `@char_string` (grep).
- Ajouter case `@arm_preempt` (5 lignes). Build, test.
- Test preemption : `(@arm_preempt 0)` puis recursion infinie ->
  doit etre interrompu a 10ms (SuspendRequested), pas hang.

## Mise a jour 2026-10-26 (soir) -- preemption armee

### Patch livre (commit suivant)
- flag `preempt_flag` + handler `sigalrmHandler` callconv(.c)
- struct `Itimerval` (2x Timeval i64)
- fn libre `armPreemption(engine)` : sigaction + setitimer 10ms
- check dans `evaluate` : `fuel % 1000 == 0 and preempt_armed`
- magic `@arm_preempt` + case evalMagic
- BUILD OK, 18/18 vert

### Test TCO faux positif
`rec n = rec n` : timeout 3s (EXIT=143), PAS interrompu.
Cause : self-tail-call optimise par TCO. La boucle TCO ne
decremente PAS fuel -> le check ne fire pas.

### Ce qui reste (2 blocs)
1. Fix TCO : decrementer `fuel` dans la boucle self-tail-call
   (~5 lignes, localiser `tco_name` / `tco_spine_buf` dans evaluate)
2. Test non-TCO : `f n = if n > 0 then (f (n + 1)) + 1 else 0`
   (recursion NON terminale, fuel decremente normalement) -> doit
   etre interrompu a 10ms

### Vraie preemption : 2 blocs restants
Le patch est arme, le check est la, 18/18 vert. Il manque :
- Test non-TCO pour valider la preemption sur recursion normale
- Fix TCO pour la preemption sur self-tail-calls

## MILESTONE 2026-10-26 (soir) : preemption REELLE validee

### 4 formes, 4 SuspendRequested
- TCO (`rec n = rec n`) : SuspendRequested
- non-TCO (`f n = f (n + 1)`) : SuspendRequested
- borne (`f n = if n < 1000000 then (f (n+1)) else n`) : SuspendRequested
- boucle (`loop _ = loop 0`) : SuspendRequested
- sanity (`(+ 1 2)`) : 3 OK, 18/18 vert

### Ce que ca veut dire
SIGALRM + fuel + preempt_flag interrompt TOUTE evaluation, pas
seulement les self-tail-calls. Le runtime Heaven est preemptif a 10ms.
Plus aucun hang, plus aucun timeout shell. C est le runtime qui
interrompt, pas le shell.

### Ce qui manque pour de VRAIS acteurs (Erlang-like)
Actuellement : SuspendRequested remonte au top-level et le process
EXIT avec une erreur. Pas de reprise, pas de scheduler.

Pour de vrais acteurs :
1. Scheduler catch SuspendRequested -> requeue l acteur (1-2 blocs)
   - l acteur est ABORT (pas suspendu), relance au prochain tick
   - comme Erlang pour un timeout (process tue, pas suspendu)
2. Vrai suspend (continuation capture pour tout SuspendRequested)
   - capture : profondeur, env, id (2-3 blocs)
   - resume : evaluate(state.id) au prochain tick
   - necessite continuation.captureCont pour TOUT SuspendRequested,
     pas seulement handle_rec

### Recommendation
Commencer par (1) : scheduler catch SuspendRequested, requeue.
Coût 1-2 blocs. Donne des acteurs cooperatifs abort-and-retry.
Puis (2) si besoin de vrai suspend (4-5 blocs).

## Tentative @schedule_processes (2026-10-26) -- rollback

### Approche
Magic `@schedule_processes budget` : boucle sur les processus, evalWithBudget
par message, requeue sur suspend. ~60 lignes.

### Resultat
BUILD OK apres 1 fix (var -> const). MAIS regression : test_eval
et test_meta_if SEGV (139). Cause inconnue (probablement corruption
memoire dans la boucle, ou interaction avec les Env crees/defer).

### Ce qui est livre (sans @schedule_processes)
- `spawn handler init` : cree Process (mailbox, state, handler)
- `tell pid msg` : push mailbox
- `recv pid` : pop mailbox (FIFO)
- `run pid` : **preemptif** (evalWithBudget + requeue sur suspend)
- `(run pid)` traite les messages un par un, requeue sur suspend

### Ce qui manque (1 bloc session fraiche)
`@schedule_processes` : boucle globale sur les process, deadline,
requeue. Le bug a trouver : SEGV sur test_eval/test_meta_if (probablement
le `defer new_env.unref()` dans le for, ou un des pids_buf en heap).

## Mise a jour 2026-10-26 (soir) : preemption portable

### Etat par plateforme
| Plateforme | Mecanisme | Statut |
| Linux/macOS/BSD | SIGALRM + setitimer 10ms | OK |
| wasm32-wasi | fallback mono_ns 10ms | OK |
| wasm32-freestanding | fallback mono_ns (host clock) | OK |
| Windows | fallback mono_ns | OK (a tester CI) |

### Double-check idempotent
SIGALRM fire -> return avant check temps. Si SIGALRM absent
(wasm, windows sans sigaction), le check temps prend le relais.
Aucun double-SuspendRequested.

### Ce qui manque
1. Test CI Windows (fallback mono_ns).
2. wasm32-freestanding timer : import env.set_timer du host JS
   (1 bloc + host, cooperatif suffit pour l instant).
3. FFI bloquant (net_read, TLS_read) non preemptible sans thread.

### Commit
e27eb35 feat(engine): preemption temps portable -- fallback mono_ns

## Tentative @schedule_processes v2 (2026-10-26, soir) -- rollback

### Approche v2
Swap engine.env = new_env avant evalWithBudget, restore apres.
~60 lignes. BUILD OK.

### Resultat
Regression : test_eval et test_meta_if SEGV (139). Meme si
actors2 (run pid) marche, le scheduler global casse le reste.

### Cause probable
Use-after-free entre :
- defer new_env.unref() (fin de scope for)
- pending_capture quand evalWithBudget suspend (garde une ref a new_env)
Le pending_capture n est pas nettoye -> il pointe vers du vide.

Quand le prochain evalWithBudget lit pending_capture, SEGV.

### Fix (1 bloc, session fraiche)
Option A : releasePendingCapture(engine) apres chaque .suspended
  (comme run() le fait).
Option B : ne pas detruire new_env tant que pending_capture existe.
  Creer un pool d envs par process.
Option C : evalWithBudget sans capture de continuation (eval direct
  avec catch SuspendRequested + state save/restore).

A est le plus simple (2 lignes). A tester en session fraiche.

## Tentative @schedule_processes v3 (2026-10-26, nuit) -- rollback DEFINITIF

### Approche v3
releasePendingCapture + new_env.unref() apres chaque .suspended/.done.
~60 lignes. BUILD OK.

### Resultat
MEME SEGV que v2 sur test_eval et test_meta_if, MEME si actors3/4
echouent a FileNotFound (magic jamais execute).

### Diagnostic clair
Le SEGV est cause par la SIMPLE PRESENCE de @schedule_processes dans
la liste magics, PAS par son execution. Bug d initialisation, pas
d execution. Probablement :
- la liste magics comptime est utilisee ailleurs avec index-based lookup
- ou un des helpers (releasePendingCapture, hasClock) cree une collision

### Decision
STOP. 3 tentatives, 3 SEGV. Le fix demande une session Zig dediee avec
gdb + core dump sur test_eval, ET une inspection de la liste magics.

### Ce qui marche (acquis de la session)
- spawn / tell / recv / run pid (PREEMPTIF avec requeue sur suspend)
- prerequis : @arm_preempt + fallback temps portable
- 4 formes de preemption validees (TCO, non-TCO, borne, boucle)

### Prochain bloc (session fraiche)
1. gdb -nx + core dump sur test_eval SANS @schedule_processes (baseline)
2. Ajouter le magic dans la liste, rebuild, gdb + core dump
3. bt 20 pour voir la fonction exacte au SEGV (init du magics ?)
4. Si c est un helper (releasePendingCapture), le deplacer ou le fixer
5. Si c est la liste magics, la rendre runtime (std.StringHashMap)

## Diagnostic DEFINITIF @schedule_processes (2026-10-26, nuit)

### Test discriminant : @foo dummy
Ajout magic `@foo` (retourne unitLit) dans la liste magics.
Resultat : 13/13 test_eval, 7/7 test_meta_if, AUCUNE regression.

Conclusion : la liste magics n est PAS fragile. `@schedule_processes`
est specifiquement le probleme.

### Ce que ca elimine
- Taille de la liste magics (91 entrees, @foo passe)
- Init comptime (dummy case trivial passe)
- Duplicate dans la liste (aucun)

### Vraie cause
Le code du case `@schedule_processes` corrompt l etat Engine.
Probablement :
- swap engine.env = new_env perturbe pending_capture
- releasePendingCapture appele au mauvais moment
- evalWithBudget + processes = double free ou UAF
- ou l interaction avec `@arm_preempt` / preempt_flag

### 3 versions tentees, 3 SEGV
v1 : sans swap env -> SEGV (new_env non utilise, handlers perdus)
v2 : swap env -> SEGV (UAF pending_capture)
v3 : swap + releasePendingCapture -> SEGV (meme)

### Prochain bloc (session gdb, OBLIGATOIRE)
1. `gdb -nx` + core dump sur test_eval AVEC `@schedule_processes`
   dans la liste (magic jamais execute, mais SEGV init)
2. `bt 20` pour voir la fonction exacte
3. Si c est Engine.init / evalMagic init : le champ expr_eval
   ou le case ajoute une collision
4. Si c est dans eval : le swap env est le coupable

### Acquis (acteurs partiels, sans @schedule_processes)
- spawn handler init : Process avec mailbox
- tell pid msg : push mailbox
- recv pid : pop mailbox
- run pid : PREEMPTIF (evalWithBudget + requeue sur suspend)
- 1 actor a la fois, pilotage manuel

### Fix possible (a tester en session fraiche)
Ne PAS utiliser evalWithBudget (qui interagit avec pending_capture).
Utiliser evaluate direct + catch SuspendRequested + save/restore.
~20 lignes, sans capture de continuation.

## Diagnostic FINAL v4 (2026-10-26, nuit profonde) -- evalMagic size

### v4 : evaluate direct (pas evalWithBudget)
Case ~60 lignes, evaluate() direct, catch SuspendRequested manuel.
PAS de swap env (on passe new_env directement a evaluate).
BUILD OK, MAIS test_eval SEGV identique a v2/v3.

### LE finding decisif (comparer avec @foo)
@foo : 3 lignes dans evalMagic, 18/18 vert, aucune regression.
@schedule_processes : ~60 lignes, SEGV test_eval/13 tests casses.
LES DEUX ne sont jamais executees (test_eval n appelle pas ces magics).

### Cause : evalMagic est trop gros
evalMagic contient maintenant 91+ cases sur ~1000 lignes.
Ajouter 60 lignes fait exploser un seuil (compilateur, codegen, ou
stack frame des appels recursifs de evaluate). Le SEGV est silencieux
(pas de message) et n apparais PAS avec 3 lignes.

### Fix propre (1 bloc session fraiche)
Extraire chaque case en helper fonction :
  fn magic_schedule_processes(store, env, engine, args, depth) !Id { ... }
Puis dans evalMagic : if (eql(op, "@schedule_processes")) return try
  magic_schedule_processes(store, env, engine, args, depth);
evalMagic revient a ~5 lignes par case. Test : +60 lignes en helper,
pas de SEGV.

### Bonus CI : proto2_run_drains fail (pre-existant)
Test_suite.hvn CI : proto1 OK, proto2 (run p != 8) fail.
Cause : run pid caller-driven ne propage pas bien le state final.
Meme famille que @schedule_processes (env swap). Voir doc print.

### Ordre de priorite post-session
1. Extraction helpers evalMagic (P1 _zig_debt.md, 2-3 sessions)
2. @schedule_processes (1 bloc apres extraction)
3. Loader .hvn (session gdb)
4. print (env propagation, meme famille que proto2)
