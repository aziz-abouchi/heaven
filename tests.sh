#!/bin/bash
rm -fr zig-out .zig-cache
zig build
for f in tests/*.hvn; do
  echo "===== $f ====="
  zig-out/bin/heaven --run-test "$f" 2>&1 | grep -v '^\s*$' || echo "  (exit $?)"
done
