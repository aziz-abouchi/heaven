# Perf baseline — Heaven

Mesures datées pour détecter les régressions.

## 2026-10-29 (machine devilHope Linux)

### Binaire
- `zig build -Doptimize=ReleaseFast` → 24 071 544 octets (24 MB, debug_info)
- Après `strip` → 9 358 136 octets (9.3 MB, stripped)
- `file` : ELF 64-bit, x86-64, dynamically linked

### Build
- **Non mesuré** (cache `.zig-cache/o` cassé par rm, build à refaire)
- Modules : 170 (`addModule` + `root_source_file`)
- Signal : > 60 s à froid = audit nécessaire

### Tests
- `heaven test tests/otp_gs_basic.hvn` (2 tests) : 1,5 s total, 1,2 ms utile
- `heaven test tests/` (54 fichiers, ~500 tests) : **0,206 s**
- Boucle `for f in tests/*.hvn` (54 invocations) : **44,9 s**
- Overhead startup : ~1,4 s par invocation (parse + imports `core/std/*`)

### Constat
- Tests batch = **218× plus rapides** que la boucle
- Overhead startup > travail utile pour 1 fichier
- Build lent = 170 modules, à auditer

## Prochaine mesure à faire

Après strip permanent + audit modules :
- Build à froid (< 60 s cible)
- Build à chaud (< 2 s cible)
- Binaire strippé (< 10 MB cible, déjà OK)
