<!-- HEAVEN:ci-checklist -->
# Checklist pre-commit (a jour 2026-11-03)

Le commit c03c1aa a passe 5/5 en local mais echoue en CI (fixture non
versionnee). Le commit ad24926 a passe test-files mais echoue en CI
(`zig build test` non verifie). Deux incidents, deux lecons.

## Les 5 commandes obligatoires

AVANT tout commit :

    zig build -Doptimize=ReleaseFast
    zig build test
    HEAVEN_NO_LEAK_CHECK=1 zig build -Dnetwork=false test-files
    zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
    zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall

Toutes vertes. Pas d'exception. `test-files` seul ne suffit PAS
(ne couvre pas les tests Zig). ReleaseFast seul ne suffit PAS
(ne couvre pas Debug). Natif seul ne suffit PAS (ne couvre pas WASM).

## Script de verif rapide

`bash scripts/ci-preflight.sh` simule un checkout propre et lance
build+test-files. Voir ci-dessus pour les 3 autres commandes.

## Tests .hvn exhaustifs — `scripts/test_all_hvn.sh` (2026-11-03)

`check_all.sh` ne couvre que ~5 fichiers `.hvn` sur 247 (audit 2026-11-03).
Script complémentaire couvre **165 tests .hvn bloquants** :

    scripts/test_all_hvn.sh

- Lance `tests/*.hvn` + `imports/`, `hvn_pl/`, `optics/`, `hab/`, `eval/`.
- Whitelist `scripts/test_all_hvn_known_fails.txt` (bigint D20, cyc_a/b, exp_util).
- Timeout 10s, exit 1 si échec.
- **Complémentaire**, pas remplacement de `ci-preflight.sh`.
- À intégrer dans `check_all.sh` une fois whitelists résolues (P0.5).

## Environnement : wasmtime cassé (2026-11-04)

Symptôme : `tests.sh` → 5 FAIL WASM. `smoke.sh` dit `obtenu=` vide.

Cause : `/home/aabouchi/.local/bin/wasmtime` cassé — `libgcc_s.so.1 not found`
+ interpréteur `ld-linux` manquant dans `/gnu/store/yj053cys...-glibc-2.41/`.

**Ce n'est PAS un bug Heaven.** 4 FAIL = wasmtime cassé, 1 FAIL =
`build.sh` skip wasm par condition. Fix : réinstaller wasmtime
(`guix install wasmtime` ou binaire statique GitHub releases).

Le binaire WASM `.wasm` se produit bien en manuel
(`zig build -Dtarget=wasm32-freestanding` → 592 KB, rc=0).

**Règle** : si `smoke.sh` échoue sur WASM, vérifier `wasmtime --version`
en premier. Si cassé, ignorer — c'est de l'environnement.

## Historique des pieges

| Commit | Cause | Cout |
|---|---|---|
| c03c1aa | Fixture non versionnee (heaven_test_io.txt) | 2h |
| ad24926 | `zig build test` non verifie | 1h |


## Regle affinee (2026-10-19) — nature du changement

Les 5 commandes ci-dessus ne sont obligatoires que si un fichier
`.zig` est modifie. Pour un `.hvn` pur :

| Changement | Commandes requises |
|---|---|
| `.zig` modifie | les 5 (build, test, test-files, wasm-fs, wasm-wasi) |
| `.hvn` modifie, importe par aucun test | aucun build ; relancer le test qui l'utilise si pertinent |
| `.hvn` modifie, importe par un test | `./zig-out/bin/heaven --run-tests tests` (binaire direct) **ou** `scripts/test_all_hvn.sh` (scope complet, whitelist) |
| `.hvn` + `.zig` melanges | les 5 |

Raison : le binaire `heaven` est un interpreteur. Tant qu'il n'est
pas recompile, un changement `.hvn` est immediatement actif dans le
binaire existant. Faire `zig build` revient a recompiler un binaire
identique.

**Anti-pattern observe** : 5 `zig build` pour un changement dans
`stdlib/dns.hvn` (aucun `.zig` touche). Cout ~2 min pour rien.
