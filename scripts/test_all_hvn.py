#!/usr/bin/env python3
"""test_all_hvn.py — lance tous les tests .hvn bloquants en parallèle."""
import subprocess, sys, os, glob, re, concurrent.futures
from pathlib import Path

HEAVEN = "./zig-out/bin/heaven"
TIMEOUT = int(os.environ.get("TIMEOUT", "10"))
WHITELIST = Path("scripts/test_all_hvn_known_fails.txt")
NPROC = int(os.environ.get("NPROC", "4"))  # 4 par défaut, race conditions en parallèle sur fixtures

PATTERNS = [
    "tests/*.hvn", "tests/imports/*.hvn", "tests/hvn_pl/*.hvn",
    "tests/optics/*.hvn", "tests/hab/*.hvn", "tests/eval/*.hvn",
    "tests/hvn-check/thunks.hvn",
    "tests/hvn-check/with-test.hvn",
    "tests/hvn-check/if-sexpr.hvn",
    "tests/qtt/let_quantities_ok.hvn",
    "tests/io/result.hvn",
    "tests/io/read_lines.hvn",
]

def load_whitelist():
    wl = set()
    if WHITELIST.exists():
        for line in WHITELIST.read_text().splitlines():
            line = line.split("#")[0].strip()
            if line: wl.add(line)
    return wl

def collect_files():
    files = []
    for pat in PATTERNS:
        for f in glob.glob(pat):
            if f.endswith(".hvn.skip") or f.endswith(".bak"): continue
            files.append(f)
    return sorted(files)

def _run_once(f):
    try:
        out = subprocess.run(
            ["timeout", str(TIMEOUT), HEAVEN, "--run-test", f],
            capture_output=True, text=True, timeout=TIMEOUT + 5,
        )
        stdout = out.stdout + out.stderr
        m = re.search(r"Total:\s*(\d+)\s*/\s*(\d+)", stdout)
        if not m: return (f, "CRASH", 0, 0)
        n, mm = int(m.group(1)), int(m.group(2))
        return (f, "PASS" if (n == mm and mm > 0) else "FAIL", n, mm)
    except subprocess.TimeoutExpired:
        return (f, "TIMEOUT", 0, 0)
    except Exception:
        return (f, "ERROR", 0, 0)

def run_one(f):
    r = _run_once(f)
    # Retry 1x si FAIL/CRASH/ERROR (flaky parallèle, fixtures partagées)
    if r[1] in ("FAIL", "CRASH", "ERROR"):
        r2 = _run_once(f)
        if r2[1] == "PASS":
            print(f"  ✓ {r2[2]}/{r2[3]}  {f}  (retry)", flush=True)
            return r2
    return r

def main():
    wl = load_whitelist()
    files = collect_files()
    to_run = [f for f in files if f not in wl]
    skipped = len(files) - len(to_run)

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=NPROC) as ex:
        for r in ex.map(run_one, to_run):
            results.append(r)
            f, st, n, mm = r
            if st == "PASS": print(f"  ✓ {n}/{mm}  {f}", flush=True)
            elif st == "FAIL": print(f"  ✗ {n}/{mm}  {f}", flush=True)
            elif st == "TIMEOUT": print(f"  ⏱  {f}", flush=True)
            else: print(f"  ✗  {f} (crash)", flush=True)

    passed = sum(1 for r in results if r[1] == "PASS")
    failed = sum(1 for r in results if r[1] in ("FAIL", "CRASH", "ERROR"))
    timeout = sum(1 for r in results if r[1] == "TIMEOUT")
    bad = failed + timeout

    print()
    print("═══════════════════════════════════════════════")
    print(f"  ✓ {passed} passed    ✗ {failed} failed    ⏱ {timeout} timeout    ⊘ {skipped} skipped")
    if bad > 0:
        print("───────────────────────────────────────────────")
        for f, st, _, _ in results:
            if st not in ("PASS",): print(f"    {f}")
    print("═══════════════════════════════════════════════")
    sys.exit(0 if bad == 0 else 1)

if __name__ == "__main__":
    main()
