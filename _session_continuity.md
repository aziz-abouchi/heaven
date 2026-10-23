# HEAVEN — Prompt de continuité (2026-10-20, après recon R1-R9)

## Rôle
Agent expert Zig/Heaven. Scripts shell/python copier-collables.
L'utilisateur exécute et colle les sorties. Adapte selon ce que tu vois.

## Méthodologie (héritée, toujours valide)
1. Blocs courts : shell < 20L, python < 40L. Heredoc `python3 - <<'PYPATCH'`
   préféré à `cat > file`.
2. Chaque bloc vérifiable : grep, wc -l, `echo "EXIT=${PIPESTATUS[0]}"`
   (jamais `$?` après pipe).
3. Backups `.bak` avant modif. `cp -n` pour idempotence.
4. Cutoff dur : si un fix échoue au 1er build, rollback + doc + pause.
   Pas de 3ᵉ tentative.
5. Baseline avant commit (si .zig touché) :
   - `zig build -Doptimize=ReleaseFast` = 0
   - `zig build test` = 0
   - `HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests` fails=0
   - wasm32-freestanding + wasm32-wasi = 0
6. `--run-test` (singulier) fork par fichier, capture le Total.
   `--run-tests tests` global, timeout 30s possible (baseline via per-file).

- **TOUJOURS infixe dans les .hvn ecrits** : `f x y == "p"`, `a + b`,
  `if p then a else b`, `let x = v in body`. **JAMAIS** S-Expr
  `(f x y)`, `(+ a b)`, `(let ...)`. Le "bug parser multi-ligne ~180b"
  etait en fait du S-Expr mal forme, pas un bug parser. Verifie 2026-10-20.

## Style Heaven (infixe obligatoire)
- `a + b` (pas `(+ a b)`), `if p then a else b`, `let x = v in body`.
- `f = 42` est une fonction, PAS une valeur. `f _ = 42` puis `f 0 == 42`.
- **Dans `test "nom":`, le parser cherche `==` à profondeur 0.** Tout
  `let ... in` doit être dans un helper HORS test.
- Escape `\xNN`, `\"` non supportés (workaround poke_byte).

- **Recursion dans argument d'operateur** : `(+ 1 (rec k (inner ...)))`
  crash silencieusement dans `--run-test` (pas de Total). Workaround
  obligatoire : `let nxt = (inner ...) in if ... else (+ 1 (rec k nxt))`.
  Decouvert session 2026-10-20 (test_ontology_derivation.hvn).
  Pattern proche du bug `011d934` selfrecursion.

- **QTT `let linear x = v in body` multi-token** : `v` multi-token
  (`(raw_alloc 16)`) casse (`ArityMismatch`). `body` est OK car
  accumule. Fix identifie : `expr_parser.zig:677` `qtt_val` 1 token
  au lieu d'accumulation. Session dediee parser.

- **25 fichiers auto-loadés au boot** : `src/main.zig:396-420`
  (bootstrap, kernel, logic, prelude, io) + `src/core/std_loader.zig`
  (20 fichiers `core/std/*` + `core/{stream,io_stream,http,bigint}.hvn`).
  TOUT est dispo sans `import` (Lens, Free, Array, HashMap, string helpers,
  BigInt...). `docs/PRIMER.md` documente le contrat complet. **Ne pas
  creer de doublon dans `stdlib/` — verifier d'abord dans `core/std/`**.
  Decouvert session 2026-10-20 apres 7 faux doublons en legacy.

- **`let x = v in <recursive-call>`** = `ExecutionFailed` silencieux
  (découvert session LSP). Split en helper : `f x = if cond then base
  else f_step x (arg)` puis `f_step x a = <expr + f a>`.
- **`s = "hello"`** = fonction 0-arg (pas valeur). `string_substring s`
  passe le SYMBOLE. Fix : `s _ = "hello"` + `(s 0)`.
- **`\"` dans strings** = parser rejette. Fix : `@char_string 34` + `+`.
- **`{` et `}` littéraux** dans strings cassent std_loader (le split
  par `\n` avale la suite). Fix : `@char_string 123` / `@char_string 125`.
