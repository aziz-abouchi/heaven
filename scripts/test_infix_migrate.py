#!/usr/bin/env python3
"""Tests unitaires de scripts/infix_migrate.py (P1a, 2026-11-04).

transform() : convertit les ops/if/let en infixe, PRESERVE les parens.
unparen_rhs() : strippe les parens top-level d'un RHS de '=' si une seule expr.
Combinaison (== migrate) : ce qui est réellement appliqué aux fichiers.
"""
import sys
sys.path.insert(0, 'scripts')
from infix_migrate import transform, unparen_rhs

PASS = 0
FAIL = 0

def eq(name, got, expected):
    global PASS, FAIL
    if got == expected:
        PASS += 1; print(f"  ✓ {name}")
    else:
        FAIL += 1; print(f"  ✗ {name}")
        print(f"      got     : {got!r}")
        print(f"      expected: {expected!r}")

def migrate_line(line):
    """Simule ce que le script fait sur une ligne."""
    return unparen_rhs(transform(line))

print("═══ transform : ops/if/let wrappés, parens préservés ═══")

eq("(+ 1 2) → (1 + 2)",
   transform("(+ 1 2)"), "(1 + 2)")
eq("(== 1 1) → (1 == 1)",
   transform("(== 1 1)"), "(1 == 1)")
eq("arg infixe : (f x (+ y z)) → (f x (y + z))",
   transform("(f x (+ y z))"), "(f x (y + z))")
eq("if : (if (< a b) a b) → (if (a < b) then a else b)",
   transform("(if (< a b) a b)"), "(if (a < b) then a else b)")
eq("négatif : (- 0 5) → (0 - 5)",
   transform("(- 0 5)"), "(0 - 5)")

print()
print("═══ migrate_line : unparen_rhs strippe RHS de '=' ═══")

eq("foo = (+ 1 2)",
   migrate_line("foo = (+ 1 2)"), "foo = 1 + 2")
eq("foo = (f x (+ y z))",
   migrate_line("foo = (f x (+ y z))"), "foo = f x (y + z)")
eq("foo = (if c a b)",
   migrate_line("foo = (if c a b)"), "foo = if c then a else b")
eq("foo = (cons 1 (cons 2 nil))",
   migrate_line("foo = (cons 1 (cons 2 nil))"), "foo = cons 1 (cons 2 nil)")

print()
print("═══ non-régression : strings, comments, appels non-infixes ═══")

eq("string préservée : (f \"a b\")",
   transform('(f "a b")'), '(f "a b")')
eq("appel non-infixe : (foo bar baz)",
   transform("(foo bar baz)"), "(foo bar baz)")

print()
print(f"[{'DONE' if FAIL == 0 else 'FAIL'}] {PASS} passed, {FAIL} failed")
sys.exit(0 if FAIL == 0 else 1)
