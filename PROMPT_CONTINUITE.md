# Prompt de continuité — Heaven session suivante

## HEAD
11ca8f4 (main) — docs sync 2026-09-30 (STATUS/BACKENDS/CHANGELOG)
Session : f31b2eb (fix mir+defs), 22de554 (_bench.md), 097a493 (fib.hvn)
Tout poussé sur origin/main.

## Tests
Zig : 381/382 (1 skip test_mir_wat).
HVN : ~95/95.

## Ce qui a été fait cette session
- QBE v1.2 opérationnel (compile + bench).
- WASM via wasmtime (M2a/M2b).
- bench-interp / bench-qbe / bench-wasm : wall, cpu, energy RAPL,
  temperature, RSS, --loop.
- Compilation des fonctions utilisateur recursives : fib(25) = 75025
  en QBE 1.15 ms (vs 29824 ms interprete, ~26000x).
- bench/run.sh, bench/progs/{count_down,arith,loop,fib}.hvn.
- docs/spec/_bench.md : methodologie et resultats.

## Fix majeur — fonctions utilisateur (f31b2eb)
3 bugs chaines :
1. defs.zig : parseSExpr pour les corps S-expr purs. parseExpression
   -> tree-sitter confond `<` avec une balise et currifie.
2. defs.zig : lowerRec uniforme (le cas "sans patterns" l'oubliait).
3. mir.zig : precompileUserFns en 2 passes (placeholders avant
   compilation des corps). Resout la recursion (fib appelle fib).

## WIP externe (NE PAS TOUCHER)
- src/core/heaven_expr.zig + engine_expr.zig + parse.zig : feature
  "guards" (autre session). ~88 l. de diff non commitees.
  BUGBLOQUANT chez eux : heaven_expr.zig:516 a
  `self.engine.fns.functions.getPtr` au lieu de
  `self.engine.fns.getPtr` (fns est deja la map). Corrige
  localement, pas commit.
- tests/guards.hvn : leur test (untracked).
- src/core/parse.zig, src/runtime/shell/commands_test.zig :
  modifies non commites.
- core/std/*.hvn, core/test_suite.hvn, src/vessel/public/*.hvn :
  WIP, ne pas toucher.

## Pistes pour la prochaine session
1. TCO WASM/QBE : mir_wat/mir_qbe convertissent recursion tail en
   boucle -> supprime le besoin de `-W max-wasm-stack=67108864`.
2. Rattraper bench-wasm fib (le dernier bench a timeout).
3. Complete _bench.md avec les chiffres fib interp vs QBE.
4. Fix RAPL persistant (udev rule) pour eviter `sudo chmod +r`.
5. Auto-hebergement (long terme) : BigInt (libtommath), I/O,
   structures de donnees, puis self-parse/self-compile.

## Fichiers de reference
- src/commands/qbe_cmd.zig, wasm_cmd.zig, bench_interp.zig
- src/backend/mir_qbe.zig, mir_wat.zig
- src/core/mir.zig (precompileUserFns)
- src/core/commands/defs.zig (parseSExpr)
- bench/run.sh, bench/progs/
- docs/spec/_bench.md

## Methodes
- Heredoc > 50 l. = tronque par navigateur (scinder en 2-3 blocs).
- git add cible uniquement (jamais -A, 3 sessions sur l'arbre).
- Avant de retoucher mir.zig/defs.zig, verifier qu'aucune session
  parallèle n'y travaille.
- Utiliser src/platform/* pour toute syscall, jamais std.posix direct.

## Addendum -- session guards (2026-10-01)

### Livre
- 867ec43 : guards sur clauses (f p | cond = body). 17/17.
  6 bugs de suture (tokenizer lhs_eff, split =, == non evaluable,
  mem.replace in-place = corruption tas). Credit : fix fns.getPtr
  (session MIR/QBE) inclus.
- d377a73 : STATUS guards ✅. 7be1b81 : tranchages comprehensions
  (ROADMAP, 5 decisions : syntaxe double, sequentiel, linear,
  SubstStream, Set-quotient).

### Conventions #17-#18
- #17 : std.mem.replace exige src != dest (in-place = UB,
  SIGSEGV differe DebugAllocator).
- #18 : ASCII seul (commands, patches, commits).

### File
- t_distrib ~2s (regression vivante, piste nodeHash)
- tco_deep ~40us/iter (trampoline)
- M4 Green/Fast (debloque depuis M3)
- Comprehensions : spec decidee, implementation a ouvrir
