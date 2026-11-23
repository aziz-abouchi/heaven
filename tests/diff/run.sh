#!/usr/bin/env bash
set -u
H=./zig-out/bin/heaven
P=0; F=0
# Tests dont la jambe WASM est CONNUE non supportee (liste explicite, a vider
# quand le tas WASM existera). Un .wat contient toujours des `unreachable`
# (fonctions du prelude utilisant des paires), donc on ne peut pas le deduire
# du fichier genere.
WASM_UNSUPPORTED=""
for f in tests/diff/*.hvn; do
    n=$(basename "$f" .hvn)
    # Le harnais compare des VALEURS : on desactive le leak-check de l'interpreteur
    # (ses traces de pile polluent la sortie). Les fuites sont couvertes par
    # `zig build check` ("Memory clean").
    a=$(HEAVEN_NO_LEAK_CHECK=1 timeout 10 "$H" run "$f" 2>&1 | grep -vE 'error\(gpa\)|Unable to print|MEMORY LEAK|Memory clean|^\(\)$|^$')
    rm -f "/tmp/$n.q" "/tmp/$n.wat"   # jamais de sortie perimee d'un run precedent
    "$H" compile-qbe "$f" -o "/tmp/$n.q" >/dev/null 2>&1
    b=$([ -x "/tmp/$n.q" ] && timeout 5 "/tmp/$n.q" 2>/dev/null | grep -vE 'Memory clean|^\(\)$|^$' || echo "QBE_NO_BIN")
    # Normalisation : interp affiche true/false (bool), QBE affiche 1/0 (int)
    a_norm=$(echo "$a" | sed 's/^true$/1/; s/^false$/0/')
    if [ "$a_norm" = "$b" ]; then echo "OK  $n"; P=$((P+1)); else echo "FAIL $n: i='$a' q='$b'"; F=$((F+1)); fi
    if ! command -v wasmtime >/dev/null 2>&1 && [ "${REQUIRE_WASM:-0}" = "1" ]; then
        # CI : l'absence de wasmtime ne doit pas desactiver la jambe WASM en silence.
        echo "  FAIL wasm: wasmtime requis (REQUIRE_WASM=1) mais absent"; F=$((F+1))
    elif command -v wasmtime >/dev/null 2>&1; then
        "$H" compile-wasm "$f" -o "/tmp/$n.wat" >/dev/null 2>&1
        if [ ! -f "/tmp/$n.wat" ]; then
            echo "  FAIL wasm: compile-wasm n'a pas produit de .wat"; F=$((F+1))
        elif case " $WASM_UNSUPPORTED " in *" $n "*) true;; *) false;; esac; then
            echo "  SKIP wasm: tas non implemente dans mir_wat.zig (alloc/load_at -> unreachable)"
        else
            c=$(timeout 5 wasmtime --invoke main "/tmp/$n.wat" 2>/dev/null | grep -vE 'Memory clean|^\(\)$|^$' || echo "WASM_NO_BIN")
            c_norm=$(echo "$c" | sed 's/^true$/1/; s/^false$/0/')
            if [ "$a_norm" = "$c_norm" ]; then echo "  OK wasm"; else echo "  FAIL wasm: i='$a' w='$c'"; F=$((F+1)); fi
        fi
    fi
done
echo ""
echo "RESULT: OK=$P FAIL=$F"
exit $F
