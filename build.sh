#!/bin/bash
set -e

ROOT_DIR=$(pwd) VENDOR_DIR="$ROOT_DIR/vendor"

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
		cd "$target"
		tree-sitter generate
		cd "$ROOT_DIR"
	fi
}

#setup_parser "heaven" "https://github.com/aziz-abouchi/tree-sitter-heaven.git"
setup_parser "pie" "https://github.com/syrkis/tree-sitter-pie"
setup_parser "c" "https://github.com/tree-sitter/tree-sitter-c"
setup_parser "zig" "https://github.com/maxxnino/tree-sitter-zig"

echo "[FORGE] Parsers prêts."

#─── Build via zig build ───
echo "[FORGE] Compilation..." zig build

echo "[FORGE] Tests..." zig build test

echo "[FORGE] Terminé. Lancer avec: zig build run -- <port>"
