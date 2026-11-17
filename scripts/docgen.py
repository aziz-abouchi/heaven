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


# Codes de retour des suites : une suite qui echoue ne doit jamais
# produire de chiffres verts dans la doc.
EXIT_CODES = {}


def sh(*cmd):
    r = subprocess.run(list(cmd), capture_output=True, text=True)
    EXIT_CODES[" ".join(cmd)] = r.returncode
    return r.stdout + r.stderr


def extract_facts():
    f = {}

    # tests_zig : "N/M tests passed"
    out = sh("zig", "build", "test", "--summary", "all")
    m = re.search(r"(\d+)/(\d+) tests passed", out)
    f["tests_zig"] = m.group(1) if m else "?"
    f["tests_zig_total"] = m.group(2) if m else "?"

    # tests_heaven : total des tests Heaven reellement executes par le CI
    # = test-regression (core/test_suite.hvn) + test-files (tests/*.hvn)
    # Ce n'est pas un compte de declarations `test "..."` mais de
    # resultats "N passed" effectifs (assert_eq comptent aussi).
    n_reg = 0
    n_reg_total = 0
    out = sh("zig", "build", "-Dnetwork=false", "test-regression")
    for m in re.finditer(r"Total: (\d+) / (\d+)", out):
        n_reg, n_reg_total = int(m.group(1)), int(m.group(2))
    n_reg_leaks = out.count("MEMORY LEAK DETECTED")
    n_files = 0
    n_files_total = 0
    out = sh("zig", "build", "-Dnetwork=false", "test-files")
    n_files_leaks = out.count("MEMORY LEAK DETECTED")
    totals = re.findall(r"Total: (\d+) / (\d+)", out)
    if totals:
        # Somme de tous les "Total: X / Y" (une par fichier de tests)
        n_files = sum(int(t[0]) for t in totals)
        n_files_total = sum(int(t[1]) for t in totals)
    f["tests_heaven"] = str(n_reg + n_files)
    f["tests_heaven_regression"] = str(n_reg)
    f["tests_heaven_files"] = str(n_files)

    # date
    f["date"] = date.today().isoformat()

    # test-regression / test-files : valeurs string pour README
    # Le denominateur vient du log, PAS du numerateur : l'ancienne
    # ecriture f"{n_reg}/{n_reg}" etait une tautologie incapable de
    # rapporter un echec.
    f["test_regression"] = f"{n_reg}/{n_reg_total}" if n_reg_total else "?"
    f["test_files"] = f"{n_files}/{n_files_total}" if n_files_total else "?"
    f["test_files_count"] = str(len(list(Path("tests").glob("*.hvn"))))

    red = []
    for cmd, rc in EXIT_CODES.items():
        if rc != 0:
            red.append(f"{cmd} -> exit {rc}")
    if n_reg_leaks:
        red.append(f"test-regression : {n_reg_leaks} fuite(s)")
    if n_files_leaks:
        red.append(f"test-files : {n_files_leaks} fuite(s)")
    f["_red"] = red

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

    red = facts.pop("_red", [])
    if red:
        print("\n✗ SUITE ROUGE — publication des chiffres refusee :", file=sys.stderr)
        for r in red:
            print(f"    {r}", file=sys.stderr)
        sys.exit(1)

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
