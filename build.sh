#!/bin/bash
set -e

# Desactive le leak check DebugAllocator pendant les tests : depuis
# 2026-10-02, un bug intermittent y fait paniquer le DebugAllocator
# (assert 'double-mapped pages'). page_allocator passe 20/20.
# Pour retrouver le check complet : HEAVEN_NO_LEAK_CHECK=0 bash build.sh
export HEAVEN_NO_LEAK_CHECK="${HEAVEN_NO_LEAK_CHECK:-1}"

ROOT_DIR=$(pwd)
VENDOR_DIR="$ROOT_DIR/vendor"

#─── Bootstrap parsers tree-sitter ───
setup_parser() {
    local name=$1
    local source=$2
    local target="$VENDOR_DIR/tree-sitter-$name"

    if [ ! -d "$target" ]; then
        echo "[FORGE] Clonage parser $name..."
        if [[ $source == http* ]]; then
            git clone "$source" "$target"
        else
            cp -r "$source" "$target"
        fi
    fi

    if [ ! -f "$target/src/parser.c" ]; then
        echo "[FORGE] Génération parser $name..."
        (cd "$target" && tree-sitter generate)
    fi
}

#─── Tree-sitter runtime (lib.c) ───
if [ ! -d "$VENDOR_DIR/tree-sitter" ]; then
    echo "[FORGE] Clonage tree-sitter runtime..."
    git clone https://github.com/tree-sitter/tree-sitter.git "$VENDOR_DIR/tree-sitter"
fi
echo "[FORGE] tree-sitter runtime présent."

setup_parser "pie" "https://github.com/syrkis/tree-sitter-pie"
setup_parser "c" "https://github.com/tree-sitter/tree-sitter-c"
setup_parser "zig" "https://github.com/maxxnino/tree-sitter-zig"

echo "[FORGE] Parsers prêts."

# TCC
if [ ! -d "$VENDOR_DIR/tcc" ]; then
    echo "[FORGE] Clonage TCC..."
    git clone https://github.com/TinyCC/tinycc.git "$VENDOR_DIR/tcc"
fi

rm -f vendor/tcc/config.h
# Générer config.h adapté à l'OS
if [ -d "$VENDOR_DIR/tcc" ]; then
    OS=$(uname -s)
    ARCH=$(uname -m)
    echo "[FORGE] Génération config.h pour $OS/$ARCH..."
    
    if [ "$OS" = "Darwin" ]; then
        if [ "$ARCH" = "arm64" ]; then
            cat > "$VENDOR_DIR/tcc/config.h" <<'EOF'
#define TCC_TARGET_MACHO 1
#define TCC_TARGET_ARM64 1
#define CONFIG_TCC_MACHO 1
#define CONFIG_ARM64 1
#define CONFIG_TCC_ASM 1
#define CONFIG_TCC_LINKER 1
#define CONFIG_USE_LIBTCC 1
#define TCC_IS_NATIVE 1
#define CONFIG_TCC_BACKTRACE 1
#define CONFIG_TCC_STATIC 1
#define CONFIG_TCC_BCHECK 1
#define TCC_VERSION "0.9.28"
#define HOST_ARM64 1
#define CONFIG_TCC_SEMANTIC 0
EOF
        else
            cat > "$VENDOR_DIR/tcc/config.h" <<'EOF'
#define TCC_TARGET_MACHO 1
#define TCC_TARGET_X86_64 1
#define CONFIG_TCC_MACHO 1
#define CONFIG_X86_64 1
#define CONFIG_TCC_ASM 1
#define CONFIG_TCC_LINKER 1
#define CONFIG_USE_LIBTCC 1
#define TCC_IS_NATIVE 1
#define TCC_VERSION "0.9.28"
#define HOST_X86_64 1
EOF
        fi
    elif [ "$OS" = "Linux" ]; then
        cat > "$VENDOR_DIR/tcc/config.h" <<'EOF'
#define TCC_TARGET_ELF 1
#define TCC_TARGET_X86_64 1
#define CONFIG_TCC_ELF 1
#define CONFIG_X86_64 1
#define CONFIG_TCC_ASM 1
#define CONFIG_TCC_LINKER 1
#define CONFIG_USE_LIBTCC 1
#define TCC_IS_NATIVE 1
#define TCC_VERSION "0.9.28"
#define HOST_X86_64 1
EOF
    else
        # Windows (déjà existant)
        cat > "$VENDOR_DIR/tcc/config.h" <<'EOF'
