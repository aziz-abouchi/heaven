#!/usr/bin/env bash
set -o pipefail
cd "$(dirname "$0")/.." || exit 1

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

echo "${BOLD}═══ Zig unit tests ═══${RESET}"
zig_out=$(zig build test --summary all 2>&1)
zig_rc=$?

# Dernière ligne "Build Summary: ... N/M tests passed ..."
summary=$(echo "$zig_out" | grep -oE '[0-9]+/[0-9]+ tests passed[^;]*' | tail -1)
if [ -z "$summary" ]; then
    summary=$(echo "$zig_out" | grep -oE '[0-9]+ tests passed[^;]*' | tail -1)
fi

if [ $zig_rc -eq 0 ]; then
    echo "  ${GREEN}✓${RESET} $summary"
    zig_status="${GREEN}PASS${RESET}"
else
    echo "  ${RED}✗${RESET} $summary"
    echo "$zig_out" | grep -E 'error|failed' | head -5 | sed 's/^/    /'
    zig_status="${RED}FAIL${RESET}"
fi
echo

echo "${BOLD}═══ Heaven integration tests ═══${RESET}"
hvn_pass=0; hvn_fail=0; hvn_files_ok=0; hvn_files_total=0
for f in tests/*.hvn; do
    hvn_files_total=$((hvn_files_total + 1))
    out=$(zig-out/bin/heaven --run-test "$f" 2>&1)
    line=$(echo "$out" | grep -oE 'Total: [0-9]+ / [0-9]+' | head -1)
    p=$(echo "$line" | grep -oE '[0-9]+ /' | tr -d ' /')
    t=$(echo "$line" | grep -oE '/ [0-9]+' | tr -d ' /')
    [ -z "$p" ] && p=0
    [ -z "$t" ] && t=0
    if [ "$p" = "$t" ] && [ "$t" != "0" ]; then
        echo "  ${GREEN}✓${RESET} $(basename "$f") ${DIM}($p/$t)${RESET}"
        hvn_files_ok=$((hvn_files_ok + 1))
    else
        echo "  ${RED}✗${RESET} $(basename "$f") ${DIM}($p/$t)${RESET}"
    fi
    hvn_pass=$((hvn_pass + p))
    hvn_fail=$((hvn_fail + t - p))
done

echo
echo "${BOLD}═══ Récapitulatif ═══${RESET}"
echo "  Zig  : $zig_status    ($summary)"
echo "  HVN  : $hvn_files_ok / $hvn_files_total fichiers    $hvn_pass / $((hvn_pass + hvn_fail)) tests"
