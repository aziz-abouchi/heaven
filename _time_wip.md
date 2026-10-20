# lib/time.hvn -- WIP (2026-10-20)

## Etat

- `raw_syscall 318` (getrandom) : marche, retourne 4
- `raw_syscall 228` (clock_gettime) : `RecursionLimitExceeded` meme sur
  la forme minimale `f _ = raw_syscall 228 0 0 0` + print
- `(print (X 0))` ou X retourne un raw_syscall : KO (RecursionLimitExceeded)
  Des que X est plus complexe que getrandom direct.

## Suspects (pour session dediee)

1. Dispatch engine-lambda (engine_expr.zig:2820) : `defer delete` retire
   ("thunk"), bindings accumules -> recursion lors du 2e appel ?
2. `print` d'un int negatif (raw_syscall -EFAULT = -14) : boucle ?
3. `raw_syscall 228` specifiquement : `ts=NULL` -> EFAULT, mais pourquoi
   recursion ?

## Test minimal a reprendre en session dediee

    f _ = raw_syscall 318 0 0 0   -- getrandom(NULL, 0, 0) = 0 OK
    f _ = raw_syscall 228 0 0 0   -- clock_gettime : KO ?

Si le premier marche et le second non : c'est le numero 228, pas le pattern.

## Effort

1 session .zig. Priorite : basse (getrandom suffit pour `lib/random.hvn`
OS, time peut attendre).
