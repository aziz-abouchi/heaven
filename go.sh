#!/bin/bash
pkill -f "zig-out/bin/heaven" 2>/dev/null || true

NETWORK_FLAG=""
if [ "$(uname -s)" = "Darwin" ]; then
    NETWORK_FLAG="-Dnetwork=false"
fi

#rm -f .heaven_session.json

# 1. Générer le WASM EN PREMIER
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# 2. Le copier dans public/
cp zig-out/bin/heaven.wasm src/vessel/public/heaven.wasm

# 3. Nettoyer : le natif doit lire le NOUVEAU public/heaven.wasm
#rm -fr .zig-cache zig-out

# 4. Compiler le natif (embarque le nouveau wasm)
zig build $NETWORK_FLAG

# 5. Tests
zig build test $NETWORK_FLAG

# 6. Lancer
HEAVEN_DEBUG=1 ./zig-out/bin/heaven 8080
