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
check nocatch       $'g 0 = 1\ng 1 = 2\n(g 5)'
check nocatch2      $'g 0 a = 1\ng 1 a = 2\n(g 5 0)'
check guard_nocatch $'h n | n > 0 = 1\nh n | n < 0 = 2\n(h 0)'
check nested_ctor   $'data L = Nil | Cons x xs\nlen (Cons (Cons _ _) r) = 1 + len r\nlen _ = 0\n(len (Cons Nil Nil))'
echo "reject: $fail echec(s)"; exit $fail
