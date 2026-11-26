#!/usr/bin/env bash
# Soundness : un programme que MIR/QBE ne sait pas compiler fidelement doit etre
# REJETE (compile-qbe echoue, aucun binaire), jamais compile avec une valeur
# inventee. Complement negatif de tests/diff/run.sh.
H=./zig-out/bin/heaven
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
check() {  # nom source
  printf '%s\n' "$2" > "$tmp/$1.hvn"
  rm -f "$tmp/$1.bin"
  "$H" compile-qbe "$tmp/$1.hvn" -o "$tmp/$1.bin" >/dev/null 2>&1
  if [ -x "$tmp/$1.bin" ]; then echo "FAIL $1 : binaire produit (valeur inventee ?)"; fail=$((fail+1)); else echo "OK   $1 rejete"; fi
}
# Aucun motif ne correspond : pas de clause generale. Le programme peut etre
# rejete OU compile (repli @abort), mais alors il doit MOURIR bruyamment (signal
# en natif, trap en WASM) sans rien imprimer : jamais une valeur inventee.
check_dies() {  # nom source
  printf '%s\n' "$2" > "$tmp/$1.hvn"
  rm -f "$tmp/$1.bin" "$tmp/$1.wat"
  if "$H" compile-qbe "$tmp/$1.hvn" -o "$tmp/$1.bin" >/dev/null 2>&1 && [ -x "$tmp/$1.bin" ]; then
    out=$("$tmp/$1.bin" 2>/dev/null); rc=$?
    if [ "$rc" -ge 128 ] && [ -z "$out" ]; then echo "OK   $1 qbe meurt (exit $rc, rien imprime)"; else echo "FAIL $1 : qbe valeur='$out' exit=$rc (attendu: mort bruyante sans sortie)"; fail=$((fail+1)); fi
  else echo "OK   $1 qbe rejete"; fi
  if "$H" compile-wasm "$tmp/$1.hvn" -o "$tmp/$1.wat" >/dev/null 2>&1 && [ -f "$tmp/$1.wat" ] && command -v wasmtime >/dev/null; then
    out=$(wasmtime --invoke main "$tmp/$1.wat" 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$out" ]; then echo "OK   $1 wasm trappe (exit $rc, rien imprime)"; else echo "FAIL $1 : wasm valeur='$out' exit=$rc (attendu: trap sans sortie)"; fail=$((fail+1)); fi
  fi
}
check_dies nocatch       $'g 0 = 1\ng 1 = 2\n(g 5)'
check_dies nocatch2      $'g 0 a = 1\ng 1 a = 2\n(g 5 0)'
check_dies guard_nocatch $'h n | n > 0 = 1\nh n | n < 0 = 2\n(h 0)'
# Motifs imbriques : profondeur 2 compilee (tests/diff/32-nested-ctor.hvn) ;
# profondeur 3 non geree -> doit etre REJETE (jamais ignore silencieusement).
check nested_ctor3  $'data T = E | L x | N l r\nf (N (N (L 0) b) r) = 9\nf (N l r) = 1\nf (L n) = n\nf E = 0\n(f (N (N (L 0) E) E))'
echo "reject: $fail echec(s)"; exit $fail
