# Bug : target_os == "linux" retourne false (2026-10-20)

## Symptome
    (target_os) == "linux"        -- TRUE (apres fix 2026-10-20)
    target_os == "linux"          -- FALSE (bug parser)

## Deux bugs distincts

### Bug 1 (resolu 2026-10-20) : evalCmp comparait Sym IDs
`evalCmp` case .str comparait `sa == sb` (Sym IDs) au lieu des bytes.
Fix : `std.mem.eql(u8, ra, rb)` sur les bytes resolus.
Test "c" passe maintenant.

### Bug 2 (ouvert) : target_os sans parens = symbole bare
`target_os == "linux"` parse `target_os` comme `sym(target_os)`,
pas comme `apply(sym(target_os), [])`. Compare `sym` vs `lit.str`
-> exprStructuralEq retourne false (tags differents).

## Workaround
Toujours ecrire `(target_os) == "..."` (parens forcent l'appel 0-arg).

## Fix Bug 2
1 session parser : magics 0-arg connus doivent etre parsés comme
apply(sym, []) en position infixe. Non bloquant.

## Impact
Dispatch OS en .hvn : possible avec `(target_os)` mais pas sans
parens. Workaround documenté dans _session_continuity.md.
