#!/usr/bin/env bash
# false_theorems.sh -- soundness discriminator for the proof system.
# Exit 0 if all false theorems are rejected AND all true theorems are accepted.
# Exit 1 otherwise (regression in soundness).

set -u
HEAVEN=${1:-./zig-out/bin/heaven}
TMP=$(mktemp /tmp/false_theorems.XXXXXX.hvn)
trap "rm -f $TMP" EXIT

cat > "$TMP" << EOF_TESTS
# False theorems: must be rejected (proved must NOT appear)
theorem f_plus1 : x + 1 = x
prove f_plus1 by simplify
theorem f_2p2 : 2 + 2 = 5
prove f_2p2 by simplify
theorem f_sq : x * x = x
prove f_sq by simplify
theorem f_0_1 : 0 = 1
prove f_0_1 by simplify
theorem f_rev : x = x + 1
prove f_rev by simplify
theorem f_mul : 2 * 3 = 7
prove f_mul by simplify

# True theorems: must be accepted (proved must appear)
theorem t_zero : x + 0 = x
prove t_zero by simplify
theorem t_2p2 : 2 + 2 = 4
prove t_2p2 by simplify
theorem t_mul1 : x * 1 = x
prove t_mul1 by simplify
theorem t_00 : x + 0 + 0 = x
prove t_00 by simplify
EOF_TESTS

OUTPUT=$("$HEAVEN" --run-test "$TMP" 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ] && [ "$EXIT_CODE" -ne 1 ]; then
  echo "FAIL: heaven returned unexpected exit code $EXIT_CODE"
  echo "$OUTPUT"
  exit 1
fi

FAILS=0

for name in f_plus1 f_2p2 f_sq f_0_1 f_rev f_mul; do
  if echo "$OUTPUT" | grep -q "proved (simplify)" | grep -q "\\[$name\\]"; then
    :
  fi
  if echo "$OUTPUT" | grep -E "prove $name by simplify" | grep -q "proved"; then
    echo "FAIL: false theorem $name was PROVED (soundness bug)"
    FAILS=$((FAILS + 1))
  fi
done

for name in t_zero t_2p2 t_mul1 t_00; do
  if ! echo "$OUTPUT" | grep -E "prove $name by simplify" | grep -q "proved"; then
    echo "FAIL: true theorem $name was NOT proved (regression)"
    FAILS=$((FAILS + 1))
  fi
done

if [ "$FAILS" -eq 0 ]; then
  echo "OK: 6 false rejected, 4 true accepted"
  exit 0
else
  echo "FAIL: $FAILS soundness violations"
  exit 1
fi
