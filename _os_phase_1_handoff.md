# OS Phase 1 -- handoff (2026-10-21)

## Phase 1A FAIT (cette session)
- lib/os/kernel.hvn : composition Device + VFS + Scheduler
- tests/test_os_kernel.hvn : 7/7

## Phase 1B (session fraiche, 2 sessions)

### Objectif : MPST V1 multipartite
Reference `_mpst_v2_plan.md` (existe).
- Etendre `stdlib/mpst.hvn` : roles, projection par role
- Protocol a 3+ acteurs (ex: client <-> vfs <-> disk)
- Tests : check dual multi-role

### Objectif : instances OS supplementaires
- `instance Device Disk` (blocs, offsets)
- `instance Device Net` (wraps @net_*)
- `instance Device Timer` (wraps lib/time.hvn)
- Chaque instance = 3-4 fonctions read/write, 5-10 lignes
- Non bloquant

### Objectif : kernel multi-taches
- Scheduler sur liste de tasks + yield
- Bloque par let+recursion (voir _qtt_runtime_bug.md)
- Apres fix .zig let+recursion

## Discipline
- `and`/`or` infixe KO -> `(and a b)` S-expr
- Commentaire `--` inline dans else-if -> ArityMismatch
- Pas de let+recursion (split helpers)
- Tests isoles avant composition

## Ce qui existe deja
lib/os/{device,scheduler,vfs,ipc,kernel}.hvn
tests/test_os.hvn (11/11), test_os_kernel.hvn (7/7)
