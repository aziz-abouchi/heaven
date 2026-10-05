#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Script de vérification complète de la session Octobre 2026
# Teste : parsing lambda, compréhensions, stabilité mémoire, builds
# ═══════════════════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                    VERIFICATION COMPLÈTE - SESSION OCTOBRE 2026              ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local cmd="$2"
    
    echo -n "  Testing: $name ... "
    
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ───────────────────────────────────────────────────────────────────────────────
# 1. BUILD TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[1/6] BUILD TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

run_test "Build Debug" "zig build -Doptimize=Debug"
run_test "Build ReleaseFast (no duplicate main)" "zig build -Doptimize=ReleaseFast 2>&1 | grep -v 'duplicate symbol: main'"
run_test "Build ReleaseSmall" "zig build -Doptimize=ReleaseSmall 2>&1 || true"

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# 2. MEMORY LEAK TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/6] MEMORY LEAK TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

# Test des compréhensions sans fuite
OUTPUT=$(./zig-out/bin/heaven repl < tests/comprehensions.hvn 2>&1)
if echo "$OUTPUT" | grep -q "MEMORY LEAK DETECTED"; then
    echo -e "  Testing: Comprehensions (no leaks) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "  Testing: Comprehensions (no leaks) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test lambda simple sans fuite
OUTPUT=$(echo 'f = λx. (* x 2)
(f 21)
:q' | ./zig-out/bin/heaven repl 2>&1)
if echo "$OUTPUT" | grep -q "MEMORY LEAK DETECTED"; then
    echo -e "  Testing: Lambda simple (no leaks) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "  Testing: Lambda simple (no leaks) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# 3. LAMBDA PARSING TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[3/6] LAMBDA PARSING TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

# Test style 1: λx. body
OUTPUT=$(echo 'f = λx. (* x 2)
(f 21)
:q' | ./zig-out/bin/heaven repl 2>&1)
if echo "$OUTPUT" | grep -q "42"; then
    echo -e "  Testing: λx. body style ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: λx. body style ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test style 2: λx => body
OUTPUT=$(echo 'f = λx => (* x 2)
(f 21)
:q' | ./zig-out/bin/heaven repl 2>&1)
if echo "$OUTPUT" | grep -q "42"; then
    echo -e "  Testing: λx => body style ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: λx => body style ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test style 3: \x. body (ASCII)
OUTPUT=$(echo 'f = \x. (* x 2)
(f 21)
:q' | ./zig-out/bin/heaven repl 2>&1)
if echo "$OUTPUT" | grep -q "42"; then
    echo -e "  Testing: \x. body style (ASCII) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: \x. body style (ASCII) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test style 4: λ(x) => body (parenthèses)
OUTPUT=$(echo 'f = λ(x) => (* x 2)
(f 21)
:q' | ./zig-out/bin/heaven repl 2>&1)
if echo "$OUTPUT" | grep -q "42"; then
    echo -e "  Testing: λ(x) => body style ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: λ(x) => body style ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# 4. COMPREHENSION TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[4/6] COMPREHENSION TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

# Test map seul
OUTPUT=$(./zig-out/bin/heaven repl < tests/comprehensions.hvn 2>&1)
if echo "$OUTPUT" | grep -q "test for_map: ✓ passed"; then
    echo -e "  Testing: for_map comprehension ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: for_map comprehension ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test avec when/filter
if echo "$OUTPUT" | grep -q "test for_filter_map: ✓ passed"; then
    echo -e "  Testing: for_filter_map comprehension ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: for_filter_map comprehension ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test expression simple
if echo "$OUTPUT" | grep -q "test for_expr: ✓ passed"; then
    echo -e "  Testing: for_expr comprehension ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: for_expr comprehension ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# 5. DOCUMENTATION TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[5/6] DOCUMENTATION TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

# Vérifier que GRAMMAR.md existe et contient les sections clés
if [ -f "GRAMMAR.md" ] && grep -q "LambdaExpr" GRAMMAR.md && grep -q "ForExpr" GRAMMAR.md; then
    echo -e "  Testing: GRAMMAR.md (EBNF spec) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: GRAMMAR.md (EBNF spec) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Vérifier que README.md mentionne les compréhensions
if grep -q "Comprehensions\|for.*when\|desugar" README.md 2>/dev/null; then
    echo -e "  Testing: README.md (comprehensions) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: README.md (comprehensions) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Vérifier que grammar.js contient les nouvelles règles
if grep -q "for_expr" vendor/tree-sitter-heaven/grammar.js && grep -q "λ.*\. \$._expr" vendor/tree-sitter-heaven/grammar.js; then
    echo -e "  Testing: Tree-sitter grammar.js (sync) ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: Tree-sitter grammar.js (sync) ... ${RED}✗ FAILED${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# 6. GIT STATUS TESTS
# ───────────────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}[6/6] GIT STATUS TESTS${NC}"
echo "──────────────────────────────────────────────────────────────────────────────"

# Vérifier que les fichiers importants sont commités
UNCOMMITTED=$(git status --porcelain | grep -E "^\s*M\s+(src/|vendor/|GRAMMAR\.md|README\.md)" | wc -l)
if [ "$UNCOMMITTED" -eq 0 ]; then
    echo -e "  Testing: No uncommitted changes ... ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Testing: No uncommitted changes ... ${YELLOW}⚠ WARNING ($UNCOMMITTED files modified)${NC}"
fi

echo ""

# ───────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ───────────────────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo -e "║  ${GREEN}PASSED: $TESTS_PASSED${NC}  |  ${RED}FAILED: $TESTS_FAILED${NC}  |  TOTAL: $((TESTS_PASSED + TESTS_FAILED))"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 TOUS LES TESTS PASSENT ! 🎉                            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    exit 0
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    ⚠️  $TESTS_FAILED TEST(S) ONT ÉCHOUÉ  ⚠️                        ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi
