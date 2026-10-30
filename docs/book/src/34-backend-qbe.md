# Backend QBE — Compilation native

> Du MIR à QBE IL, puis binaire natif via qbe-1.2.

## Pipeline

    Source.hvn → parse → Core AST
      → lowerRec → MIR (Instr)
      → precompileUserFns (fns user en fn_defs)
      → compileExpr (body) → MirFunction
      → mir_qbe.emitQbe → SSA QBE (prog.ssa)
      → qbe-1.2/prog.ssa → prog.s → cc → binaire natif

## Opcodes MIR

    Instr = union(enum) {
        const_int, add, sub, mul, div,
        cmp_lt, cmp_eq,
        jump, branch, ret, phi,
        load, store,
        alloc, load_at, store_at,   -- heap (2026-10-30)
        call_user, extern_call,
    }

## 6 builtins heap

    -- pair(a, b) = alloc(16) + store_at(0, a) + store_at(8, b)
    -- fst(p)     = load_at(p, 0)
    -- snd(p)     = load_at(p, 8)
    -- cons/head/tail = alias pair/fst/snd

## Ce qui marche (2026-10-30)

    (fst (pair 1 2))     → 1
    (choose 1)           → 42  (if simple)
    (check (pair 1 99))  → 42  (if + fst)
    (sign -5)            → -1  (if imbrique, < et >)

4/5 cas fonctionnels. phi3 lève `UnsupportedOp` (parser/lowering).

## Limites

- Fns std strings/bytes/http skippées (99 sur 142)
- `range` n'existe pas → benchmarks invalides
- Build 2m05s par patch (mir.zig importé par 10 modules)

## Référence

`docs/spec/_runtime_gaps.md` § compile-qbe.

## Mises à jour 2026-10-30 (soir) — selfhost

Voir [ch. 39 selfhosting](39-selfhosting.md). Résumé :

- `main = EXPR` compilé (avant : expression nue seulement)
- `const_str` : strings littérales émises via `data $str_N`
- `@puts`, `@printf`, `@getenv`, `@strcmp` (extern_call glibc)
- `@argv N` natif, wrapper `l $main(l argc, l argv)` (ABI SysV)
- Wrapper `ret %r` : exit code = valeur de dispatch
- `bin/heaven.hvn` V0.6 : dispatch CLI via `@strcmp` + `if`

Pièges connus (non résolus) : [G.25](G-pieges.md) multi-clauses,
[G.33](G-pieges.md) `@argv` fn user, [G.34](G-pieges.md)
`@strcmp` fn user.