- **`(lt a b)` en S-expr dans `if`** casse. Fix : `<` `>` infixe.
- **`> 0 - 1` dans `test "..."`** refuse (seul `==` accepté). Fix :
  helper `contains s pat = (find_str_from ...) >= 0`.

- **Commentaire `--` inline dans `else if`** = `ArityMismatch` silencieux
  (découvert session OS). `else if off == 1 then 1  -- comment` casse.
  Fix : commentaire sur ligne séparée (au-dessus) ou supprimé.
- **`and`/`or` infixe KO** : `a and b` = `UnknownSymbol`. `(and a b)`
  S-expr OK. Idem `or`. Ne pas utiliser en infixe.

## Pièges confirmés
- Regex multi-ligne casse les corps indentés → remove_def par blocs.
- Double import direct+transitif silencieusement KO (fossile #4) —
  workaround `b1adff3` (retire le chemin), vraie correction non-commitée
  (patch `import.zig` re-préfixe sous-imports).
- `engine_expr.zig:1052-1060` : `evalMagic` est fonction libre (`engine`, pas `self`).
- `heaven_expr.zig` = parser (fields `Heaven`), `engine_expr.zig` = magics
  (fields `Engine`). Les deux ont un `fn_arities`.

## État réel (vérifié R1-R9, 2026-10-20)

**Vert / fonctionnel** :
- HKT V1a : 2/2 (`test_hkt_v1a`)
- HKT V1b : 25/25 (step1 4/4, step2 11/11, step3 10/10) — dispatch livré
- Lens/optics : 12/12 (`stdlib/optics.hvn` canon, `core/std/lens.hvn` v0 fossile)
- Effects : commit `e445f5d` (facade .hvn + resume + tests)
- MPST : 10+3 runtime (`stdlib/mpst.hvn`)
- Fantasy Land : 13/13, Free monad : 6/6, MaybeT : 6/6

**Partiel / non branché** :
- QTT : `linear`/`erased`/`many` parsés, check parse `expr_parser.zig:742`
  **ne fire PAS sur `heaven run`**, `LinearChecker` (`types.zig:145`) mort
  sauf `hasErrors` appelé par `src/runtime/shell/commands.zig:917`.
  → Chantier Phase 2 RFC v2 : brancher, 1 session.
- `examples/vision/` : 14-16L/fichier, esquisse multi-OS (`linear`,
  `inline_qbe`, `module`, `arena`, `memory`). Parser accepte `linear`,
  sémantique absente. À rapatrier `stdlib/platform/`.

**Dette** :
- 3 arbres `.hvn` : `core/` (mort, 0 import tests), `site/repl/core/`
  (copie publiée 35/37 identiques, 2 divergents `bigint`, `http_server`),
  `stdlib/`+`lib/` (vrais arbres actifs, 12+7 imports).
- 10 `.bak` récursifs (voir `find . -name '*.bak'`).
- 57 fichiers `tests/scratch/`.
- `stdlib/` : 2 `.bak` (`dns.hvn.local.bak`, `string.hvn.d2.bak`).
- Pas de tests `.hvn` end-to-end QTT.
- Bug runner : `helper _ = ...` dans test → `Total 1/2` silencieux
  (1 passed + 1 failed invisible, sans message).

## Chantiers actifs (par priorité, après patch docs)

1. **QTT Phase 2** (1 session, `.zig`) : brancher `expr_parser.zig:742`
   sur `heaven run`, ajouter 4-6 tests `.hvn` explicites, décider si
   `types.zig` `LinearChecker` est mort ou à rebrancher.
2. **Fix runner `helper` dans test** (0.5 session) : `Total 1/2` sur
   fichier 1-test = bug scope, à tracer dans `test_runner.zig`.
3. **Plateforme `examples/vision/` → `stdlib/platform/`** (1-2 sessions,
   `.hvn` + FFI Zig) : HKT V1b débloque `class Allocator a`.
4. **Stratification `stdlib/`** (1 session, shell) : `data/`, `net/`,
   `core/`, `io/`, `platform/`. Après Phase 2/3 pour ne pas perturber.
5. **Fossile #4 vraie correction** : patch `import.zig` non-commité
   (re-préfixe sous-imports), baseline complet à faire, 4-5 blocs.

## Ordre de lecture au démarrage
1. `_stdlib_v2_plan.md` (97L, plan complet)
2. `docs/STATUS.md` (474L, journal)
3. `docs/STDLIB.md` (308L+, sections à jour)
4. Ce fichier

## Contraintes de communication
- Signaler tunnel > 3 blocs sur un diagnostic. Proposer rollback + doc.
- Ne pas prétendre faisable si session de conception. Dire « 2 sessions ».
- Demander la sortie après CHAQUE bloc, ne pas supposer.

## Session 2026-10-21 (suite -- découvertes majeures)

### Bug `let-in-if` = SEGV parser (pas let+recursion)
Probes discriminants (tous via `--eval-file`):
- P_A `if > 0 then let x = n+1 in x+1 else 0` -> SEGV (non recursif)
- P_E `if > 0 then 1 else let x = 2 in x` -> SEGV (else aussi)
- P_G `if > 0 then (let x = 1 in x) else 0` -> SEGV (parenthesifie)
- P_F hoisted helper dans if -> **OK** (contournement valide)
- P_C recursif sans let -> OK
- P_D let corps de fonction -> OK

**Regle** : JAMAIS de `let` dans `then` ni `else`. Helper hoiste obligatoire.
Le label historique "let+recursion" etait trompeur -- c'est `let-in-if`.

### SEGV runner accumulation
- `--run-test fichier` SEGV a ~23 statements.
- Chaque test isole passe via `--eval-file`.
- `splitTopLevelEq` (heaven_expr.zig:3690) est CORRECT, ne pas blamer.
- Cause : pas de reset arena/env entre `heaven.eval()` dans
  `src/runtime/test_runner.zig`. Fragmentation -> SEGV sur parse_file profond.
- Fix (session Zig dediee) : fork par test OU reset arena.
- `tests/test_parser.hvn.skip` documente ce blocage.

### read_stdin / write_stdout : jamais exerces E2E avant cette session
Deux panics Zig en serie :
1. `evalMagic:1688` `@intCast` sur read negatif quand `read_stdin 0`
   (raw_alloc 0 + raw_syscall read 0 -> -EFAULT -> cast negatif).
2. `F.parse_body ""` assert sur EOF (string vide).
`serve_once` traite 1 frame, crash au 2e (EOF).
`lib/mcp/server_loop.hvn` reste stub. Doc `_mcp_loop_wip.md`.

### MCP : seuls `TT.handle_tools_call` et `M.tool_call_body` accessibles
`TT.run_echo`, `TT.run_tool`, `TT.extract_text` -> UnboundVariable.
Tests par chemin public : `TT.handle_tools_call id body`.
`web_lookup` incompatible precalc+pick (I/O reseau x7 par call).
Doc `_mcp_tools_wip.md`.

### Pieges confirmes
- `a = MkTask 1 5` en top-level = fonction 0-arg. `(a 0)` = ArityMismatch.
  Utiliser inline `(MkTask 1 5)` ou helper `mk _ = (MkTask 1 5)`.
- `--run-test <dir>` = error.IsDir. CI doit iterer `tests/*.hvn`.
- `heaven parse <file>` est un stub tree-sitter (tous prints commentes).

### Livre cette session
- commit c1294e1 : skip test_parser.hvn (SEGV runner, doc complete)
- commit 7df7a01 : scheduler run_n (5/5) -- boucle via drop_id helper
- commit 0552fde : doc MCP web_lookup WIP
- commit fb2098d : kernel multi-taches (KernelQ, 6/6)

### Prochaines sessions (ordre)
1. **Zig dedie** : fix `let-in-if` parser SEGV + fix runner arena reset
   (les deux sont localises, ~30-50 lignes cumulees).
2. **Zig dedie** : fix `read_stdin 0` + `F.parse_body ""` (MCP loop E2E).
3. Apres Zig : dispatch direct `if m then M.foo` (debloque web_lookup,
   MCP loop propre, QTT runtime).
4. En .hvn pur en attendant : OS Phase 1B MPST instances (Disk/Net/Timer),
   `lib/os/ipc.hvn` etendu.

## Session 2026-10-21 (soir) -- build macOS debloque

### Fix platform aarch64_macos.zig
Le shim etait minimal (io_console stub, io stub, time/fs/net stubs inline)
-> manquait `target`, `getenv`, `Thread`, `parser_ts`, `debug`, `fs`,
`process`, `spawnProcess`, `profiler`, `net_sockets`, etc. Cascade.

Reecrit en repliquant x86_64_linux.zig (62 lignes), sauf :
- `profiler = @import("profiler_darwin.zig")`
- `readEnergyUJ` -> retourne 0 (RAPL Linux-only)

### Resultat
- `zig build` = 0 sur macOS aarch64.
- Baseline .hvn 9/10 verts sur macOS.
- `test_mcp_tools` fail sur macOS : `lib/time.hvn` = `raw_syscall 228`
  (Linux-only, clock_gettime). Chantier separe : `@time_now` portable
  en .zig + .hvn, puis re-test.

### Chantier separe (prochaine session)
- `lib/time.hvn` portable : magic `@time_now clockid` en Zig natif
  (std.posix.clock_gettime sur Darwin, raw_syscall 228 sur Linux).
- En attendant, `lib/time.hvn` documente comme Linux-only.

## Session 2026-10-23 (soir) -- FIX let-in-if LIVRE

### Cause racine confirmee (backtrace core dump)
`gdb -nx -batch ./zig-out/bin/heaven /tmp/core` puis `bt 20` :
`#13 expr.NativeParser.parsePostfix (self=0x0)` -- SEGV par stack
overflow (pas self null, gdb lit dans la guard page).

**Cause reelle** : `NativeParser` de `src/core/expr.zig` **n'avait
AUCUNE gestion de `let`**. `parsePrimary` case `.ident` ne gerait que
`if`, tout le reste tombait dans `dupe(t.text)`. `let x = v in body`
produisait un symbole brut `"let"` puis `parsePostfix` bouclait sur
`x`, `=`, `in`, `body` a l'infini -> stack overflow.

### Fix livre (commit 1672ce8)
Ajout `parseLetExpr` + case `.ident "let"` dans `parsePrimary`.
Desucrage `let x = v in body` -> `((lambda x body) v)`, evalue par
le moteur existant. 14 lignes de `.zig`, 0 changement eval.

### Probes validees
- A (let-in-then) : 5 OK
- E (let-in-else) : 2 OK
- G (let-in-then paren) : 1 OK
- F (helper hoiste) : 5 OK
- rec (let-in-if recursif) : 0 OK
- Baseline .hvn 14/14, `zig build test` 0 (404/407 preserve)

### Chantiers debloques par ce fix
1. `dispatch direct if m then M.foo` (supprime precalc+pick)
2. `web_lookup` 6e tool MCP (plus de x7 I/O reseau)
3. `MCP loop` multi-frame (parse_body EOF + read_stdin 0 restent,
   mais le dispatch direct contourne `precalc+pick`)
4. `QTT runtime` (`linear` enforced)
5. `KernelQ` dispatch polymorphe (plus besoin de helpers hoistes)

### Outillage : ATTENTION ulimit
`ulimit -s 512` (test stack overflow) **fixe la limite hard aussi**.
Impossible de remonter dans le meme terminal ni via `prlimit`.
**Fermer le terminal** et en ouvrir un neuf (limite revient a 8 MB).

### Lecon methodo
Un SEGV `timeout 124` sur `--eval-file` n'est pas forcement un hang :
peut etre un stack overflow qui met ~10s a atteindre la guard page.
`ulimit -s 64` discrimine : si instantane = stack overflow, si pareil
= boucle CPU pure. `gdb -nx` (sans init Python) + core dump est la
methode fiable.

## Session 2026-10-23 (nuit) -- HoTT path.hvn

lib/hott/path.hvn : MkPath witness start end, refl/sym/trans/ap/
transport/trans3/refl_eq. 14 tests verts. Facade rank-1.

Etat typechecker : DependentChecker et TypeEnv.infer sont STUBS.
elabDataDecl ignore tparams. lambda = GAP parser (contournement
id_f x = x). Roadmap 5-6 sessions dans docs/spec/_hott_roadmap.md.

Q1(a) + Q2(A) actees. Baseline 15/15 fichiers .hvn verts.

## Session 2026-10-24 -- emancipation E1.1

### Livre
- lib/parse/infix.hvn (E1.1) : + - * parens, 12 tests.
- lib/qtt/linear.hvn : facade QTT 0/1/w, 8 tests.
- lib/hott/path.hvn : facade Path rank-1, 14 tests.
- Grammar tree-sitter : path_constructor (HIT HoTT).
- lib/syscall : constantes litterales + write_str.
- docs/spec/_emancipation_roadmap.md : 10 phases E1-E10.

### Decision actee
Surface utilisateur = INFIXE uniquement. S-Expr = INTERNE.
Pipeline : .hvn infixe -> HP.lex -> AST S-Expr -> heaven_eval.
Ordre revise : E1 (parse_infix) -> E3 (--meta) -> E2 (C) -> E4..E10.
E3 avant E1 = impossible : --meta ne peut pas evaluer .hvn infixe
sans parseur infixe en .hvn.

### E1.2 (if/then/else) -- BLOQUE
Bisection 8 blocs. is_kw, mk_if, parse_if, pif_* marchent SEULS.
Mais cycle de definitions parse_atom -> parse_if -> parse_add ->
parse_mul -> parse_atom casse le loader .hvn (silence, exit 0).
3 strategies documentees dans _emancipation_roadmap.md.
Option A recommandee : if au niveau expression (parse_expr),
PAS au niveau atome. parse_atom ne connait pas if.

### Bugs Zig ouverts (session dediee)
- poke_int64/peek_int64 : poison 0xAAAA (mem adressable casse).
- wait4 : status pas ecrit (fork+exit OK, status KO).
- --eval-file vs --run-test mode-dependent (imports resolus differemment).
- F.parse_body "" assert EOF (MCP loop 2e frame).
- Runner arena reset (~23 statements, test_parser.hvn.skip).

### Baseline
17/17 fichiers .hvn verts. zig build test 404/407 (preserve).

### Prochaine session
1. E1.2 option A (if au niveau expr). 1-2 blocs si methode OK.
2. E1.3-E1.7 (let, lambda, application, comparaisons, data/import).
3. E2 (backend C en .hvn).
4. E3 (--meta).
5. Axe 1 QTT ensuite.


## Session 2026-10-24 (WE) -- primitives + nettoyage

### Livre
- lib/heaven_eval.hvn : +primitives == != > <= >= via table plate
  (prim_ops + in_list). prim_fin delegue a prim_cmp. Cascade de 10
  if remplacee, test_eval ne crashe plus a 134.
- tests/test_heaven_eval_prims.hvn : 16/16 (5 nouvelles + regressions).
- Nettoyage : 8 .bak supprimes, /tmp vide, 1 branche mergee supprimee.
  2 branches non mergees gardees (backup-wip-20260914, physical-telemetry).

### Bloque
parse_cmp dans infix.hvn : SEGV au chargement (meme famille que
le cycle E1.2 parse_atom/parse_if). Rollback, primitives prêtes.
Doc : docs/spec/_cascade_if_bug.md (nouveau).

### Commits
- ff3c591 feat(heaven_eval): primitives etendues (refactor plat)
- 1644b99 test(heaven_eval): 16/16 tests
- fc75d94 docs(spec): cascade if > 5-6 niveaux

### Baseline
18/18 fichiers .hvn verts. zig build test 404/407 preserve.
