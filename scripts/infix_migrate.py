#!/usr/bin/env python3
"""Convert Heaven .hvn S-expr → infix (safe transformations only).

Transformations :
  (+ a b)          → a + b        (idem -, *, /, ==, !=, <, >, <=, >=)
  (if c a b)       → if c then a else b
  (let x v body)   → let x = v in body
  foo = (bar ...)  → foo = bar ...  (si le RHS est une seule expr parenthésée)

Ne touche pas : strings, commentaires (--), parens imbriqués d'arguments
((f x y) reste (f x y), ou f x y si le RHS complet est (f x y)).

Usage : python3 scripts/infix_migrate.py FILE [--apply] [--diff]
"""
import sys, re
from pathlib import Path

OPS_INFIX = ['+', '-', '*', '/', '==', '!=', '<=', '>=', '<', '>']

def find_paren_end(s, start):
    depth = 0; in_str = False; i = start
    while i < len(s):
        c = s[i]
        if in_str:
            if c == '\\' and i + 1 < len(s): i += 2; continue
            if c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c == '(': depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0: return i
        i += 1
    return -1

def split_args(s, n):
    parts = []; depth = 0; in_str = False; start = 0
    for i, c in enumerate(s):
        if in_str:
            if c == '\\' and i + 1 < len(s): continue
            if c == '"': in_str = False
        else:
            if c == '"': in_str = True
            elif c == '(': depth += 1
            elif c == ')': depth -= 1
            elif c == ' ' and depth == 0:
                parts.append(s[start:i]); start = i + 1
                if len(parts) == n - 1:
                    parts.append(s[start:]); return parts
    if len(parts) == n - 1:
        parts.append(s[start:])
    return parts if len(parts) == n else []

def needs_parens(x):
    x = x.strip()
    return ' ' in x or (x and x[0] == '(') or (len(x) > 1 and x[0] == '-' and x[1].isdigit())

def transform(s, depth=0):
    if depth > 50: return s
    out = []; i = 0
    while i < len(s):
        # strings
        if s[i] == '"':
            j = i + 1
            while j < len(s):
                if s[j] == '\\': j += 2; continue
                if s[j] == '"': j += 1; break
                j += 1
            out.append(s[i:j]); i = j; continue
        # comments
        if s.startswith('--', i):
            j = s.find('\n', i)
            if j < 0: j = len(s)
            out.append(s[i:j]); i = j; continue
        if s[i] != '(':
            out.append(s[i]); i += 1; continue
        # try transformations
        matched = False
        for op in OPS_INFIX:
            m = f"({op} "
            if s.startswith(m, i):
                e = find_paren_end(s, i)
                if e < 0: break
                args = split_args(s[i+len(m):e], 2)
                if len(args) == 2:
                    a = transform(args[0].strip(), depth+1)
                    b = transform(args[1].strip(), depth+1)
                    if needs_parens(a): a = f"({a})"
                    if needs_parens(b): b = f"({b})"
                    out.append(f"{a} {op} {b}")
                    i = e + 1; matched = True; break
        if matched: continue
        # if
        if s.startswith('(if ', i):
            e = find_paren_end(s, i)
            if e > 0:
                args = split_args(s[i+4:e], 3)
                if len(args) == 3:
                    c = transform(args[0].strip(), depth+1)
                    a = transform(args[1].strip(), depth+1)
                    b = transform(args[2].strip(), depth+1)
                    out.append(f"if {c} then {a} else {b}")
                    i = e + 1; continue
        # let
        if s.startswith('(let ', i):
            e = find_paren_end(s, i)
            if e > 0:
                args = split_args(s[i+5:e], 3)
                if len(args) == 3:
                    x = args[0].strip()
                    v = transform(args[1].strip(), depth+1)
                    body = transform(args[2].strip(), depth+1)
                    out.append(f"let {x} = {v} in {body}")
                    i = e + 1; continue
        # generic paren recurse
        e = find_paren_end(s, i)
        if e > 0:
            out.append('(' + transform(s[i+1:e], depth+1) + ')')
            i = e + 1; continue
        out.append(s[i]); i += 1
    return ''.join(out)

def unparen_rhs(s):
    """foo = (bar ...) → foo = bar ... si le RHS complet est une seule expr parenthésée."""
    out = []
    for line in s.split('\n'):
        m = re.match(r'^(\s*[a-z_]\w*(?:\s+[^=]+)?)\s*=\s*(\(.*\))\s*$', line)
        if m:
            lhs, rhs = m.groups()
            if rhs.startswith('(') and find_paren_end(rhs, 0) == len(rhs) - 1:
                inner = rhs[1:-1]
                if re.match(r'^[a-z_]\w*(\s+.*)?$', inner):
                    out.append(f"{lhs} = {inner}")
                    continue
        out.append(line)
    return '\n'.join(out)

def migrate(path):
    s = Path(path).read_text()
    return unparen_rhs(transform(s))

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: infix_migrate.py FILE [--apply] [--diff]")
        sys.exit(1)
    path = sys.argv[1]
    apply = '--apply' in sys.argv
    show_diff = '--diff' in sys.argv
    orig = Path(path).read_text()
    new = migrate(path)
    if orig == new:
        print(f"[OK] {path} : déjà infixe")
        sys.exit(0)
    import difflib
    diff = list(difflib.unified_diff(orig.split('\n'), new.split('\n'), lineterm='', n=1))
    if show_diff:
        for d in diff[:80]: print(d)
        if len(diff) > 80: print(f"... ({len(diff)-80} lignes de plus)")
    if apply:
        Path(path).write_text(new)
        print(f"[APPLY] {path} : {len(diff)} lignes changées")
    else:
        print(f"[DRY]   {path} : {len(diff)} lignes à changer")
