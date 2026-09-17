#!/usr/bin/env bash
# tools/extract_book_tests.sh
# Extrait les blocs ```hvn du livre en une suite exécutable.
# Usage: bash tools/extract_book_tests.sh && zig-out/bin/heaven --run-test core/book_suite.hvn

set -euo pipefail
BOOK_DIR="docs/book/src"
OUT="core/book_suite.hvn"

shopt -s nullglob
CHAPTERS=("$BOOK_DIR"/*.md)
[ ${#CHAPTERS[@]} -gt 0 ] || { echo "[book-tests] aucun chapitre dans $BOOK_DIR" >&2; exit 1; }

{
    echo "# ═══ Suite générée depuis le livre — NE PAS ÉDITER ═══"
    echo "# Régénérer : bash tools/extract_book_tests.sh"
    for chapter in "${CHAPTERS[@]}"; do
        name=$(basename "$chapter" .md)
        awk -v chap="$name" '
            /^```hvn[[:space:]]*$/ { inblock=1; n++; print ""; print "# ── " chap " (bloc " n+") ──"; next }
            /^```$/                 { inblock=0; next }
            inblock { print }
        ' "$chapter"
    done
} > "$OUT"

echo "[book-tests] $OUT : ${#CHAPTERS[@]} chapitres, $(grep -cv '^\s*$\|^\s*#' "$OUT" || true) lignes actives"
