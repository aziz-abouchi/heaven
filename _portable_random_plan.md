# Portable random (2026-10-20)

## Niveau 1 : LCG en .hvn (FAIT)
`lib/random.hvn` : PRNG deterministe, portable partout.
Meme resultat sur toutes plateformes. Pas cryptographique.

## Niveau 2 : vrai random OS via magic (S9)
Le .hvn seul ne peut PAS acceder a l'entropie OS. Il faut un magic
`@random_bytes n` en .zig avec dispatch par plateforme :

| OS | Source | API |
|---|---|---|
| Linux | getrandom (syscall 318) | raw_syscall |
| Android | getrandom (syscall 318) | raw_syscall |
| macOS | getentropy | libc |
| iOS | getentropy | libc |
| Windows | BCryptGenRandom | advapi32 |
| WASI | random_get | wasi_snapshot_preview1 |
| WASM web | crypto.getRandomValues | JS host import |

Implementation : `src/platform/random.zig` (dispatch) + `random_stub.zig`
(wasm fallback). Signature : `pub fn bytes(buf: []u8) !void`.

Puis `lib/random.hvn` :
  urandom n = @random_bytes n   -- string de n octets
  urand_int n = string_to_int (urandom 4) % n  -- int 0..n-1

## Effort S9
1 session .zig : random.zig + random_stub.zig + wiring build.zig
+ tests Zig.
+ 1 bloc .hvn : wrapper + tests.

## Pourquoi pas plus tot
Priorite bugs .zig ouverts (QTT, TLS, leak). Random LCG couvre 90% des
usages (jeux, simulations, tests deterministes). Vrai random = crypto/securite,
debloque quand il y a un besoin reel.

## Non-objectifs
- CSPRNG maison : utiliser l'OS
- HMAC-DRBG custom : overkill
