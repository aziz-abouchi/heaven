# Benchmarking Heaven — méthodologie et résultats

**Date** : 2026-09-30
**Statut** : document vivant. Chiffres sur une machine donnée (voir §Machine).
**But** : mesurer les 3 backends (interprète, QBE natif, WASM)
avec une méthodologie reproductible, sur CPU, mémoire, énergie,
température.

## Commandes

Trois commandes CLI symétriques :

    heaven bench-interp <src.hvn> [N] [--loop M]   # in-process
    heaven bench-qbe    <src.hvn> [N] [--loop M]   # binaire natif
    heaven bench-wasm   <src.hvn> [N] [--loop M]   # wasmtime

Sémantique :
- **N spawns** (ou évaluations) de l'expression cible.
- **M itérations internes** : le programme lui-même répète son corps
  M fois avant de produire un résultat. Amortit le coût de spawn
  ou de bootstrap (wasmtime ~5 ms, fork+exec ~0.8 ms).
- **Warmup hors chrono** : 1 run préalable pour éliminer les coûts
  de compilation JIT/aiguillage.

Les 3 mesures rapportent **wall**, **cpu** (user+sys), **energy**
(RAPL), **temperature** (thermal_zone), **RSS pic**.

## Programmes de bench

Dans `bench/progs/` :

| Fichier | Forme | Sens |
|---|---|---|
| `count_down.hvn` | `fn count_down(n, acc) = (if (= n 0) acc (count_down (- n 1) (+ acc 1)))` puis `(count_down 100000 0)` | récursion non-tail, arith + branchement |
| `arith.hvn` | `fn sum_squares(n, acc) = (if (= n 0) acc (sum_squares (- n 1) (+ acc (* n n))))` puis `(sum_squares 100000 0)` | récursion non-tail, multiplication |
| `loop.hvn` | `count_up 1000000` | itération pure, mesure du dispatch |

## Méthode `bench/run.sh`

    bash bench/run.sh <prog.hvn> [N] [--loop M]

Lance les 3 backends dans l'ordre :
1. Interprète (in-process, warmup exclu)
2. QBE natif (spawn + binaire compilé)
3. WASM (spawn + wasmtime)

Grep les lignes utiles (wall, cpu, energy, temp, rss).

## Limites connues

### RAPL (énergie)

Depuis la CVE-2020-8694, le kernel restreint la lecture de
`/sys/class/powercap/intel-rapl/*/energy_uj` aux processus root. Un
`sudo chmod +r` fonctionne mais doit etre refait a chaque reboot.
Pour rendre la lecture permanente :

    bash scripts/setup-rapl.sh [groupe]     # defaut : users

Le script detecte la plateforme et propose la methode adaptee :

| Plateforme | Action |
|---|---|
| Guix System | snippet `/etc/config.scm` + `guix system reconfigure` |
| NixOS | snippet `configuration.nix` + `nixos-rebuild switch` |
| Distro classique (root) | installe `/etc/udev/rules.d/99-rapl-readable.rules` |

Dans tous les cas, la regle accorde la lecture (`0440`) au groupe
specifie. Verification :

    ls -la /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj
    # attendu : -r--r----- root users

Sans ce fix, `bench-qbe` et `bench-wasm` retournent une energie nulle
ou une erreur de permission.
`/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj` est root-only
depuis CVE-2020-8694. Pour l'activer :

    sudo chmod +r /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj

Non persistant entre boots (une udev rule serait nécessaire). Si
inaccessible, `bench-*` rapporte `energy : indisponible`.

L'énergie mesurée inclut tout ce que le package CPU consomme
pendant le bench — y compris les processus système concurrents.
Précision de la mesure : ~1 J sur une fenêtre de plusieurs secondes.

### Température
Le die met plusieurs secondes à chauffer. Sur des benchs courts
(< 5 s), `delta = 0.0 C`. Pour voir une variation, il faut des
runs de 30 s+ (`--loop` élevé).

### TCO WASM/QBE (2026-10-01)
Les self-tail-calls sont transformes en boucle dans `mir_qbe.zig`
et `mir_wat.zig` : un `call_user` terminal vers la fonction
courante devient un saut au bloc d'entree. Consequence : plus
besoin de `-W max-wasm-stack=67108864`, la pile native reste
petite. `count_down 10000000` compile et tourne sur les deux
backends. La TCO ne couvre pas encore la recursion mutuelle ni
les trampolines multi-fonctions.

### Interprète en `--run-test` vs `bench-interp`
`time ./heaven --run-test <file>` mesure le processus complet :
startup + init + warmup + mesure. `bench-interp` mesure l'expression
seule (warmup exclu). Comparer les deux donne ~2× d'écart, ce qui
est normal.

## Machine

Toutes les mesures sur :

- CPU : à préciser (`lscpu | grep "Model name"`)
- OS : Guix System (Linux x86_64)
- RAPL : Intel RAPL package
- wasmtime : 49.0.1
- QBE : v1.2 (release officielle c9x.me)
- Zig : 0.15.2

## Résultats — `count_down 100000 0`

Commande :

    bash bench/run.sh bench/progs/count_down.hvn 5 --loop 1000

Total mesuré : 5 spawns × 1000 itérations = 5000 tours.

