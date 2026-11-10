#!/usr/bin/env python3
"""
mcp_diff_check.py — Test différentiel MCP ≡ Heaven (B4)

Vérifie que les 5 tools Heaven (kind=0 dans le registre) produisent
le même résultat via `heaven mcp` (JSON-RPC, callHeavenTool) et via
`heaven run` (TT.run_tool direct).

Ne couvre PAS les 11 tools natifs (kind=1) : ils n'ont pas
d'équivalent Heaven-side direct. B4b les ajoutera si pertinent.

Cas spéciaux time_now / time_ms : le timestamp varie entre les deux
appels, comparaison par tolérance (10s / 10s).

Usage :
    python3 scripts/mcp_diff_check.py            # informatif
    python3 scripts/mcp_diff_check.py --check    # exit 1 si échec
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

HEAVEN_BIN = "./zig-out/bin/heaven"


def mcp_call(name, args, timeout=10):
    req = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": args},
    }) + "\n"
    r = subprocess.run([HEAVEN_BIN, "mcp"], input=req,
                      capture_output=True, text=True, timeout=timeout)
    for line in r.stdout.splitlines():
        if '"id":1' in line and '"result"' in line:
            obj = json.loads(line)
            return obj["result"]["content"][0]["text"]
    raise RuntimeError(f"MCP no response (stdout={r.stdout[:200]!r})")


def heaven_call(name, args, timeout=8):
    body = json.dumps({"name": name, "arguments": args},
                      separators=(",", ":"))
    escaped = body.replace("\\", "\\\\").replace('"', '\\"')
    hvn = f'import "lib/mcp/tools.hvn" as TT\n(TT.run_tool "{escaped}")\n'
    with tempfile.NamedTemporaryFile("w", suffix=".hvn", delete=False) as f:
        f.write(hvn)
        path = f.name
    try:
        r = subprocess.run([HEAVEN_BIN, "run", path],
                          capture_output=True, text=True, timeout=timeout)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    # Le résultat de `heaven run` va sur stderr (debug.print), pas
    # stdout. On cherche sur les deux par robustesse.
    candidates = (r.stderr + "\n" + r.stdout).splitlines()
    for line in candidates:
        line = line.strip()
        if line and "Memory" not in line:
            if len(line) >= 2 and line[0] == '"' and line[-1] == '"':
                line = line[1:-1]
            return line
    raise RuntimeError(
        f"Heaven no output (stdout={r.stdout[:200]!r}, stderr={r.stderr[:200]!r})"
    )


CASES = [
    ("echo",         {"text": "hi"},                    "exact"),
    ("echo",         {"text": "hello world"},           "exact"),
    ("count_chars",  {"text": "hello"},                 "exact"),
    ("count_chars",  {"text": ""},                      "exact"),
    ("time_now",     {},                                "ts_sec"),
    ("time_ms",      {},                                "ts_ms"),
    ("fs_read",      {"path": "/etc/hostname"},         "exact"),
    ("fs_read",      {"path": "/nonexistent_xyz_404"},  "exact"),
]


def compare(kind, m, h):
    if kind == "exact":
        return m == h
    if kind == "ts_sec":
        return m.isdigit() and h.isdigit() and abs(int(m) - int(h)) < 10
    if kind == "ts_ms":
        return m.isdigit() and h.isdigit() and abs(int(m) - int(h)) < 10000
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit 1 si au moins un cas diffère")
    args = ap.parse_args()

    if not os.path.exists(HEAVEN_BIN):
        print(f"ERROR: {HEAVEN_BIN} introuvable. Lance `zig build`.")
        sys.exit(2)

    failures = []
    for name, a, kind in CASES:
        label = f"{name}({json.dumps(a, separators=(',', ':'))})"
        try:
            m = mcp_call(name, a)
            h = heaven_call(name, a)
            ok = compare(kind, m, h)
            tag = "OK" if ok else "FAIL"
            extra = ""
            if kind in ("ts_sec", "ts_ms") and ok:
                extra = f" (delta={abs(int(m) - int(h))})"
            print(f"[{tag}]   {label}: MCP={m!r} Heaven={h!r}{extra}")
            if not ok:
                failures.append(label)
        except Exception as e:
            print(f"[FAIL] {label}: {type(e).__name__}: {e}")
            failures.append(label)

    print()
    print(f"{len(CASES) - len(failures)}/{len(CASES)} cas OK")
    if failures:
        print(f"Échecs : {', '.join(failures)}")
        if args.check:
            sys.exit(1)


if __name__ == "__main__":
    main()
