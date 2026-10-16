<!-- HEAVEN:ci-checklist -->
# Checklist pre-commit (a jour 2026-10-16)

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

## Historique des pieges

| Commit | Cause | Cout |
|---|---|---|
| c03c1aa | Fixture non versionnee (heaven_test_io.txt) | 2h |
| ad24926 | `zig build test` non verifie | 1h |
