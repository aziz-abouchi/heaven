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
