#!/usr/bin/env bash
# bench/run.sh — compare les 3 backends sur un ou plusieurs .hvn
# Usage : bench/run.sh <prog.hvn> [N] [--loop M]
set -e
PROG="${1:?usage: run.sh <prog.hvn> [N] [--loop M]}"
shift
N="${1:-10}"
shift || true
LOOP_ARG=()
if [ "$1" = "--loop" ] && [ -n "$2" ]; then
    LOOP_ARG=(--loop "$2")
fi

HEAVEN=./zig-out/bin/heaven

echo "=== interprète ==="
if [ ${#LOOP_ARG[@]} -gt 0 ]; then
    echo "(interprète ne supporte pas --loop, mesuré sans)"
fi
$HEAVEN --run-test "$PROG" 2>&1 | grep -E "wall time|peak mem"

echo ""
echo "=== QBE natif ==="
$HEAVEN bench-qbe "$PROG" "$N" "${LOOP_ARG[@]}" 2>&1 | grep -E "BENCH|min|median|mean|energy|temp|rss"

echo ""
echo "=== WASM (wasmtime) ==="
$HEAVEN bench-wasm "$PROG" "$N" "${LOOP_ARG[@]}" 2>&1 | grep -E "BENCH|min|median|mean|energy|temp"
