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

setup_parser "pie" "https://github.com/syrkis/tree-sitter-pie"
setup_parser "c" "https://github.com/tree-sitter/tree-sitter-c"
setup_parser "zig" "https://github.com/maxxnino/tree-sitter-zig"

echo "[FORGE] Parsers prêts."

# TCC
if [ ! -d "$VENDOR_DIR/tcc" ]; then
    echo "[FORGE] Clonage TCC..."
    git clone https://github.com/TinyCC/tinycc.git "$VENDOR_DIR/tcc"
fi

# Générer config.h complet pour TCC (Windows)
if [ -d "$VENDOR_DIR/tcc" ] && [ ! -f "$VENDOR_DIR/tcc/config.h" ]; then
    echo "[FORGE] Génération config.h pour TCC..."
    cat > "$VENDOR_DIR/tcc/config.h" <<'EOF'
/* config.h.  Generated from config.h.in by configure.  */
/* config.h.in.  Generated from configure.ac by autoheader.  */

/* Define to 1 if the target architecture is arm */
#define CONFIG_ARM 0

/* Define to 1 if the target architecture is arm64 */
#define CONFIG_ARM64 0

/* Define to 1 if the target architecture is i386 */
#define CONFIG_I386 0

/* Define to 1 if the target architecture is riscv */
#define CONFIG_RISCV 0

/* Define to 1 if the target architecture is x86_64 */
#define CONFIG_X86_64 1

/* Define to 1 if the target architecture is loongarch */
#define CONFIG_LOONGARCH 0

/* Define to 1 to use an external libtcc */
#define CONFIG_USE_LIBTCC 1

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 0

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define to 1 if you have the `m' library (-lm). */
#define HAVE_LIBM 1

/* Define to 1 if you have the `dl' library (-ldl). */
#define HAVE_LIBDL 0

/* Define to 1 if you have the `pthread' library (-lpthread). */
#define HAVE_LIBPTHREAD 1

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the <malloc.h> header file. */
#define HAVE_MALLOC_H 1

/* Define to 1 if you have the `alloca' function. */
#define HAVE_ALLOCA 1

/* Define to 1 if you have the `strtold' function. */
#define HAVE_STRTOLD 1

/* Define to 1 if you have the `__sync_val_compare_and_swap' function. */
#define HAVE_SYNC_VAL_COMPARE_AND_SWAP 1

/* Define to 1 if you have the `_lock_file' function. */
#define HAVE_LOCK_FILE 0

/* Define to 1 if you have the `_unlock_file' function. */
#define HAVE_UNLOCK_FILE 0

/* Define to 1 if you have the `__builtin_alloca' function. */
#define HAVE___BUILTIN_ALLOCA 1

/* Define to 1 if you have the `__builtin_expect' function. */
#define HAVE___BUILTIN_EXPECT 1

/* Define to 1 if you have the `__builtin_frame_address' function. */
#define HAVE___BUILTIN_FRAME_ADDRESS 1

/* Name of package */
#define PACKAGE "tcc"

/* Define to the address where bug reports for this package should be sent. */
#define PACKAGE_BUGREPORT ""

/* Define to the full name of this package. */
#define PACKAGE_NAME "TinyCC"

/* Define to the full name and version of this package. */
#define PACKAGE_STRING "TinyCC 0.9.28"

/* Define to the one symbol short name of this package. */
#define PACKAGE_TARNAME "tcc"

/* Define to the home page for this package. */
#define PACKAGE_URL ""

/* Define to the version of this package. */
#define PACKAGE_VERSION "0.9.28"

/* The size of `void *', as computed by sizeof. */
#define SIZEOF_VOID_P 8

/* The size of `int', as computed by sizeof. */
#define SIZEOF_INT 4

/* The size of `long', as computed by sizeof. */
#define SIZEOF_LONG 4

/* The size of `long long', as computed by sizeof. */
#define SIZEOF_LONG_LONG 8

/* The size of `short', as computed by sizeof. */
#define SIZEOF_SHORT 2

/* Define to 1 if you have the ANSI C header files. */
#define STDC_HEADERS 1

/* Define to 1 if you can safely include both <sys/time.h> and <time.h>. */
#define TIME_WITH_SYS_TIME 1

/* Version number of package */
#define VERSION "0.9.28"

/* Define to 1 if your processor stores words with the most significant byte
   first (like Motorola and SPARC, unlike Intel and VAX). */
