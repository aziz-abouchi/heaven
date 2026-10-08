#!/bin/bash
# D20 workaround : stack illimitee pour les tests BigInt > 500.
# A lancer en root, ou si le hard limit le permet.
#
# Usage : bash scripts/run-tests-with-stack.sh
#
# Le tree-walker recursif de Heaven consomme ~40 KB par niveau
# utilisateur. Sur 8 MB, ~200 niveaux. Au-dela : segfault.
# Ce script augmente la stack pour les cas qui depassent.

ulimit -s unlimited 2>/dev/null || ulimit -s 65536

cd "$(dirname "$0")/.." || exit 1

for t in "$@"; do
    echo "=== $t ==="
    HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-test "$t"
done
