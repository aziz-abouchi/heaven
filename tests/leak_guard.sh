#!/usr/bin/env bash
# Le détecteur de fuites (actif par défaut) ne doit rien signaler sur les
# définitions `fn` redéfinies. Régression : evalFnDef dupliquait le nom à chaque redéfinition.
set -u
BIN="${HEAVEN_BIN:-zig-out/bin/heaven}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'fn f(x) = x + 1\nfn f(x) = x + 2\nfn f(x) = x + 3\n(f 1)\n' > "$T/a.hvn"
out=$(env -u HEAVEN_NO_LEAK_CHECK "$BIN" --eval-file "$T/a.hvn" 2>&1)
if echo "$out" | grep -q 'leaked'; then echo "FAIL leak_guard"; echo "$out" | head -5; exit 1; fi
echo "$out" | grep -q '^4$' || { echo "FAIL leak_guard: valeur attendue 4"; echo "$out" | head -3; exit 1; }
echo "leak_guard OK"
