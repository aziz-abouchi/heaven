#!/bin/bash

echo "=== Tests d'intégration Transform ==="
echo ""

# Test 1
echo "Test 1 : Transformation arithmétique simple"
./zig-out/bin/heaven 8080 << 'HEAVEN' | grep -A 3 "transform x + 0 = x"
theorem add_zero : a + 0 = a
transform x + 0 = x
quit
HEAVEN
echo ""

# Test 2
echo "Test 2 : Échec explicite"
./zig-out/bin/heaven 8080 << 'HEAVEN' | grep "transform x + 0 = y"
transform x + 0 = y
quit
HEAVEN
echo ""

# Test 3
echo "Test 3 : Littéraux numériques"
./zig-out/bin/heaven 8080 << 'HEAVEN' | grep "transform 2 + 3 = 5"
transform 2 + 3 = 5
quit
HEAVEN
echo ""

echo "=== Tests terminés ==="
