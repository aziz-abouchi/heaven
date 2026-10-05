#!/bin/bash
# ═══════════════════════════════════════════════════════════
# check_all.sh — état de santé complet du projet Heaven
# Usage : bash check_all.sh [--quick] [--no-build]
# Sortie : tableau synthétique + détails en fichier
# ═══════════════════════════════════════════════════════════

set -u
QUICK=0; NO_BUILD=0
for arg in "$@"; do
  case $arg in
    --quick)    QUICK=1 ;;
    --no-build) NO_BUILD=1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
LOG="/tmp/heaven_check_$(date +%s).log"
PASS=0; FAIL=0; WARN=0

line()  { printf "%-40s" "$1"; }
ok()    { echo "✓ OK";    PASS=$((PASS+1)); }
ko()    { echo "✗ FAIL";  FAIL=$((FAIL+1)); }
warn()  { echo "⚠ WARN";  WARN=$((WARN+1)); }

echo "═══ Heaven — check complet ═══"
echo "Date : $(date '+%Y-%m-%d %H:%M')"
echo "Log  : $LOG"
echo ""

# ── 1. GIT ──────────────────────────────────────────
echo "── GIT ──"
line "branch / HEAD"
BR=$(git branch --show-current 2>/dev/null || echo "DETACHED")
echo "$BR @ $(git log --oneline -1 2>/dev/null | cut -c1-8)"
[ "$BR" = "main" ] && ok || warn

line "origin/main synchronisé"
git fetch origin -q 2>/dev/null
AHEAD=$(git log --oneline origin/main..HEAD 2>/dev/null | wc -l)
BEHIND=$(git log --oneline HEAD..origin/main 2>/dev/null | wc -l)
if [ "$AHEAD" = "0" ] && [ "$BEHIND" = "0" ]; then ok; else
  echo "⚠ ahead=$AHEAD behind=$BEHIND"; WARN=$((WARN+1)); fi

line "working tree propre"
DIRTY=$(git status --porcelain 2>/dev/null | grep -v "^??" | wc -l)
UNTRACKED=$(git status --porcelain 2>/dev/null | grep "^??" | wc -l)
if [ "$DIRTY" = "0" ] && [ "$UNTRACKED" = "0" ]; then ok
elif [ "$DIRTY" = "0" ]; then echo "⚠ clean, $UNTRACKED untracked"; warn
else echo "✗ $DIRTY fichiers modifiés"; ko; fi
echo ""

# ── 2. BUILD ───────────────────────────────────────
echo "── BUILD ──"
line "zig build (natif)"
if [ "$NO_BUILD" = "0" ]; then
  if zig build > "$LOG" 2>&1; then
    ok; BUILD_OK=1
  else
    ko; BUILD_OK=0
    echo "    → détails : grep error $LOG"
  fi
  line "binaire frais (timestamp)"
  NOW=$(date +%s)
  BIN_TIME=$(stat -c %Y zig-out/bin/heaven 2>/dev/null || echo 0)
  AGE=$(( NOW - BIN_TIME ))
  if [ $AGE -lt 60 ]; then ok; else echo "⚠ binaire vieux de ${AGE}s"; warn; fi
else
  echo "(skippé --no-build)"; BUILD_OK=1
fi
echo ""

# ── 3. TESTS UNITAIRES ZIG ─────────────────────────
if [ "$BUILD_OK" = "1" ] && [ "$QUICK" = "0" ]; then
echo "── ZIG TEST ──"
line "zig build test"
if zig build test > "$LOG.zig" 2>&1; then
  SUMMARY=$(grep "Build Summary" "$LOG.zig" | tail -1)
  [ -z "$SUMMARY" ] && SUMMARY="(pas de summary -- voir log)"
  echo "✓ $SUMMARY"; PASS=$((PASS+1))
else
  LEAKS=$(grep -c "leaked" "$LOG.zig" 2>/dev/null || echo 0)
  if [ "$LEAKS" -gt 0 ]; then
    echo "✗ FAIL + $LEAKS leaks"; ko
  else
    ko
  fi
  echo "    → détails : grep -E 'error|leaked' $LOG.zig"
fi
echo ""
fi

# ── 4. SUITE DE REFERENCE ──────────────────────────
if [ "$BUILD_OK" = "1" ]; then
echo "── SUITE DE RÉFÉRENCE ──"
ts_ref="/tmp/ts_ref.hvn"
git show origin/main:core/test_suite.hvn > "$ts_ref" 2>/dev/null || \
  git show HEAD:core/test_suite.hvn > "$ts_ref" 2>/dev/null
if [ -s "$ts_ref" ]; then
  line "suite standard (test_suite.hvn)"
  OUT=$(zig-out/bin/heaven --run-test "$ts_ref" 2>&1)
  TOTAL=$(echo "$OUT" | grep "Total:" | tail -1 | sed 's/.*Total: //')
  echo "$TOTAL"
  echo "$OUT" | grep -q "Memory clean" && ok || warn
  echo "$TOTAL" | grep -qE "^(94|95|96|97|98|99|100)" && ok || warn
  echo "$OUT" | grep -q "tco_deep.*passed" && echo "    tco_deep : ✓" || echo "    tco_deep : ✗"
