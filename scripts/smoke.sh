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

# --- D10 : extern_call via prefixe @nom ---
echo "--- D10 extern_call ---"
cat > /tmp/smoke_extern.hvn <<'HEOF'
fn main() = (@write 1 0 0)
main
HEOF
$HEAVEN compile-qbe /tmp/smoke_extern.hvn -o /tmp/smoke_extern_qbe >/dev/null 2>&1
if nm -D /tmp/smoke_extern_qbe 2>/dev/null | grep -q "U write"; then
    echo "  OK   QBE @write -> U write@GLIBC"
    PASS=$((PASS+1))
else
    echo "  FAIL QBE @write absent de nm -D"
    FAIL=$((FAIL+1))
fi

# --- D10 : raw_syscall (interpreteur) ---
echo "--- D10 raw_syscall ---"
cat > /tmp/smoke_getpid.hvn <<'HEOF'
(+ 1000 (raw_syscall 39 0 0 0))
HEOF
RESULT=$($HEAVEN run /tmp/smoke_getpid.hvn 2>&1 | grep -E '^[0-9]+$' | head -1)
if [ -n "$RESULT" ] && [ "$RESULT" -gt 1000 ]; then
    echo "  OK   raw_syscall getpid = $RESULT"
    PASS=$((PASS+1))
else
    echo "  FAIL raw_syscall : obtenu '$RESULT' (attendu > 1000)"
    FAIL=$((FAIL+1))
fi

# --- D12 memoization ---
echo "--- D12 memoization ---"
cat > /tmp/smoke_memo.hvn <<'HEOF'
twice t = (+ (force t) (force t))
(twice (delay 99))
HEOF
RESULT=$($HEAVEN run /tmp/smoke_memo.hvn 2>&1 | grep -E '^[0-9]+$' | head -1)
if [ "$RESULT" = "198" ]; then
    echo "  OK   twice (delay 99) = 198"
    PASS=$((PASS+1))
else
    echo "  FAIL twice (delay 99) : '$RESULT' (attendu 198)"
    FAIL=$((FAIL+1))
fi


# --- D10 Path C : link freestanding (stubs + _start custom) ---
echo "--- D10 Path C (HEAVEN_NO_LIBC=1) ---"
cat > /tmp/smoke_boot.hvn <<'HEOF'
(@heaven_syscall6 60 42 0 0 0 0 0)
HEOF
HEAVEN_NO_LIBC=1 $HEAVEN compile-qbe /tmp/smoke_boot.hvn -o /tmp/smoke_boot >/dev/null 2>&1
if [ -x /tmp/smoke_boot ]; then
    /tmp/smoke_boot
    RC=$?
    if [ "$RC" = "42" ]; then
        echo "  OK   freestanding exit=42, statique"
        PASS=$((PASS+1))
    else
        echo "  FAIL freestanding exit=$RC (attendu 42)"
        FAIL=$((FAIL+1))
    fi
    if ldd /tmp/smoke_boot 2>&1 | grep -q "not a dynamic"; then
        echo "  OK   ldd -> not a dynamic executable"
        PASS=$((PASS+1))
    else
        echo "  FAIL ldd: dynamic linkage detectee"
        FAIL=$((FAIL+1))
    fi
else
    echo "  FAIL freestanding: binaire non produit"
    FAIL=$((FAIL+1))
fi

# --- D12 laziness : delay/force ---
echo "--- D12 laziness ---"
cat > /tmp/smoke_lazy1.hvn <<'HEOF'
(force (delay 42))
HEOF
RESULT=$($HEAVEN run /tmp/smoke_lazy1.hvn 2>&1 | grep -E '^[0-9]+$' | head -1)
if [ "$RESULT" = "42" ]; then
    echo "  OK   force (delay 42) = 42"
    PASS=$((PASS+1))
else
    echo "  FAIL force (delay 42) : obtenu '$RESULT' (attendu 42)"
    FAIL=$((FAIL+1))
fi

cat > /tmp/smoke_lazy2.hvn <<'HEOF'
(force (delay (+ 1 2)))
HEOF
RESULT=$($HEAVEN run /tmp/smoke_lazy2.hvn 2>&1 | grep -E '^[0-9]+$' | head -1)
if [ "$RESULT" = "3" ]; then
    echo "  OK   force (delay (+ 1 2)) = 3"
    PASS=$((PASS+1))
else
    echo "  FAIL force (delay (+ 1 2)) : obtenu '$RESULT' (attendu 3)"
    FAIL=$((FAIL+1))
fi

echo ""
echo "Total: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
