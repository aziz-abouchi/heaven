# Bug : target_os == "linux" retourne false (2026-10-20)

## Symptome
    (print (target_os))          -- affiche "linux"
    (target_os) == "linux"       -- false (devrait etre true)

## Impact
Impossible de dispatcher OS en .hvn pur. `lib/random.hvn` niveau 2
(urandom) doit etre appele explicitement sur Linux au lieu d'etre
auto-dispatch.

## Cause probable
`target_os` retourne un Symbole interné, `"linux"` est une String.
`==` ne compare pas par contenu entre Sym et Str. Voir fossile H1
(pattern.exprStructuralEq, math.structuralEq) -- meme classe de bug.

## Fix
1 session .zig, `evalCmp` / `structuralEq` : normaliser Sym<->Str.
Priorite : basse (workaround = appel explicite).

## Workaround
`rand_os_linux S` (import explicite) ou LCG portable.
