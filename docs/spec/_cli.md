# Heaven — CLI reference

Version courante : `heaven --help` (v0.1.0).
Binaire : `./zig-out/bin/heaven` (jamais dans le PATH).

## Frontend

- `heaven parse <file.hvn>` — parse et affiche l'AST (via tree-sitter).
- `heaven check <file.hvn>` — type-check. **Exit 1 si diagnostic, 0 sinon.**
  - Détecte les erreurs de syntaxe (nœuds `ERROR` tree-sitter).
  - Détecte les erreurs d'arité (`add 1` quand `add` attend 2 args).
  - Ne détecte **pas** les erreurs de type au-delà de l'arité (Typer minimal).
- `heaven fmt <file.hvn>` — formate la source.
- `heaven doc <file.hvn>` — génère la documentation.
- `heaven transpile [--to c|heaven|latex] <file>` — transpile.

## Execution

- `heaven run <file.hvn>` — compile et exécute.
- `heaven test <file.hvn>` — exécute les blocs `test "..."`.
- `heaven repl` — REPL interactif.

## Backends

- `heaven compile <file.hvn>` — génère du code C (`output.c`).
- `heaven compile-qbe <src.hvn> -o <bin> [--target <name>]` — natif via QBE.
  - Cibles : `amd64_sysv`, `amd64_apple`, `arm64`, `arm64_apple`, `rv64`.
- `heaven compile-wasm <src.hvn> -o <out.wat>` — WebAssembly (format WAT).

## Benchmarks

- `heaven bench-interp <file.hvn>` — timings interpréteur.
- `heaven bench-qbe <file.hvn>` — timings QBE (natif).
- `heaven bench-wasm <file.hvn>` — timings WASM.

## Tools

- `heaven lsp` — démarre le LSP server (stdio).
- `heaven mcp` — démarre le MCP server.
- `heaven --completions` — shell completions.
- `heaven help` — affiche l'aide.

## Internal (usage interne / CI)

- `heaven --run-test <file.hvn>` — exécute un seul fichier de tests.
  Retourne `Total: n / m` et un exit code.
- `heaven --run-tests <dir>` — exécute tous les `.hvn` d'un dossier.

## Limitations connues (2026-11-05)

- **`heaven check` ne supporte PAS `test "name":`** — la grammar tree-sitter
  n'émet pas de nœud valide pour les blocs test top-level, donc 142/148
  `tests/*.hvn` sont flaggés « syntax error » à tort. **Ne pas utiliser
  `heaven check` sur un fichier de tests.** Chantier : grammar à étendre.
- `heaven check` : détecte **syntaxe + arité**, pas les erreurs de type au-delà.
  Le Typer (`src/compiler/typer.zig`) est minimal — vérifie l'arité des appels
  via `fn_arity`, mais pas l'unification complète.
- `heaven check` : ignore les `MISSING ;` de tree-sitter (artefacts grammar
  cosmétiques). Seuls les nœuds `ERROR` réels sont signalés.
- `heaven run` / `heaven test` : les top-level binds `xyz = 3` sont évalués
  correctement (fix 2026-11-05). Les workarounds `f _ = ...` documentés
  antérieurement ne sont plus nécessaires.
- Edge case curry : `(((f a) b) c)` (double partielle) échoue encore.
  Voir `_runtime_gaps.md` §4.

## État `heaven check` (P1c bouclé 2026-11-05)

CI-verrouillé via `check_all.sh §7b` + `tests/hvn-check/` :
- `clean.hvn` → exit 0, silencieux
- `arity.hvn` → exit 1, `arity mismatch: 'add' attend 2 argument(s), reçu 1`
- `syntax-error.hvn` → exit 1, `syntax error in source`
- `thunks.hvn` → 7/7 (non-régression)

## QTT (quantitative) — enforced au parse (2026-11-06)
- let linear/erased/many : check au parse (expr_parser.zig:774).
- Tests : tests/qtt/let_quantities_{ok,viol}.hvn (7/7 conformes).
- Limitation : message brut (error.LinearViolation), pas pédagogique.

## IO — read_file (2026-11-06)
- perform "ReadFile" path → string (marche, 1 Mo max).
- perform "WriteFile" (path, content) → unit.
- perform "ReadLine" → string.
- read_file manuel (raw_alloc+io_read) cassé : utiliser perform.
