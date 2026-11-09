#!/usr/bin/env bash
set -u
H=./zig-out/bin/heaven
P=0; F=0
for f in tests/diff/*.hvn; do
    n=$(basename "$f" .hvn)
    a=$(timeout 10 "$H" run "$f" 2>&1 | grep -vE 'error\(gpa\)|Unable to print|MEMORY LEAK|Memory clean|^\(\)$|^$')
    "$H" compile-qbe "$f" -o "/tmp/$n.q" >/dev/null 2>&1
    b=$([ -x "/tmp/$n.q" ] && timeout 5 "/tmp/$n.q" 2>/dev/null | grep -vE 'Memory clean|^\(\)$|^$' || echo "QBE_NO_BIN")
    # Normalisation : interp affiche true/false (bool), QBE affiche 1/0 (int)
    a_norm=$(echo "$a" | sed 's/^true$/1/; s/^false$/0/')
    if [ "$a_norm" = "$b" ]; then echo "OK  $n"; P=$((P+1)); else echo "FAIL $n: i='$a' q='$b'"; F=$((F+1)); fi
    if command -v wasmtime >/dev/null 2>&1; then
        "$H" compile-wasm "$f" -o "/tmp/$n.wat" >/dev/null 2>&1
        c=$([ -f "/tmp/$n.wat" ] && timeout 5 wasmtime "/tmp/$n.wat" 2>/dev/null | grep -vE 'Memory clean|^\(\)$|^$' || echo "WASM_NO_BIN")
        [ "$a" = "$c" ] && echo "  OK wasm" || echo "  FAIL wasm: i='$a' w='$c'"
    fi
done
echo ""
echo "RESULT: OK=$P FAIL=$F"
exit $F
