#!/usr/bin/env python3
"""Compte les parenthèses d'un fichier .hvn. Ignore les commentaires (--)."""
import sys, re

def check(path):
    with open(path) as f:
        lines = [re.sub(r'--.*$', '', l) for l in f.read().split('\n')]
    depth = 0
    ln = 0
    for raw in lines:
        ln += 1
        for col, ch in enumerate(raw):
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth < 0:
                    print(f"{path}:{ln}:{col+1}: ')' non appariée")
                    return False
    if depth != 0:
        which = "')'" if depth > 0 else "'('"
        print(f"{path}: déséquilibre — manque {abs(depth)} {which}")
        return False
    print(f"{path}: OK")
    return True

if __name__ == "__main__":
    sys.exit(0 if all(check(p) for p in sys.argv[1:]) else 1)
