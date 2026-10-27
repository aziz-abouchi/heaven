#!/usr/bin/env bash
# fuzz.sh : mutation-based fuzzing minimal.
# Mute des seeds valides (tests/*.hvn), lance --eval-file, capture rc>128 (crash).
set -u
BIN=./zig-out/bin/heaven
N="${1:-100}"
CORPUS="${2:-tests/test_arithmetic.hvn}"
mkdir -p /tmp/fuzz_crashes
crash=0
for i in $(seq 1 "$N"); do
  # Mute : coupe, insère de l'urandom au milieu, ou remplace un bloc
  size=$(wc -c < "$CORPUS")
  cut=$(( (RANDOM % size) + 1 ))
  { head -c "$cut" "$CORPUS"; head -c 20 /dev/urandom; tail -c +$((cut+1)) "$CORPUS"; } > /tmp/fuzz_in.hvn
  timeout 2 "$BIN" --eval-file /tmp/fuzz_in.hvn >/dev/null 2>&1
  rc=$?
  if [ "$rc" -gt 128 ]; then
    cp /tmp/fuzz_in.hvn "/tmp/fuzz_crashes/crash_${i}_rc${rc}.hvn"
    echo "CRASH rc=$rc (iter $i) -> /tmp/fuzz_crashes/crash_${i}_rc${rc}.hvn"
    crash=$((crash+1))
  fi
done
echo "→ $N iterations, $crash crashes"