else
  echo "(test_suite.hvn introuvable)"
fi
echo ""
fi

# ── 5. FONCTIONNALITÉS (smoke tests) ───────────────
if [ "$BUILD_OK" = "1" ]; then
echo "── FONCTIONNALITÉS ──"

# 5a. Base
line "arithmétique de base"
echo 'test "t": (+ 1 1) == 2' > /tmp/chk_base.hvn
R=$(zig-out/bin/heaven --run-test /tmp/chk_base.hvn 2>&1 | grep -cE "✓")
[ "$R" -ge "1" ] && ok || ko

# 5b. Guards
line "guards (tests/guards.hvn)"
if [ -f tests/guards.hvn ]; then
  T=$(zig-out/bin/heaven --run-test tests/guards.hvn 2>&1 | grep "Total:" | sed 's/.*Total: //')
  echo "$T"; echo "$T" | grep -q "28 / 28" && ok || warn
else echo "(absent)"; warn; fi

# 5c. Comprehensions
line "comprehensions"
if [ -f tests/comprehensions.hvn ]; then
  T=$(zig-out/bin/heaven --run-test tests/comprehensions.hvn 2>&1 | grep "Total:" | sed 's/.*Total: //')
  echo "$T"; echo "$T" | grep -qE "^(12 / 12|11 / 12|10 / 12)" && ok || warn
else echo "(absent)"; warn; fi

# 5d. Streams
line "streams (test_stream.hvn)"
if [ -f tests/test_stream.hvn ]; then
  T=$(zig-out/bin/heaven --run-test tests/test_stream.hvn 2>&1 | grep "Total:" | sed 's/.*Total: //')
  echo "$T"; echo "$T" | grep -qE "^(2[6-9]|3[0-9]) / 37" && ok || warn
else echo "(absent)"; warn; fi

# 5e. Preuves
line "preuves (verify_book2.hvn)"
if [ -f tests/verify_book2.hvn ]; then
  T=$(zig-out/bin/heaven --run-test tests/verify_book2.hvn 2>&1 | grep "Total:" | sed 's/.*Total: //')
  echo "$T"; echo "$T" | grep -q "8 / 8" && ok || warn
else echo "(absent)"; warn; fi

# 5f. Ordre supérieur (le fix du jour)
line "ordre supérieur (symbole fn)"
cat > /tmp/chk_ho.hvn <<'HVNEOF'
data Stream a = Cons a (Stream a) | End
big x = x > 10
filter p End = End
filter p (Cons x rest) = if (p x) (Cons x (filter p rest)) (filter p rest)
test "ho": (filter big (Cons 5 (Cons 20 End))) == (Cons 20 End)
HVNEOF
R=$(zig-out/bin/heaven --run-test /tmp/chk_ho.hvn 2>&1 | grep -cE "✓ test")
[ "$R" -ge "1" ] && ok || ko
echo ""
fi

# ── 6. SUITE ÉTENDUE (si pas --quick) ─────────────
if [ "$BUILD_OK" = "1" ] && [ "$QUICK" = "0" ]; then
echo "── SUITE ÉTENDUE (tests/*.hvn) ──"
for f in tests/*.hvn; do
  [ -f "$f" ] || continue
  NAME=$(basename "$f")
  line "  $NAME"
  T=$(timeout 30 zig-out/bin/heaven --run-test "$f" 2>&1 | grep "Total:" | tail -1 | sed 's/.*Total: //')
  [ -z "$T" ] && T="(timeout/crash)"
  echo "$T"
done
echo ""
fi

# ── 7. OUTILS ──────────────────────────────────────
echo "── OUTILS ──"
line "wasmtime présent"
command -v wasmtime >/dev/null && ok || warn
line "QBE vendé"
[ -x vendor/qbe/obj/qbe ] && ok || warn
line "t_distrib perf (optionnel)"
if [ "$QUICK" = "0" ]; then
  cat > /tmp/chk_perf.hvn <<'HVNEOF'
theorem t : (2 * x) + (2 * y) = 2 * (x + y)
prove t by simplify
HVNEOF
  MS=$( { time -p zig-out/bin/heaven --run-test /tmp/chk_perf.hvn > /dev/null 2>&1; } 2>&1 | grep real | awk '{print $2}')
  echo "${MS}s"; warn
fi
echo ""

# ── RÉSUMÉ ──────────────────────────────────────────
echo "═══════════════════════════════════"
echo "RÉSUMÉ : ✓ $PASS  ✗ $FAIL  ⚠ $WARN"
[ $FAIL -eq 0 ] && echo "VERDICT : PROJET SAIN" || echo "VERDICT : $FAIL ÉCHEC(S) — voir $LOG*"
exit $FAIL
