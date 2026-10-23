# Runner .hvn — WIP (2026-10-23)

## Statut
Tentative de runner `.hvn` pur pour contourner le bug `test_runner.zig`
(SEGV ~23 statements, voir `_session_continuity.md`).
**Bloqué**, rollback propre, baseline 14/14 préservée.

## Ce qui marche
- `lib/syscall/linux_x86_64.hvn` : getrandom, read, write, openat, close,
  exit_group (déjà existants).
- `fork` + `wait4` + `exit_group` : **fonctionnent** SI le fils ne fait
  qu'`exit_group` (test `/tmp/t_fw2.hvn` → `done`, exit 0).
- `poke_int64` + `string_ptr` : construction d'un argv test OK
  (pointeur retourné, pas de crash).
- `print` depuis `lib/lsp/stdio.hvn` (via `raw_syscall 1 1`) : OK.

## Ce qui NE marche PAS
- `raw_syscall 1 2 "A" 1` (write stderr) : **hang** (exit 124).
  Même `raw_syscall 1 2 (sp "A") 1` hang. Suspect : fd 2 non ouvert
  ou `write` bloque sur pipe non-lu.
- `S.write 2 "done\n" 5` : hang identique.
- Test combiné `fork + write_stderr` : aucun output (même pas avant fork),
  donc fork lui-même n'est pas la cause du premier blocage.
- `fork + execve("./zig-out/bin/heaven", argv, 0)` : timeout 10s
  avec `forking` non flushé — soit deadlock dans le fils (GPA mutex
  hérité de fork), soit execve fail + hang.

## Cause probable (non tranchée, cutoff 3 blocs dépassé)
1. `raw_syscall 1 2` hang = fd 2 absent/fermé dans le contexte `.hvn`,
   ou `raw_syscall` bloque sur write stderr (bug evaluator).
2. `fork` hérite de mutex verrouillés (allocator, interner) et deadlock
   au premier alloc dans le fils.
3. `execve` fail (PATH lookup) → fils retombe sur eval qui hang.

## Fix propre (session Zig dédiée, 3 pistes)
1. Debug `raw_syscall 1 2` hang : ajouter `dprintf` Zig avant/après
   le `@syscall`, vérifier fd 2 côté child process spawné.
2. `fork` : vérifier si le runtime Heaven alloue/lock avant le premier
   eval dans le fils. Si oui, `atexit` ou reset explicite.
3. `execve` : passer chemin absolu (`/home/.../heaven`) au lieu de
   `heaven` (le kernel ne fait pas de PATH lookup).

## Alternative actuelle
- **Runner bash** (hors `.hvn`) : `for f in tests/*.hvn; do
  HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-test "$f"; done`
  Fonctionne (utilisé en session 2026-10-21/23), mais pas auto-hébergé.
- **Fix Zig runner** (`test_runner.zig`) : reset arena entre statements
  (voir `_session_continuity.md`), session dédiée.

## Conclusion
Le chemin `.hvn` pur pour le runner est **fermé pour l'instant** à cause
de `raw_syscall 1 2` hang (incompréhensible sans instrumentation Zig).
Toutes les autres briques (fork+wait4, argv construction, exit_group)
sont validées et documentées.
