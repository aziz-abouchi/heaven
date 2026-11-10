#!/usr/bin/env python3
"""
book_check_v2.py — verifie les blocs ```heaven du livre v2

Pour chaque docs/book/src-v2/*.md :
  - Extrait les blocs ```heaven
  - Skip les blocs dans `## Exercices` (sections pedagogiques)
  - Skip les blocs `<!-- doctest: skip -->`
  - Classifie:
    * test "..." present OU theorem+prove -> runnable
    * <!-- doctest: expect-fail --> -> runnable, attendu exit != 0
    * sinon -> ignore (fragment)
  - Execute via --run-test, verifie le exit code

MCP integration: 6 cas heaven_prove + registry.

Usage:
    python3 scripts/book_check_v2.py            # informatif
    python3 scripts/book_check_v2.py --check    # exit 1 si echec
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

BOOK_DIR = Path("docs/book/src-v2")
HEAVEN_BIN = "./zig-out/bin/heaven"
MARKER_LOOKBACK = 5


def find_marker(lines, fence_idx):
    start = max(0, fence_idx - MARKER_LOOKBACK)
    for i in range(fence_idx - 1, start - 1, -1):
        if '<!-- doctest: expect-fail -->' in lines[i]:
            return 'expect-fail'
        if '<!-- doctest: skip -->' in lines[i]:
            return 'skip'
    return None


def extract_blocks(md_path):
    """Retourne [(start_line, content, kind, marker)]"""
    lines = md_path.read_text().splitlines()
    exercise_start = None
    for i, line in enumerate(lines):
        if line.startswith('## Exercices'):
            exercise_start = i
            break

    blocks = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == '```heaven':
            fence_idx = i
            block_lines = []
            i += 1
            while i < len(lines) and lines[i].strip() != '```':
                block_lines.append(lines[i])
                i += 1
            content = '\n'.join(block_lines)

            marker = find_marker(lines, fence_idx)
            if marker == 'skip':
                blocks.append((fence_idx + 1, content, 'skipped-marker', marker))
                i += 1
                continue

            if exercise_start is not None and fence_idx > exercise_start and marker is None:
                blocks.append((fence_idx + 1, content, 'skipped-exercise', marker))
                i += 1
                continue

            has_test = 'test "' in content
            has_theorem = 'theorem ' in content and 'prove ' in content
            is_runnable = has_test or has_theorem or marker == 'expect-fail'

            kind = 'runnable' if is_runnable else 'ignored'
            blocks.append((fence_idx + 1, content, kind, marker))
            i += 1
            continue
        i += 1
    return blocks


def run_block_hvn(block_content, timeout=8):
    with tempfile.NamedTemporaryFile(mode='w', suffix='.hvn', delete=False) as f:
        f.write(block_content)
        if not block_content.endswith('\n'):
            f.write('\n')
        path = f.name
    try:
        r = subprocess.run([HEAVEN_BIN, "--run-test", path],
                          capture_output=True, text=True, timeout=timeout)
        return (r.returncode, r.stdout + r.stderr)
    except subprocess.TimeoutExpired:
        return (-1, "TIMEOUT")
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def check_mcp_prove(timeout=10):
    results = []
    cases = [
        ("kernel_simplify_ok", "theorem t1 : x + 0 = x", "prove t1 by { simplify }", True),
        ("kernel_simplify_bad", "theorem bad : x + 1 = x", "prove bad by { simplify }", False),
        ("kernel_reflexivity", "theorem t1b : x + 0 = x", "prove t1b by { reflexivity }", False),
        ("kernel_induction", "theorem t1c : x + 0 = x", "prove t1c by { induction on x }", False),
    ]
    for name, eval_expr, prove_stmt, expect_proved in cases:
        inp = (json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"heaven_eval","arguments":{"expression":eval_expr}}}) + "\n" +
               json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"heaven_prove","arguments":{"statement":prove_stmt}}}) + "\n")
        try:
            r = subprocess.run([HEAVEN_BIN, "mcp"], input=inp, capture_output=True, text=True, timeout=timeout)
            prove_resp = None
            for line in r.stdout.splitlines():
                if '"id":2' in line:
                    prove_resp = json.loads(line)
                    break
            if prove_resp is None:
                results.append((name, expect_proved, "no_response", False))
                continue
            inner = json.loads(prove_resp['result']['content'][0]['text'], strict=False)
            actual = inner.get('proved')
            results.append((name, expect_proved, actual, actual == expect_proved))
        except Exception as e:
            results.append((name, expect_proved, f"error:{e}", False))

    # Panic case
    inp = json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"heaven_prove","arguments":{}}}) + "\n"
    try:
        r = subprocess.run([HEAVEN_BIN, "mcp"], input=inp, capture_output=True, text=True, timeout=timeout)
        has_panic = 'panic' in r.stdout or 'panic' in r.stderr
        results.append(("prove_no_statement", "no_panic", "panic" if has_panic else "ok", not has_panic))
    except subprocess.TimeoutExpired:
        results.append(("prove_no_statement", "no_panic", "TIMEOUT", False))

    # Registry
    try:
        r = subprocess.run([HEAVEN_BIN, "--run-test", "tests/tool_registry/registry.hvn"],
                          capture_output=True, text=True, timeout=timeout)
        results.append(("registry_24", "exit_0", f"exit_{r.returncode}", r.returncode == 0))
    except subprocess.TimeoutExpired:
        results.append(("registry_24", "exit_0", "TIMEOUT", False))

    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 si echec")
    ap.add_argument("--skip-mcp", action="store_true")
    args = ap.parse_args()

    if not Path(HEAVEN_BIN).exists():
        print(f"ERROR: {HEAVEN_BIN} introuvable. Lance `zig build`.")
        sys.exit(2)

    md_files = sorted(BOOK_DIR.glob("*.md"))
    if not md_files:
        print(f"ERROR: aucun .md dans {BOOK_DIR}")
        sys.exit(2)

    total_pass = 0
    total_ef_ok = 0
    total_ef_bad = 0
    total_ignored = 0
    total_skipped_ex = 0
    total_skipped_marker = 0
    failures = []

    for md in md_files:
        blocks = extract_blocks(md)
        if not blocks:
            continue
        pass_n = fail_n = ignored_n = 0
        for start_line, content, kind, marker in blocks:
            if kind == 'ignored':
                ignored_n += 1
                continue
            if kind == 'skipped-exercise':
                total_skipped_ex += 1
                continue
            if kind == 'skipped-marker':
                total_skipped_marker += 1
                continue
            exit_code, output = run_block_hvn(content)
            passed = (exit_code == 0)
            is_ef = (marker == 'expect-fail')
            if is_ef:
                if not passed:
                    total_ef_ok += 1
                    pass_n += 1
                else:
                    total_ef_bad += 1
                    failures.append((md.name, start_line, "expect-fail but passed"))
            else:
                if passed:
                    total_pass += 1
                    pass_n += 1
                else:
                    fail_n += 1
                    failures.append((md.name, start_line, f"exit={exit_code}"))
                    print(f"  FAIL {md.name}:{start_line}")
                    for l in output.splitlines()[:6]:
                        print(f"    {l}")
        total_ignored += ignored_n
        if pass_n + fail_n > 0:
            print(f"  {md.name}: {pass_n} pass, {fail_n} fail, {ignored_n} ignored")

    mcp_results = []
    if not args.skip_mcp:
        print("\nMCP integration:")
        mcp_results = check_mcp_prove()
        for name, exp, act, ok in mcp_results:
            status = "OK" if ok else "FAIL"
            print(f"  [{status}] {name}: expected {exp}, got {act}")
            if not ok:
                failures.append(("mcp", name, f"expected {exp}, got {act}"))

    print()
    print("=" * 60)
    print(f"Book blocks: {total_pass} pass, {total_ef_ok} expect-fail (OK), "
          f"{total_ef_bad} expect-fail (BAD), {total_ignored} ignored, "
          f"{total_skipped_ex} skipped-exercise, {total_skipped_marker} skipped-marker")
    if mcp_results:
        ok_count = sum(1 for _,_,_,ok in mcp_results if ok)
        print(f"MCP cases: {ok_count}/{len(mcp_results)} OK")
    if failures:
        print(f"\n{len(failures)} failure(s):")
        for f in failures:
            print(f"  {f[0]}:{f[1]} — {f[2]}")
        if args.check:
            sys.exit(1)
    else:
        print("\nAll checks pass.")


if __name__ == "__main__":
    main()