#define WORDS_BIGENDIAN 0

/* Define to 1 if your processor stores words with the most significant byte
   first (like Motorola and SPARC, unlike Intel and VAX). */
#define WORDS_BIGENDIAN 0

/* Define to 1 if `lex' declares `yytext' as a `char *' by default, not a
   `char[]'. */
#define YYTEXT_POINTER 1

/* Define to 1 to build using an external libtcc */
#define CONFIG_USE_LIBTCC 1

/* Define to 1 to enable cross compilation */
#define CONFIG_TCC_CROSS 0

/* Define to 1 if you want to enable bounds checking */
#define CONFIG_TCC_BCHECK 1

/* Define to 1 if you want to enable backtrace */
#define CONFIG_TCC_BACKTRACE 1

/* Define to 1 if you want to enable ELF target */
#define CONFIG_TCC_ELF 0

/* Define to 1 if you want to enable PE target */
#define CONFIG_TCC_PE 1

/* Define to 1 if you want to enable Mach-O target */
#define CONFIG_TCC_MACHO 0

/* Define to 1 if you want to enable COFF target */
#define CONFIG_TCC_COFF 0

/* Define to 1 if you want to enable assembler */
#define CONFIG_TCC_ASM 1

/* Define to 1 if you want to enable linker */
#define CONFIG_TCC_LINKER 1

/* Define to 1 if you want to enable self compilation */
#define CONFIG_TCC_SELF 1

/* Define to 1 if you want to enable static linking */
#define CONFIG_TCC_STATIC 1

/* Define to 1 if you want to enable dynamic linking */
#define CONFIG_TCC_DLOPEN 0

/* Define to 1 if you want to enable the tinycc preprocessor */
#define CONFIG_TCC_PREPROCESSOR 1

/* Define to 1 if you want to enable the tinycc code generator */
#define CONFIG_TCC_CODEGEN 1

/* Define to 1 if you want to enable the tinycc runtime */
#define CONFIG_TCC_RUNTIME 1

/* Define to 1 if you want to enable the tinycc interpreter */
#define CONFIG_TCC_INTERPRETER 1

/* Define to 1 if the target is Windows (PE) */
#define TCC_TARGET_PE 1

/* Define to 1 if the target is x86_64 */
#define TCC_TARGET_X86_64 1

/* Define to 1 if the target is native */
#define TCC_IS_NATIVE 1

/* Define to 1 if the target is 64-bit */
#define TCC_TARGET_64 1

/* Define to 1 if the target is aarch64 */
#define TCC_TARGET_ARM64 0

/* Define to 1 if the target is arm */
#define TCC_TARGET_ARM 0

/* Define to 1 if the target is i386 */
#define TCC_TARGET_I386 0

/* Define to 1 if the target is riscv */
#define TCC_TARGET_RISCV 0

/* Define to 1 if the target is loongarch */
#define TCC_TARGET_LOONGARCH 0

/* Define to 1 if the target is macOS */
#define TCC_TARGET_MACHO 0

/* Define to 1 if the target is ELF */
#define TCC_TARGET_ELF 0

/* Define to 1 if the target is Windows */
#define TCC_TARGET_WINDOWS 1

/* Define to 1 if the target supports the __thread storage class */
#define HAVE___THREAD 1

/* Define to 1 if the target supports the __attribute__((visibility)) attribute */
#define HAVE_VISIBILITY 1

/* Define to the triplet of the target */
#define CONFIG_TRIPLET "x86_64-w64-mingw32"

/* Define to 1 if the compiler supports -fvisibility=hidden */
#define HAVE_FVISIBILITY 1

/* Define to 1 if the compiler supports -Wno-pointer-sign */
#define HAVE_WNO_POINTER_SIGN 1

/* Define to 1 if the compiler supports -Wno-unused-result */
#define HAVE_WNO_UNUSED_RESULT 1

/* Define to 1 if the compiler supports -Wno-format-truncation */
#define HAVE_WNO_FORMAT_TRUNCATION 1

/* Define to 1 if the compiler supports -Wno-implicit-fallthrough */
#define HAVE_WNO_IMPLICIT_FALLTHROUGH 1

/* Define to 1 if the compiler supports -Wno-maybe-uninitialized */
#define HAVE_WNO_MAYBE_UNINITIALIZED 1

/* Define to 1 if the compiler supports -Wno-array-bounds */
#define HAVE_WNO_ARRAY_BOUNDS 1
EOF
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
