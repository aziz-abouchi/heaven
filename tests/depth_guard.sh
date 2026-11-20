#!/usr/bin/env bash
# La récursion profonde doit donner une valeur correcte ou une erreur explicite
# (RecursionLimitExceeded), jamais un SIGSEGV muet (exit 139).
set -u
BIN="${HEAVEN_BIN:-zig-out/bin/heaven}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
run() { printf 'sum_to 0 = 0\nsum_to n = n + sum_to (n - 1)\n(sum_to %s)\n' "$1" > "$T/d.hvn"
        HEAVEN_NO_LEAK_CHECK=1 timeout 120 "$BIN" --eval-file "$T/d.hvn" > "$T/o" 2>&1; echo $?; }
c=$(run 100); [ "$c" = 0 ] && grep -q '^5050$' "$T/o" || { echo "FAIL sum_to 100"; fail=1; }
c=$(run 1000000)
if [ "$c" = 139 ] || [ "$c" = 134 ] || ! grep -q 'RecursionLimitExceeded' "$T/o"; then
  echo "FAIL sum_to 1000000: exit=$c (attendu RecursionLimitExceeded explicite)"; head -3 "$T/o"; fail=1
fi
[ $fail = 0 ] && echo "depth_guard OK"; exit $fail
