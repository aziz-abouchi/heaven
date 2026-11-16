#!/usr/bin/env bash
# mcp_soundness.sh -- integration test for MCP method label (Phase 1b).
# Output redirected to /tmp (never to tty): heaven mcp emits control chars.
# Invariant: method is never "kernel" (no path certifies by kernel today).
# Invariant: certified is always false.

set -u
HEAVEN=${1:-./zig-out/bin/heaven}
[ -x "$HEAVEN" ] || { echo "FAIL: binary missing"; exit 1; }

FAILS=0

probe() {
    local label="$1" stmt="$2"
    local tmp=$(mktemp /tmp/mcp_probe.XXXXXX)
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"heaven_prove","arguments":{"statement":%s}}}\n' \
        "$(printf '%s' "$stmt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | timeout 10 "$HEAVEN" mcp > "$tmp" 2>/dev/null
    local code=$?
    [ "$code" = "0" ] || { echo "FAIL [$label]: exit $code"; FAILS=$((FAILS+1)); rm -f "$tmp"; return; }
    local inner=$(python3 -c "
import json, sys
try:
    d = json.load(open('$tmp'))
    print(d['result']['content'][0]['text'])
except Exception as e:
    print('PARSE_ERROR: ' + str(e))
")
    rm -f "$tmp"
    echo "$inner" | grep -q 'PARSE_ERROR' && { echo "FAIL [$label]: $inner"; FAILS=$((FAILS+1)); return; }
    echo "$inner" | grep -q '"method":"kernel"' && { echo "FAIL [$label]: method=kernel (banned)"; FAILS=$((FAILS+1)); } || echo "OK [$label]: method not kernel"
    echo "$inner" | grep -q '"certified":false' && echo "OK [$label]: certified=false" || { echo "FAIL [$label]: certified missing"; FAILS=$((FAILS+1)); }
}

probe "true_theorem" "theorem good1 : x + 0 = x
prove good1 by simplify"

probe "false_theorem" "theorem bad1 : x + 1 = x
prove bad1 by simplify"

if [ "$FAILS" -eq 0 ]; then echo "OK: 2/2 invariants hold"; exit 0; fi
echo "FAIL: $FAILS violations"; exit 1
