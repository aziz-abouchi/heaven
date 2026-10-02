#!/bin/bash
# scripts/smoke.sh — smoke test des backends compiles.
#
# Compile et execute les cas TCO critiques sur QBE et WASM.
# A lancer apres `bash build.sh`.
#
# Usage :
#     bash scripts/smoke.sh

set -u
cd "$(dirname "$0")/.." || exit 1

HEAVEN=./zig-out/bin/heaven
HEAVEN_NO_LEAK_CHECK="${HEAVEN_NO_LEAK_CHECK:-1}"
export HEAVEN_NO_LEAK_CHECK

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  OK   $name : $actual"
        PASS=$((PASS+1))
    else
        echo "  FAIL $name : attendu=$expected obtenu=$actual"
        FAIL=$((FAIL+1))
    fi
}

if [ ! -x "$HEAVEN" ]; then
    echo "smoke.sh : $HEAVEN introuvable. Lance 'bash build.sh' d'abord."
    exit 1
fi

# --- QBE (natif) ---
echo "--- QBE (natif) ---"
$HEAVEN compile-qbe bench/progs/mutual.hvn -o /tmp/smoke_mutual_qbe >/dev/null 2>&1
check "QBE mutual isEven 100M = 1" "1" "$(/tmp/smoke_mutual_qbe)"

$HEAVEN compile-qbe bench/progs/triple.hvn -o /tmp/smoke_triple_qbe >/dev/null 2>&1
check "QBE triple f 1M = 200" "200" "$(/tmp/smoke_triple_qbe)"

$HEAVEN compile-qbe bench/progs/fib.hvn -o /tmp/smoke_fib_qbe >/dev/null 2>&1
check "QBE fib 25 = 75025" "75025" "$(/tmp/smoke_fib_qbe)"

$HEAVEN compile-qbe bench/progs/count_down.hvn -o /tmp/smoke_cd_qbe >/dev/null 2>&1
check "QBE count_down 100k = 100000" "100000" "$(/tmp/smoke_cd_qbe)"

# --- WASM (wasmtime) ---
if command -v wasmtime >/dev/null 2>&1; then
    echo "--- WASM (wasmtime) ---"
    $HEAVEN compile-wasm bench/progs/mutual.hvn -o /tmp/smoke_mutual.wat >/dev/null 2>&1
    check "WASM mutual isEven 100M = 1" "1" "$(wasmtime run --invoke main /tmp/smoke_mutual.wat 2>/dev/null | tail -1)"

    $HEAVEN compile-wasm bench/progs/triple.hvn -o /tmp/smoke_triple.wat >/dev/null 2>&1
    check "WASM triple f 1M = 200" "200" "$(wasmtime run --invoke main /tmp/smoke_triple.wat 2>/dev/null | tail -1)"

    $HEAVEN compile-wasm bench/progs/fib.hvn -o /tmp/smoke_fib.wat >/dev/null 2>&1
    check "WASM fib 25 = 75025" "75025" "$(wasmtime run --invoke main /tmp/smoke_fib.wat 2>/dev/null | tail -1)"

    $HEAVEN compile-wasm bench/progs/count_down.hvn -o /tmp/smoke_cd.wat >/dev/null 2>&1
    check "WASM count_down 100k = 100000" "100000" "$(wasmtime run --invoke main /tmp/smoke_cd.wat 2>/dev/null | tail -1)"
else
    echo "--- WASM : wasmtime absent, skip ---"
fi

echo ""
echo "Total: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