| Backend | CPU median total | CPU / count_down | Énergie / count_down |
|---|---|---|---|
| **Interprète** | 3500 ms (1 tour) | **~3500 ms** | ~141 J |
| **QBE natif** | 296 ms (5000 tours) | **~0.059 ms** | ~2.3 mJ |
| **WASM** | 568 ms (5000 tours) | **~0.113 ms** | ~4.7 mJ |

**Speedup QBE vs interprète** : ~59 000×.
**Speedup WASM vs interprète** : ~31 000×.
**QBE vs WASM** : QBE ~2× plus rapide.

## Résultats — `arith.hvn` (`sum_squares 100000 0`)

Commande :

    bash bench/run.sh bench/progs/arith.hvn 3 --loop 100

Total : 3 spawns × 100 itérations = 300 tours.

| Backend | CPU median total | CPU / tour | Énergie / tour |
|---|---|---|---|
| **Interprète** | 4456 ms (1 tour) | ~4456 ms | — |
| **QBE natif** | 36 ms (300 tours) | **~0.12 ms** | ~5.4 µJ × 1000 |
| **WASM** | 61 ms (300 tours) | **~0.20 ms** | ~10 µJ × 1000 |

## Résultats — `loop.hvn` (`count_up 1000000 0`)

Commande :

    bash bench/run.sh bench/progs/loop.hvn 3 --loop 100

Total : 3 spawns × 100 itérations = 300 tours.

| Backend | CPU median total | CPU / tour |
|---|---|---|
| **Interprète** | 34 708 ms (1 tour) | ~34 700 ms |
| **QBE natif** | 442 ms (300 tours) | **~1.47 ms** |
| **WASM** | 880 ms (300 tours) | **~2.93 ms** |

Le programme `loop` est 10× plus long que `count_down` en interprète
(1M itérations vs 100k). Le ratio natif reste cohérent (~1.5 ms vs
~0.06 ms, donc ~25× — proportionnel au nombre d'itérations).

## Résultats — `fib.hvn` (`fib 25` = 75025)

Commande (5 runs, sans `--loop`) :

    ./zig-out/bin/heaven bench-interp bench/progs/fib.hvn 5
    ./zig-out/bin/heaven bench-qbe    bench/progs/fib.hvn 5
    ./zig-out/bin/heaven bench-wasm   bench/progs/fib.hvn 5

`fib` n'est **pas** tail-recursive : la TCO ne s'applique pas.
Chaque backend paie le cout complet de l'arbre de recursion
(~242 786 appels de fonction pour fib(25), aucun n'est memoise).
L'ecart interp/natif vient du cout par appel, pas d'une
optimisation d'arbre.

| Backend | CPU median | CPU min | CPU max |
|---|---|---|---|
| **Interprète** | 29 215 ms | 28 886 ms | 29 884 ms |
| **QBE natif** | **1.50 ms** | 1.48 ms | 1.60 ms |
| **WASM** | 6.75 ms | 6.59 ms | 7.31 ms |

Ratio interp / QBE ≈ **19 500×**.
Ratio QBE / WASM ≈ **4.5×** (wasmtime surcoût).

`bench-wasm fib` a longtemps timeoute a cause de la pile native
non bornee (chaque frame WASM grossissait sans limite). Le TCO
du 2026-10-01 a supprime ce besoin : la mesure passe desormais
sans flag `-W max-wasm-stack`.

## Interprétation

1. **QBE ≈ 2× WASM** : wasmtime ajoute un surcoût de runtime (bounds
   checks, dispatch indirect, bytecode sandboxing). Pour du calcul
   pur, QBE est le choix optimal.

2. **Interprète / natif = 30 000× - 60 000×** : l'écart vient du
   tree-walking récursif de `engine_expr.evaluate`, qui alloue à
   chaque `apply`, `if`, `-`, `+`. Le natif compile en instructions
   machine directes.

3. **Énergie proportionnelle au CPU** : ~10-20 W pendant l'exécution
   selon la charge. Utile pour `optimize for energy` (spec
   `_metrics.md`).

4. **Température insensible** : sur 3-5 secondes de bench, le die
   ne chauffe pas assez pour voir un delta. Nécessite des runs de
   30 s+ (`--loop` beaucoup plus élevé).

## Ce qu'on ne mesure pas encore

- **Instructions retirées** : `perf_event_open` (root only aussi).
- **Cycles CPU** : idem.
- **Cache misses** : idem.
- **Précision RAPL par cœur** : RAPL package uniquement, pas
  RAPL core/dram (il faudrait lire d'autres fichiers `intel-rapl:0:N`).
- **Compilation time** : le temps de `qbe + cc` (compilation du
  binaire) et le bootstrap wasmtime ne sont pas isolés dans le
  bench ; ils sont dans le warmup.

## Suites possibles

1. **TCO WASM** (`mir_wat`) : convertir la récursion tail en boucle
   WASM, supprimer le besoin de `max-wasm-stack`.
2. **TCO QBE** : idem pour `mir_qbe`, sans effet sur la correction
   mais gain mémoire.
3. **Plus de programmes** : `fib(n)` récursif, allocs de structures,
   I/O.
4. **`_metrics.md` : injection dans l'EGraph** — la boucle complète
   `Metrics -> EGraph -> Proof`.
5. **`optimize for energy`** : implémenter la sélection par profil.
