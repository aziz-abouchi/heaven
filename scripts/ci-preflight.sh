#!/usr/bin/env bash
# HEAVEN:ci-preflight — simule un checkout propre (comme la CI).
# Copie le repo via git archive dans /tmp, build, test.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SANDBOX="$(mktemp -d /tmp/heaven-preflight.XXXXXX)"
echo "[preflight] sandbox=$SANDBOX"

# Copier uniquement les fichiers VERSIONNES (pas d'artefacts locaux)
git -C "$ROOT" archive HEAD | tar -x -C "$SANDBOX"
cd "$SANDBOX"

# Reproduire les dependances externes minimales
ln -s "$ROOT/vendor" vendor 2>/dev/null || true
ln -s "$ROOT/.zig-cache" .zig-cache 2>/dev/null || true

echo "[preflight] build ReleaseFast"
zig build -Doptimize=ReleaseFast

echo "[preflight] test-files"
HEAVEN_NO_LEAK_CHECK=1 zig build -Dnetwork=false test-files

echo "[preflight] OK — sandbox: $SANDBOX"
