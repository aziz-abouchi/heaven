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
- `heaven test tests/` : **0,24 s, 0 tests lancés** — la commande n'exécute PAS les tests du dossier (no-op silencieux). **Dette.**
- Boucle `for f in tests/*.hvn` (54 invocations) : **44,9 s**
- Overhead startup : ~1,4 s par invocation (parse + imports `core/std/*`)

### Constat
- Tests batch : **n'existe pas** (no-op). La boucle 44,9 s est le vrai coût. Optimisation réelle = cache parser (session 2) ou batch mode (à implémenter).
- Overhead startup > travail utile pour 1 fichier
- Build lent = 170 modules, à auditer

## Prochaine mesure à faire

Après strip permanent + audit modules :
- Build à froid (< 60 s cible)
- Build à chaud (< 2 s cible)
- Binaire strippé (< 10 MB cible, déjà OK)


## 2026-10-29 — corrections

- `heaven test tests/` échouait avec `error: IsDir` (routing cassé).
  Fix : `test_cmd.zig` détecte dir vs file.
- `runTestDir` existe (test_runner.zig:328) mais spawn 1 subprocess
  par fichier. Vitesse : identique à la boucle shell (~45 s pour 54
  fichiers).
- **Vrai gain 10× à faire** : `runTestDir` avec engine réutilisé
  (pas de spawn par fichier). Session 2 du plan perf.


## 2026-10-29 — fixes appliqués

- `.strip = true` dans `build.zig` (createModule) : ✅
  Binaire : 24 MB → ~9 MB, permanent.
- `test_cmd.zig` : détecte dir vs file → route vers `runTestDir`.
- `runTestDir` (existant) spawn 1 subprocess par fichier → ~45 s
  pour 54 fichiers. **Pas de gain vitesse**, juste IsDir fixé.
- Vrai gain 10× = engine réutilisé (session 2, TODO).

## Pièges shell documentés

- `cmd | tail; echo "exit: $?"` → mesure `tail`, pas `cmd`.
  Toujours : `cmd > file 2>&1; CODE=$?; echo $CODE`.
- `rm -rf .zig-cache/o` casse tree-sitter (C lib non reconstruite).
  `rm -rf .zig-cache` (tout) force un rebuild propre.