#define TCC_TARGET_PE 1
#define TCC_TARGET_X86_64 1
#define CONFIG_TCC_PE 1
#define CONFIG_X86_64 1
#define CONFIG_TCC_ASM 1
#define CONFIG_TCC_LINKER 1
#define CONFIG_USE_LIBTCC 1
#define TCC_IS_NATIVE 1
#define TCC_VERSION "0.9.28"
EOF
    fi
    echo "[FORGE] config.h créé."
fi

echo "[FORGE] TCC présent."

#─── QBE : backend natif (M3 — docs/BACKENDS.md) ───
# Amont : c9x.me/compile/release/qbe-<version>.tar.xz (release
# officielle). Le miroir github.com/andrewchambers/qbe est FIGE en
# 2021 (commit 4420727) et rejette la syntaxe SSA moderne
# (tabulations, etc.). Ne pas l'utiliser.
#
# Le tarball officiel est mis en cache dans vendor/cache/ pour
# éviter un re-téléchargement si vendor/qbe-<version>/ est supprimé.
QBE_VERSION="1.2"
QBE_DIR="$VENDOR_DIR/qbe-$QBE_VERSION"
QBE_TARBALL_URL="https://c9x.me/compile/release/qbe-$QBE_VERSION.tar.xz"
QBE_CACHE_DIR="$VENDOR_DIR/cache"
QBE_TARBALL_CACHE="$QBE_CACHE_DIR/qbe-$QBE_VERSION.tar.xz"

if [ ! -d "$QBE_DIR" ]; then
    echo "[FORGE] Installation QBE $QBE_VERSION..."
    mkdir -p "$QBE_CACHE_DIR"
    if [ ! -f "$QBE_TARBALL_CACHE" ]; then
        echo "[FORGE] Téléchargement $QBE_TARBALL_URL..."
        curl -sL "$QBE_TARBALL_URL" -o "$QBE_TARBALL_CACHE"
    fi
    # Verifier que c'est bien un tarball (et pas une page d'erreur).
    if ! file "$QBE_TARBALL_CACHE" | grep -q "XZ compressed"; then
        echo "[FORGE] ERREUR : $QBE_TARBALL_CACHE n'est pas une archive xz."
        exit 1
    fi
    mkdir -p "$QBE_DIR"
    tar -xf "$QBE_TARBALL_CACHE" -C "$QBE_DIR" --strip-components=1
fi

if [ ! -x "$QBE_DIR/qbe" ]; then
    echo "[FORGE] Build QBE $QBE_VERSION..."
    (cd "$QBE_DIR" && make)
fi

# Smoke test local : qbe → asm → cc → run. `export function` est
# requis pour l'export (sinon symbole local → link error).
cat > /tmp/qbe_smoke.ssa <<'SMOKE'
export function $main() {
@start
    %r =l call $printf(l $fmt, l 42)
    ret
}
data $fmt = { b "smoke %ld\n", b 0 }
SMOKE
"$QBE_DIR/qbe" -o /tmp/qbe_smoke.s /tmp/qbe_smoke.ssa
cc /tmp/qbe_smoke.s -o /tmp/qbe_smoke
/tmp/qbe_smoke | grep -q "smoke 42"
echo "[FORGE] QBE OK $QBE_VERSION ($(uname -s)/$(uname -m))."

# libdatachannel
if [ ! -d "$VENDOR_DIR/libdatachannel" ]; then
    echo "[FORGE] Clonage libdatachannel..."
    git clone https://github.com/paullouisageneau/libdatachannel.git "$VENDOR_DIR/libdatachannel"
    (cd "$VENDOR_DIR/libdatachannel" && git submodule update --init --recursive)
fi
echo "[FORGE] libdatachannel présent."

#─── Build via zig build ───
cp core/test_suite.hvn src/vessel/public/test_suite.hvn
echo "[FORGE] Building wasm (nécessaire pour @embedFile)..."
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
cp zig-out/bin/heaven.wasm src/vessel/public/heaven.wasm

echo "[FORGE] Compilation native..."
zig build

echo "[FORGE] Tests..."
zig build test

echo "[FORGE] Terminé. Lancer avec: zig build run -- <port>"
