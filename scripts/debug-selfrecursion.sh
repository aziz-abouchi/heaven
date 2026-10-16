#!/usr/bin/env bash
# Debug selfrecursion : reproduit + dumpe l'AST apres parse.
set -e
cd "$(dirname "$0")/.."

cat > /tmp/self.hvn <<'HVN'
count n = if (= n 0) then 0 else (count (- n 1))
test "c1": (count 1) == 0
HVN

echo "=== 1) test direct (binaire ReleaseFast) ==="
./zig-out/bin/heaven test /tmp/self.hvn 2>&1 | grep -E "c1|✗|✓"

echo
echo "=== 2) AST apres parse (a implementer) ==="
echo "TODO : ajouter dump AST dans heaven_expr.parseExpression."
echo "Piste : apres expr_parser.parseExpression, dumper l'arbre via"
echo "store.get(id).tag + span recursivement, tag-match .apply."

echo
echo "=== 3) prochaines traces a ajouter ==="
echo "  a) heaven_expr.zig:2500 environ (parseExpression) : dump AST"
echo "  b) engine_expr.zig evalMagic .apply : dump node.span_a"
echo "  c) Compare les deux : si differents -> parser. Si identiques -> eval."
