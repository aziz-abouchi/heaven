#!/usr/bin/env python3
"""
docgen.py — met à jour les valeurs factuelles dans la documentation.

Usage :
    python3 scripts/docgen.py            # met à jour
    python3 scripts/docgen.py --check    # vérifie, exit 1 si divergence

Marqueurs dans les .md :
    <!-- DOCGEN:key -->valeur<!-- /DOCGEN -->
"""
import argparse
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

DOCS = [Path("README.md")]


def sh(*cmd):
    r = subprocess.run(list(cmd), capture_output=True, text=True)
    return r.stdout + r.stderr


def extract_facts():
    f = {}

    # tests_zig : "N/M tests passed"
    out = sh("zig", "build", "test", "--summary", "all")
    m = re.search(r"(\d+)/(\d+) tests passed", out)
    f["tests_zig"] = m.group(1) if m else "?"
    f["tests_zig_total"] = m.group(2) if m else "?"

    # tests_heaven : tous les tests Heaven executables en CI =
    #   core/test_suite.hvn (test-regression)
    #   tests/*.hvn        (test-files)
    # Les tests/experimental/*.hvn sont exclus (non executes par le CI).
    n = 0
    core = Path("core/test_suite.hvn")
    if core.exists():
        n += len(re.findall(r'test "', core.read_text()))
    for hvn in Path("tests").glob("*.hvn"):
        n += len(re.findall(r'test "', hvn.read_text()))
    f["tests_heaven"] = str(n)

    # date
    f["date"] = date.today().isoformat()

    # test-regression
    out = sh("zig", "build", "-Dnetwork=false", "test-regression")
    m = re.search(r"Total: (\d+) / (\d+)", out)
    f["test_regression"] = f"{m.group(1)}/{m.group(2)}" if m else "?"

    # test-files : plusieurs Totals (un par fichier), on prend le dernier
    out = sh("zig", "build", "-Dnetwork=false", "test-files")
    matches = re.findall(r"Total: (\d+) / (\d+)", out)
    f["test_files"] = f"{matches[-1][0]}/{matches[-1][1]}" if matches else "?"
    # nombre de fichiers .hvn dans tests/
    f["test_files_count"] = str(len(list(Path("tests").glob("*.hvn"))))

    return f


MARKER_RE = re.compile(
    r"<!-- DOCGEN:(\w+) -->.*?<!-- /DOCGEN -->", re.DOTALL
)


def apply_markers(text, facts):
    def repl(m):
        key = m.group(1)
        if key in facts:
            return f"<!-- DOCGEN:{key} -->{facts[key]}<!-- /DOCGEN -->"
        return m.group(0)

    return MARKER_RE.sub(repl, text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="Ne pas écrire, échouer si divergence")
    args = ap.parse_args()

    print("Extraction des faits...")
    facts = extract_facts()
    for k, v in sorted(facts.items()):
        print(f"  {k} = {v}")

    any_change = False
    for doc in DOCS:
        if not doc.exists():
            continue
        original = doc.read_text()
        updated = apply_markers(original, facts)
        if updated != original:
            any_change = True
            if args.check:
                print(f"✗ {doc} : valeurs périmées (run sans --check pour corriger)",
                      file=sys.stderr)
            else:
                doc.write_text(updated)
                print(f"✓ {doc} mis à jour")
        else:
            print(f"✓ {doc} : à jour")

    if args.check and any_change:
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
