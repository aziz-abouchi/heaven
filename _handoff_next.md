# Handoff — prochain chat (2026-10-21)

## Objectif unique
Fix `.zig` `let + recursion` = ExecutionFailed (bloque QTT, loop MCP, web_lookup 6e tool, dispatch direct).

## Docs à coller en premier
- `_session_continuity.md` (15+ pièges)
- `docs/spec/_let_chain_bug.md` (5 discriminants, éliminations)
- `docs/PRIMER.md` (contrat implicite + debug)

## Etat git
- HEAD = c890ba8 (docs cleanup)
- git status = clean
- Baseline : zig build = 0, zig build test = 405/407 (2 fails pré-existants), wasm x2 = 0

## Discipline (leçons session 2026-10-21)
1. **Instrumenter AVANT patcher**. `std.debug.print` natif, PAS `platform.dbg` (muet sans HEAVEN_DEBUG=1).
2. **Cutoff 3 blocs diagnostic**, puis rollback + doc + pause.
3. **Pas de 4e patch aveugle** : 3 fixes `.zig` ont été tentés + rollback cette session (evalCmp OK, save/restore KO, dispatch KO). Le prochain doit être instrumenté.
4. **`let + recursion` est isolé** : pas collision, pas shadow, pas `+`, pas delete. Tester `.bind` + `.apply` avec log.

## Bloc 1 du prochain chat (instrumentation pure)

    cp -n src/core/engine_expr.zig src/core/engine_expr.zig.letrec.bak
    python3 - <<'PY2'
    from pathlib import Path
    p = Path("src/core/engine_expr.zig"); s = p.read_text()
    old = """        .bind => {
            if (node.span_a.len < 1) return error.ArityMismatch;"""
    new = """        .bind => {
            std.debug.print("[BIND] depth={d} payload={d}\n", .{depth, node.payload});
            if (node.span_a.len < 1) return error.ArityMismatch;"""
    assert old in s
    p.write_text(s.replace(old, new, 1))
    PY2
    zig build 2>&1 | grep error | head -2
    ./zig-out/bin/heaven run /tmp/t1.hvn 2>&1 | head -30  # /tmp/t1.hvn = rec n = if n > 0 then let m = n-1 in rec m else 0

Voir `[BIND]` avant crash. Si aucun `[BIND]` -> parser ne crée pas le bind. Si plusieurs -> recursion atteint bind plusieurs fois.

## Ce qui a été livré cette session (pour contexte)
- lib/web/ontology.hvn (DBpedia live, 13/13)
- MCP 5 tools E2E stables
- LSP MVP initialize E2E
- Livre restructuré 4 parties + 0.5
- 4 SVG créés, 66/66 référencées
