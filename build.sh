#!/bin/bash
set -e

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

# libdatachannel
if [ ! -d "$VENDOR_DIR/libdatachannel" ]; then
    echo "[FORGE] Clonage libdatachannel..."
    git clone https://github.com/paullouisageneau/libdatachannel.git "$VENDOR_DIR/libdatachannel"
    (cd "$VENDOR_DIR/libdatachannel" && git submodule update --init --recursive)
fi
echo "[FORGE] libdatachannel présent."

#─── Build via zig build ───
echo "[FORGE] Compilation..."
zig build

echo "[FORGE] Tests..."
zig build test

echo "[FORGE] Terminé. Lancer avec: zig build run -- <port>"
