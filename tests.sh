#!/bin/bash
for f in tests/*.hvn; do
  echo "===== $f ====="
  HEAVEN_DEBUG=1 zig build run -- --run-test "$f" 2>&1 | grep -v '^\s*$' || echo "  (exit $?)"
done
