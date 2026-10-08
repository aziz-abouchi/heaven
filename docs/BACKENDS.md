# Backends — architecture cible et état réel

> Statut : **spec** (QBE/LLVM non implémentés). Mis à jour 2026-09-29
> après audit du code. Toute affirmation pointe vers un fichier
> vérifiable. Divergence constatée : corriger ce document.

## 1. Vision

                    Heaven Core
                        │
                      Expr
                        │
                    Lowering
                        │
                       MIR
                        │
        ┌───────────────┼────────────────┐
        │               │                │
       WASM            QBE             LLVM
        │               │                │
     browser/WASI    native         optimized native
                        │                │
                  ┌─────┼─────┐      ┌───┼────┐
                  │     │     │      │   │    │
                 x86   ARM   RISC-V x86 ARM WASM

**MIR = contrat commun.** Un seul pipeline de lowering (tree-sitter →
syntax/ast → RFC-0001 → core/expr → MIR) et N consommateurs. Règle :
jamais de pipeline parallèle. On rebranche l'existant sur le hub.

## 2. Priorités

| Backend | Rôle | Priorité |
|---|---|---|
| WASM/WAT | portable, Web, distribué | **immédiate** |
| QBE | natif rapide, rapport effort/gain (x86-64/ARM64/RISC-V) | native |
| LLVM | optimisation avancée (PGO, vectorisation) | ultérieure |
| C (+TCC) | bootstrap, portabilité, FFI | conservé |
| JS / LaTeX | transpilation, représentation | maintenus, hors Green/Fast |
| x86/ARM Heaven natifs | recherche, optimisation ciblée | ultérieure |

Zig reste runtime et infrastructure, pas un backend de production.

## 3. Stratégie Green/Fast

