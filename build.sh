#!/bin/bash
set -e

# Desactive le leak check DebugAllocator pendant les tests : depuis
# 2026-10-02, un bug intermittent y fait paniquer le DebugAllocator
# (assert 'double-mapped pages'). page_allocator passe 20/20.
# Pour retrouver le check complet : HEAVEN_NO_LEAK_CHECK=0 bash build.sh
export HEAVEN_NO_LEAK_CHECK="${HEAVEN_NO_LEAK_CHECK:-1}"

ROOT_DIR=$(pwd)
VENDOR_DIR="$ROOT_DIR/vendor"

#─── Pins vendor (A1 — build reproductible) ───
# Voir vendor/manifest.lock. Ne jamais remplacer un pin par un clone
# de master : c'est ce qui a rendu la provenance irrécupérable.
TCC_COMMIT="0fb54300b56512754221d80adda85ddb9815bceb"  # release_0_9_27-1442

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
    echo "[FORGE] Clonage TCC (epingle $TCC_COMMIT)..."
    git clone https://github.com/TinyCC/tinycc.git "$VENDOR_DIR/tcc"
    git -C "$VENDOR_DIR/tcc" checkout --detach "$TCC_COMMIT"
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
# Fallback mirror (c9x.me was unreachable 2026-11-16, Debian/Ubuntu carries
# the identical orig.tar.xz since QBE is DFSG-compliant).
QBE_TARBALL_FALLBACK="https://web.archive.org/web/20250211081009/https://c9x.me/compile/release/qbe-1.2.tar.xz"
QBE_CACHE_DIR="$VENDOR_DIR/cache"
QBE_TARBALL_CACHE="$QBE_CACHE_DIR/qbe-$QBE_VERSION.tar.xz"

if [ ! -d "$QBE_DIR" ]; then
    echo "[FORGE] Installation QBE $QBE_VERSION..."
    mkdir -p "$QBE_CACHE_DIR"
    if [ ! -f "$QBE_TARBALL_CACHE" ]; then
        echo "[FORGE] Téléchargement $QBE_TARBALL_URL..."
        if ! curl -sL --max-time 60 --retry 2 --retry-delay 5 \
             -w "[FORGE] QBE primary: HTTP %{http_code}, %{time_total}s, %{size_download} bytes\n" \
             "$QBE_TARBALL_URL" -o "$QBE_TARBALL_CACHE"; then
            echo "[FORGE] Primary unreachable, trying fallback mirror..."
            rm -f "$QBE_TARBALL_CACHE"
            if ! curl -sL --max-time 60 --retry 2 --retry-delay 5 \
                 -w "[FORGE] QBE fallback: HTTP %{http_code}, %{time_total}s, %{size_download} bytes\n" \
                 "$QBE_TARBALL_FALLBACK" -o "$QBE_TARBALL_CACHE"; then
                echo "[FORGE] ERROR: both primary and fallback failed"
                echo "[FORGE] Primary: $QBE_TARBALL_URL"
                echo "[FORGE] Fallback: $QBE_TARBALL_FALLBACK"
                rm -f "$QBE_TARBALL_CACHE"
                exit 1
            fi
        fi
        # Sanity: tarball must extract and contain qbe-<ver>/
        if ! tar -tJf "$QBE_TARBALL_CACHE" 2>/dev/null | head -1 | grep -q "^qbe-$QBE_VERSION/"; then
            echo "[FORGE] ERROR: downloaded tarball does not contain qbe-$QBE_VERSION/"
            rm -f "$QBE_TARBALL_CACHE"
            exit 1
        fi
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

# WASM : optionnel, desactive via HEAVEN_NO_WASM=1.
# Mis a jour 2026-11-17 : wasm32-freestanding COMPILE sans erreur, en
# Debug comme en ReleaseSmall (mesure Guix / Zig 0.15.2). L'ancien
# commentaire (std.posix / std.Thread bloquants, CI forcee a
# HEAVEN_NO_WASM=1) est perime. Le flag reste utile pour les builds
# rapides, mais n'est plus un contournement necessaire.
# Distinct : l'IO runtime WASM (W3, @puts -> unreachable) reste ouvert.
if [ "${HEAVEN_NO_WASM:-0}" = "1" ]; then
    echo "[FORGE] WASM desactive (HEAVEN_NO_WASM=1)."
else
    echo "[FORGE] Building wasm (nécessaire pour @embedFile)..."
    zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
    cp zig-out/bin/heaven-freestanding.wasm src/vessel/public/heaven.wasm
    mkdir -p site/repl
    cp zig-out/bin/heaven-freestanding.wasm site/repl/heaven.wasm
fi

echo "[FORGE] Compilation native..."
# D20 : ReleaseFast par defaut pour la recursion profonde.
# Debug limitait f a ~130 niveaux (a cause des frames Debug non
# optimisees). ReleaseFast monte a ~500-1000.
zig build -Doptimize=ReleaseFast

echo "[FORGE] Tests..."
zig build test

#─── Documentation factuelle ───
# Regenere les chiffres du README (tests, dates) pour eviter que le
# CI (docgen --check) echoue sur un push. Non bloquant.
if command -v python3 >/dev/null 2>&1 && [ -f scripts/docgen.py ]; then
    echo "[FORGE] Mise a jour doc (docgen)..."
    python3 scripts/docgen.py || echo "[FORGE] docgen echoue (non bloquant)"
    python3 scripts/status_gen.py || echo "[FORGE] status_gen echoue (non bloquant)"
fi

echo "[FORGE] Terminé. Lancer avec: zig build run -- <port>"
