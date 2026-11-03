#!/usr/bin/env bash
# scripts/test_all_hvn.sh — lance tous les tests .hvn bloquants.
# Phase A : informatif (sortie 1 si échec, mais pas encore branché sur check_all).
#
# Usage:
#   scripts/test_all_hvn.sh              # timeout 10s, résumé
#   scripts/test_all_hvn.sh --timeout 30 # timeout custom
#   scripts/test_all_hvn.sh --list-failed # juste la liste des échecs
#   scripts/test_all_hvn.sh --with-negative # inclut tests/negative
#
# Exit : 0 si tous verts (scope bloquant), 1 sinon.

set -u
cd "$(dirname "$0")/.."

HEAVEN="./zig-out/bin/heaven"
TIMEOUT=10
LIST_FAILED=0
WITH_NEGATIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --list-failed) LIST_FAILED=1; shift ;;
    --with-negative) WITH_NEGATIVE=1; shift ;;
    *) echo "arg inconnu: $1"; exit 2 ;;
  esac
done

PASS=0; FAIL=0; TIMEOUTS=0; SKIP=0
KNOWN_FAILS_FILE="scripts/test_all_hvn_known_fails.txt"
declare -A KNOWN_FAILS
if [ -f "$KNOWN_FAILS_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] && KNOWN_FAILS["$line"]=1
  done < "$KNOWN_FAILS_FILE"
fi
FAILED=(); TIMED_OUT=()

run_one() {
  local f="$1"
  if [ -n "${KNOWN_FAILS[$f]:-}" ]; then
    SKIP=$((SKIP+1))
    echo "  ⊘  $f (whitelist)"
    return
  fi
  local out rc
  out=$(timeout "$TIMEOUT" "$HEAVEN" --run-test "$f" 2>&1) || rc=$?
  rc=${rc:-0}

  if [ "$rc" -eq 124 ]; then
    TIMEOUTS=$((TIMEOUTS+1)); TIMED_OUT+=("$f")
    [ "$LIST_FAILED" -eq 0 ] && echo "  ⏱  $f"
    return
  fi

  local total
  total=$(echo "$out" | grep "Total:" | tail -1 | sed 's/.*Total: //; s/[^0-9 /]//g')
  if [ -z "$total" ]; then
    FAIL=$((FAIL+1)); FAILED+=("$f")
    [ "$LIST_FAILED" -eq 0 ] && echo "  ✗  $f (crash/parse)"
    return
  fi

  local n m
  n=$(echo "$total" | awk -F'/' '{print $1}' | tr -d ' ')
  m=$(echo "$total" | awk -F'/' '{print $2}' | tr -d ' ')

  if [ "$n" = "$m" ] && [ "$m" != "0" ]; then
    PASS=$((PASS+1))
    [ "$LIST_FAILED" -eq 0 ] && echo "  ✓  $n/$m  $f"
  else
    FAIL=$((FAIL+1)); FAILED+=("$f")
    [ "$LIST_FAILED" -eq 0 ] && echo "  ✗  $n/$m  $f"
  fi
}

# Scope bloquant (Phase A)
for f in tests/*.hvn \
         tests/imports/*.hvn \
         tests/hvn_pl/*.hvn \
         tests/optics/*.hvn \
         tests/hab/*.hvn \
         tests/eval/*.hvn ; do
  [ -f "$f" ] || continue
  case "$f" in *.hvn.skip|*.bak) continue ;; esac
  run_one "$f"
done

if [ "$WITH_NEGATIVE" -eq 1 ]; then
  for f in tests/negative/*.hvn ; do
    [ -f "$f" ] || continue
    run_one "$f"
  done
fi

echo
echo "═══════════════════════════════════════════════"
echo "  ✓ $PASS passed    ✗ $FAIL failed    ⏱ $TIMEOUTS timeout    ⊘ $SKIP skipped"
if [ "$FAIL" -gt 0 ] || [ "$TIMEOUTS" -gt 0 ]; then
  echo "───────────────────────────────────────────────"
  echo "  Échecs (${#FAILED[@]}) :"
  for f in "${FAILED[@]}"; do echo "    $f"; done
  if [ "$TIMEOUTS" -gt 0 ]; then
    echo "  Timeouts (${#TIMED_OUT[@]}) :"
    for f in "${TIMED_OUT[@]}"; do echo "    $f"; done
  fi
fi
echo "═══════════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && [ "$TIMEOUTS" -eq 0 ]
