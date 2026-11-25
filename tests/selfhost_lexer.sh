#!/usr/bin/env bash
# Auto-hébergement : le lexeur écrit en Heaven (lib/heaven_parse.hvn), compilé en
# natif (QBE) et en WASM, doit donner le même nombre de jetons que l'interpréteur.
set -u
BIN="${HEAVEN_BIN:-zig-out/bin/heaven}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; n=0
while IFS= read -r src; do
  n=$((n+1))
  { cat lib/heaven_parse.hvn
    printf '\nprobe_len TNil = 0\nprobe_len (TCons t r) = (+ 1 (probe_len r))\n(probe_len (lex "%s"))\n' "$src"; } > "$T/p$n.hvn"
  i=$(HEAVEN_NO_LEAK_CHECK=1 timeout 120 "$BIN" --eval-file "$T/p$n.hvn" 2>&1 | grep -vE 'MIR|clause|Memory' | tail -1)
  q="rejet"; w="rejet"
  if HEAVEN_NO_LEAK_CHECK=1 timeout 120 "$BIN" compile-qbe "$T/p$n.hvn" -o "$T/p$n.bin" >/dev/null 2>&1; then q=$(timeout 10 "$T/p$n.bin" 2>/dev/null | head -1); fi
  if HEAVEN_NO_LEAK_CHECK=1 timeout 120 "$BIN" compile-wasm "$T/p$n.hvn" -o "$T/p$n.wat" >/dev/null 2>&1; then w=$(timeout 10 wasmtime --invoke main "$T/p$n.wat" 2>/dev/null | head -1); fi
  if [ "$i" = "$q" ] && [ "$i" = "$w" ]; then echo "OK   '$src' -> $i"; else echo "FAIL '$src' interp=$i qbe=$q wasm=$w"; fail=1; fi
done <<'INPUTS'
(+ 1 (* 22 3))
abc def
(f x) (g y)
x
INPUTS
[ $fail = 0 ] && echo "selfhost_lexer OK ($n entrées, interp = QBE = wasmtime)"; exit $fail
