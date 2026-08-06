#!/bin/bash
echo "=== Running Heaven Tests ==="

# Lancer le REPL et exécuter le fichier de test
./zig-out/bin/heaven 8080 << 'HEAVEN_EOF'
load tests/test_factorial.hvn
HEAVEN_EOF

echo "=== Tests Complete ==="