Sélection **explicite** : flag compile-time + profil runtime.
- **Fast** : pipeline complet, optimisations agressives (QBE puis LLVM).
- **Green** : passes minimales + instrumentation énergie branchée sur
  le profiler `green` existant (effets algébriques, roadmap #12).
## 4. Trois pipelines « WASM » (à ne pas confondre)

1. **heaven.wasm** : le compilateur lui-même compilé en WASM
   (`build.sh`, `-Dtarget=wasm32-freestanding`) pour le REPL web.
   Existant, fonctionnel.
2. **kernel-AST → WASM** (`src/backend/wasm.zig` + `test_wasm.zig`) :
   contenu computationnel des termes CIC **après effacement des
   preuves/quotients** (`class x` → `local.get`, `lift f p` émet `f`
   et jette la preuve). Ébauche (157 l.), fichier gelé.
3. **MIR → WASM** (futur, jalon M2) : codegen des programmes Heaven
   depuis le MIR. N'existe pas.

## 5. État réel (audité 2026-09-29)

| Composant | Fichier | État |
|---|---|---|
| MIR (IR + interp) | `src/core/mir.zig` (~1050 l.) | `compileExpr`, `execute` (i64), `dump` ; 15 instr ; `precompileUserFns` ; commande `mir` |
| MIR -> WAT | `src/backend/mir_wat.zig` | M2a ✅ ; `compile-wasm`, `bench-wasm` |
| MIR -> QBE IL | `src/backend/mir_qbe.zig` | M3 ✅ ; `compile-qbe`, `bench-qbe` |
| C / JS / LaTeX | `src/codegen/{expr_c,expr_js,expr_latex}.zig` | depuis Expr, vivants |
| TCC | `vendor/tcc` + build.zig | compilé/linké ; usage runtime à auditer |
| x86-64 | `src/core/x86_64.zig` (37 l.) | stub `emitFromFunction(MirFunction)` |
| emitC minimal | `src/backend/codegen.zig` (70 l.) | doublon potentiel d'expr_c, vestige ? |
| LLVM | `src/legacy/vessel/llvm_gen.zig` (60 l.) | simulation, pas un backend |

**Le point clé** : le MIR est presque orphelin. Interpréteur sérieux,
consommateur x86 en stub, pendant que les backends vivants partent
d'Expr (C/JS/LaTeX) ou du kernel-AST (wasm.zig). Le chantier n'est
pas de construire un pipeline mais de rebrancher l'existant sur MIR.

## 6. Matrice de couverture MIR

| Construct | MIR | Note |
|---|---|---|
| lit | ✅ | i64 uniquement ; float/str à étendre |
| apply (binops, cmp) | ✅ | add/sub/mul/div + cmp_lt/eq |
| sym (load/store) | ✅ | |
| if / while / break | ✅ | blocks + branch + phi (tests mir.zig) |
| bind (fn user) | ✅ | test « user function definition and call » |
| lambda | ⚠️ | lowering/unlowering testés ; capture à vérifier |
| relation / data ctors | ❌ | aucun support |

Le « MIR ~40 % » du README est périmé dans les deux sens. Cette
matrice est la mesure réelle.

## 7. Jalons

- **M0** ✅ audit + ce document.
- **M1** geler le contrat : union `Instr` + invariants documentés.
- **M2** MIR→WAT puis binaire. **M2a ✅** émetteur texte
  (`src/backend/mir_wat.zig`) + 4 golden tests dans `zig build test`
  (dispatch trampoline, phis abattus, fn_defs, rejet explicite).
  M2b ✅ : oracle mir.execute vs wasmtime run — test_mir_wat.zig.
  **TCO (2026-10-01)** : meme transformation dans `mir_wat.zig`. `wasmtime run --invoke main` sur `count_down 10000000` retourne `10000000` **sans** le flag `-W max-wasm-stack=67108864`, qui n'est plus requis.
- **M3 ✅** QBE IL depuis MIR : `mir_qbe.zig` + `qbe_cmd.zig`.
  Migration QBE v1.2 (release officielle, miroir GitHub 2021
  abandonné). Commandes `compile-qbe` et `bench-qbe`. Fonctions
  utilisateur récursives compilables. fib(25) = 75025 en 1.15 ms
  (interprète 29 824 ms, ~26 000×).
  **TCO (2026-10-01, etendue 2026-10-02)** : les self-tail-calls sont transformes en boucle `jmp @b0`. La recursion mutuelle est traitee par fusion SCC au niveau MIR (`fuseTailSCCs`, `src/core/mir.zig`) : chaque SCC (2+ fonctions mutuellement recursives) devient une fonction `$scc_N` avec tag dispatch a N branches. `isEven 100000000 = 1` (2-cycle), `f 1000000 = 200` (3-cycle). **Non couvert** : trampolines generaux, SCC avec arites differentes (voir `docs/spec/_tco_mutual.md`).

  **Cross-compilation (2026-10-02)** : `compile-qbe <src> -o <out> [--target <name>]`. Sans `--target`, comportement natif (QBE + cc + binaire). Avec `--target`, QBE emet l'assembleur pour la cible et on s'arrete la (fichier `.s`). Cibles : `amd64_sysv`, `amd64_apple`, `arm64`, `arm64_apple`, `rv64`. Le binaire final pour cible etrangere necessite un cross-cc (non gere).
- **M4** flag Green/Fast + instrumentation énergie. Profiler
  étendu (RAPL energy, thermal_zone) ; reste à brancher sur un
  flag CLI `-Ogreen`/`-Ofast`.
- **M5** LLVM (décision dédiée requise, cf. vestige legacy/).

## 8. Coordination

`mir.zig`, `wasm.zig`, `kernel.zig` gelés par la session kernel (voir
PROMPT_CONTINUITE.md). Toute implémentation M2+ après coordination
explicite. Ce document est docs-only.

## 9. Dettes documentaires

README : « 39 tests unitaires » (réel : 175+), « MIR ~40 % »,
`zig build wasm` inexistant (chemin réel : `bash build.sh`).
STATUS.md : lignes TCO et kernel CIC à rafraîchir (d9d35ba, c620281).

### Note (2026-10-08)
Tous les backends (QBE, WASM) consomment désormais exclusivement le MIR généré depuis 'core.Expr.Store', rendant 'SurvivalTranspiler' (C) obsolète.
