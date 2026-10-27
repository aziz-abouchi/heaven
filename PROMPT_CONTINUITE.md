# ÉTAT AU 2026-10-27 SOIR — fin de session E4

## Acquis solides (commits)
- `4a9bc11` E4/3.2a : serveur HTTP Heaven natif (--http-serve N, curl
  /repl.html 200 38261 o, /heaven.wasm 200 584755 o application/wasm).
  Loader multi-clauses via splitStatements (14 statements). 5 @net_accept
  successifs sans crash. REQUIS : HEAVEN_NO_LEAK_CHECK=1 en Debug
  (heap corruption preexistante, cf. _http_debug_crash.md).
- `a7d82ec` E4/3.3-pre : @arm_preempt multi-mode (fuel/timer/both) 4/4.
  Fix racine isMagicSymbol (@spawn, @broadcast, @runtime_stats, @sleep_ms
  etaient absents -> jamais dispatches).
- `88eb097` E4/3.4a : audit syntaxe (docs/spec/_syntax_audit.md).
  4 bugs documentes + inventaire S-expr (98 lignes).
- `0471a6b` E4/3.4b : fix parseLetExpr (4/8 tests rouges -> verts).

## Dettes identifiees (ordre de traitement)
1. **3.4c** : migration S-expr -> infixe (chacun test_suite garde-fou).
   Ordre : array -> memory/free/string -> bigint -> heaven_parse
   -> json/parse -> test_suite EN DERNIER.
   Regle : operateurs purs seulement. `if` S-expr reporte.
2. **3.4b-bis** : `let` bind thunk non force quand RHS = magic
   (@spawn). Preuve : via_let_parens passe, spawn_* echoue.
3. **3.4b-ter** : corps `let` non parenthese + RHS application
   echoue a 0.13ms (parse, pas eval).
4. **3.3a** : http_server.hvn reecrit en scheduler/effects/acteurs
   (apres 3.4c).
5. **Phase B** : signaux via @signalfd (Linux) + kernel32 (Windows).
   Syscalls via Heaven, PAS de std.posix dans main.
6. **Phase 6** : multi-plateformes (macOS, iOS, Android, WASI, WEB).
   Tester WASI/WEB/Linux/macOS/Windows/iOS/Android via build.sh matrix.

## Bugs langage connus
- Syntaxe lambda : SEULE forme valide = `\x. body`.
  `lambda x : body`, `lambda x -> body` buggees.
  `(fn x = x)` parse comme `((= (fn x) x)` (= infixe casse fn).
- `((\x. x) 5) > 0` echoue silencieusement (0.1ms, pas d'eval).
- `@spawn` : task creee, body_fn tag .lambda, id croissant — MAIS
  retour non lisible via let + operateur (voir dette 2).

## Environnement
- Machine devilHope, zig 0.15.2, GOP gpa (pas page_allocator).
- Stash : `stash@{0}: f4-wip` preexistant, NE PAS TOUCHER.
- `bash build.sh` OK (tests_zig 406/407, 1 skip preexistant).
- `test_suite.hvn` : 98/98 stable.

## Prochaine action immediate
3.4c / etape 1 : `core/std/array.hvn`. 10 occurrences S-expr,
7 operateurs purs convertibles. NE PAS toucher aux `if` S-expr.
Diff + rebuild + test_suite. Si 98/98 -> commit par fichier.

---

# HEAVEN — Prompt de continuité (2026-10-19, après E3 Vessel + H1/H2 clos)

## Rôle de l'agent

Tu es un agent expert Zig/Heaven. Tu fournis des scripts shell/python
copier-collables (JAMAIS d'édition manuelle). L'utilisateur exécute et
colle les sorties. Tu adaptes selon ce que tu vois.

## Méthodologie obligatoire

1. **Blocs courts** : shell < 25 lignes, python < 40 lignes. Heredoc
   `python3 - <<'PYPATCH'` préféré à `cat > file <<'EOF'`. Si le
   navigateur corrompt un heredoc (backticks, fences markdown), faire
   des appends Python par petits lots (5-10 lignes chacun) — c'est
   arrivé 3 fois dans la session 2026-10-19.
2. **Chaque bloc vérifiable** : `grep`, `wc -l`, exit code explicite
   (`echo "EXIT=${PIPESTATUS[0]}"`, JAMAIS `$?` après un pipe).
3. **Backups `.bak`** avant toute modif (`cp -n`). Ils sont gitignored.
   `rm` en fin de session (les 7 .bak de E3b ont pollué `find src`).
4. **Marqueurs `HEAVEN:XXX`** dans le code.
5. **Grep -A5 après re.sub multi-ligne** (fragments orphelins).
6. **Cutoff dur** : si un fix échoue au 1er build, rollback + doc +
   pause. Pas de 3ᵉ tentative. Signaler AVANT de coder si le chantier
   n'est pas faisable en 2-3 blocs.

7. **Baseline avant commit** (ordre, tous doivent être 0) :
   - `zig build` = 0 (Debug, tests Zig unitaires) **si .zig touché**
   - `zig build test` = 0 (Debug) **si .zig touché**
   - `zig build -Doptimize=ReleaseFast` = 0
   - `HEAVEN_NO_LEAK_CHECK=1 ./zig-out/bin/heaven --run-tests tests`
     = 0 fail — **ReleaseFast uniquement** (cf. D-CI1). En Debug,
     3 fichiers crashent (test_parser, test_hashmap, test_bigint_d20,
     SIGSEGV, `_runner_crashes_2026-10.md`). **Toujours**.
   - `zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
     = 0 **si platform/ ou expr.zig ou heaven_expr.zig touché**
   - `zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall` = 0 (idem)
   - **Changement `.hvn` pur** : seul `--run-tests tests` (ReleaseFast)
     est requis (pas de `zig build`).

## Usage du binaire (2026-10-20)

| Commande | Effet |
|---|---|
| `bash go.sh` (TTY interactif) | REPL + serveur HTTP + tests |
| `HEAVEN_NO_REPL=1 ./zig-out/bin/heaven 8080 &` | serveur-only, pas de SIGTTOU |
| `printf 'expr\n' \| ./zig-out/bin/heaven` | mode serveur (pipe, pas de REPL) |

- `HEAVEN_NO_LEAK_CHECK=1` recommande : les threads demons tiennent
  des allocations au shutdown, `gpa.deinit` crash sinon. `go.sh`
  le definit par defaut.
- Le REPL interactif necessite un vrai TTY foreground. En pipe ou
  arriere-plan, `isatty(stdin)=false` ou `HEAVEN_NO_REPL=1` ->
  mode serveur-only.

## Méthodes critiques

1. Toujours vérifier par lecture + bisect avant de patcher un bug supposé.
2. Un fix = un commit = un test qui passe auparavant.
3. Ne jamais utiliser `git add -A` (plusieurs sessions parallèles tournent).
4. Helpers nommés pour éviter les `if` multi-lignes dans le parser infixe.
5. Régénérer doc : `python3 scripts/docgen.py && python3 scripts/status_gen.py` avant push.
6. `HEAVEN_NO_LEAK_CHECK=1` par défaut (contournement DebugAllocator).
7. `zig build -Doptimize=ReleaseFast` par défaut (D20).

## Style Heaven (infixe obligatoire)

- `a + b` (pas `(+ a b)`), `if p then a else b`, `let x = v in body`
  (hors test), `f x y` multi-arg.
- S-expr réservé : magics 0-arg (`(@budget_left)`), tuples `(a, b)`,
  patterns `f (cons x xs) = ...`.
- **0-pattern def (`f = body`) est une fonction, PAS une valeur** :
  `f = 42` puis `f == 42` → faux. Toujours `f _ = 42` puis `f 0 == 42`.
  **Piège récidivant.**
- **Dans `test "nom":`, le parser cherche `==` à profondeur 0.** Tout
  `let ... in` doit être dans un helper HORS test :
  `helper _ = let x = v in body` / `test "n": (helper 0) == val`.
- **Escape `\xNN` et `\"` NON supportés.** `\"` reste littéral (2
  octets : backslash + quote). `\n`, `\r`, `\t` OK. Workaround string
  avec quotes : `poke_byte` + `string_of_bytes` (cf. `mk_obj` dans
  `tests/test_json_v1.hvn`).

## Pièges appris (ne pas répéter)

- **Regex multi-ligne** : casse les corps indentés. Toujours
  `remove_def` par blocs (première ligne + toutes les lignes
  indentées suivantes), jamais `re.sub` seul.
- **Double import** (`import "X.hvn"` direct + transitif via Y) fait
  échouer silencieusement les comparaisons de symboles. Workaround :
  tests séparés, pas d'import double.
- **Fossile #4** (import + patterns qualifiés) : jamais reproduit
  isolément. Suspect mais non tracé. `_vfs_import_gap.md` traite du
  REPL web, PAS du Sym qualifié. Voir `_json_object_bug.md` (H1/H2
  clos 2026-10-19 : ni pattern, ni import, ni `==` — c'était `\"`
  littéral dans les strings de test).
- **Runner `--run-tests`** fork un subprocess par fichier
  (`test_runner.zig:318`). Un crash dans un fichier n'affecte pas les
  autres. Un `TestFailed` sans `Total` = crash silencieux au parse.
  **`--run-test` (singulier)** existe pour un fichier unique.
- **`--run-tests` refuse un fichier** (`openDir` → `NotDir`), il faut
  un répertoire. Pour isoler un fichier : `--run-test path.hvn`.
- **`matrix.zig`/`autofab.zig`/`bridge.zig`** sont legacy (D9→HTTP).
  Ne pas y toucher sauf E4/E5 dédiés. `bridge.zig` : E3a/E3b/E3c
  livrés, reste E4 (main.zig → http_serve) + E5 (matrix → legacy).
- **`engine_expr.zig:1052-1060`** : `evalMagic` est fonction libre,
  utiliser `engine` (pas `self`).
- **`heaven_expr.zig` vs `engine_expr.zig`** : parser dans le premier
  (fields `Heaven`), magics dans le second (fields `Engine`). Les deux
  ont un `fn_arities`.
- **`syncMatrixWithFile`** (`main.zig:101`) est un stub no-op
  (`return;`). Ne pas le ressusciter. `didSave` passe par
  `Heaven.eval` depuis E3b.

## État du dépôt (à vérifier au démarrage)

```
cd ~/Desktop/Dev/langage/boot
git log --oneline -8
git status --short   # doit être propre sauf README.md (docgen) et *.bak
```

**Derniers commits connus (2026-10-20 matin)** :
- `0ece80f` E5 — bridge.zig sans matrix/autofab
- `1ba6aa4` HKT V1b pas 2 — @dispatch_instance
- `62155ce` HKT V1b pas 1 — @resolve_instance
- `57d306b` doc cutoff B3 (3e bug : pattern `_` + heaven run)
- `66f0b32` fix(heaven.eval): let-chain top-level via normalizeLetChain
- `da2f5b3` doc let-chain bug + tuto workaround fn/seq
- `584e5e2` E3c — dedup heaven_expr, retire main_mod
- `f2ee36c` H1/H2 clos — artefacts `\"`, pas bug parser
- `00e1475` E3b — didSave via Heaven.eval
- `0bdc6e9` E3a — serveTelemetry via telemetry_store
- `e65dc66` E1 — telemetry_store.zig

## Ce qui a été livré (session 2026-10-19)

**HTTP fullstack E3 (Vessel)** :
- E3a : `serveTelemetry → telemetry_store.render`. `render` prend
  `peer_ports: []const u16`, émet Bob puis les peers puis les nodes
  du Store (limite 500). `WebBridge.store: *expr.Store` plombé
  jusqu'au constructeur `bridge.zig:453`.
- E3b : `didSave` réécrit — lit le fichier, `splitStatements`, boucle
  `Heaven.eval` par statement, log stats `Heaven.getStore()`. Le stub
  `syncMatrixWithFile` n'est plus appelé. `WebBridge.heaven: *Heaven`
  (remplace `.store`). `Heaven.getStore()` pub, `splitStatements` pub
  (`test_runner.zig:36`).
- E3c : dédup `heaven_expr`/`heaven_expr_mod` dans `main.zig`, retire
  `main_mod` orphelin de `bridge.zig`.

**JSON objects (H1/H2 clos)** :
- Discriminants `test_disc2/3a/3b/5` : pattern 2-arg OK, import
  qualifié OK, parser OK, lookup OK. Le "bug" venait de `\"`
  littéral dans les strings de test, pas du parser.
- `_json_object_bug.md` amendé (H1 réfuté, H2 réfuté).
- Tests objects réels ajoutés dans `test_json_v1.hvn` via `mk_obj`
  (`poke_byte` + `string_of_bytes`). Total 12/12.

**Runner / CI** :
- 3 crashes `--run-tests` identifiés Debug-only (`test_parser`,
  `test_hashmap`, `test_bigint_d20`, SIGSEGV). ReleaseFast = 0 fail.
  Tracés dans `_runner_crashes_2026-10.md`. Priorité basse.

**Docs mises à jour** :
- `_http_fullstack_plan.md` (état E1-E5), `STDLIB.md` (json V1),
  `ROADMAP.md` (D9 statut), `CHANGELOG.md` (entrée 2026-10-19),
  `DECISIONS.md` (D-HTTP1, D-HTTP2, D-CI1), `status.json` (Progrès,
  Top priorités, journal 2026-10-19).

## Session 2026-10-20 (matin) — livré

- REPL web repare (VFS, cache-buster, site-url).
- `http_server.hvn` v1 : routing infixe, 4 routes statiques 200 OK.
- Fantasy Land 10 classes (McKenna) 13/13 en `.hvn` pur.
- Optics Lens/Prism/Iso (Kmett) 12/12.
- Free monad (Lonsdorf) 6/6, MaybeT (Wilson) 6/6.
- Closure capture fix `bound_syms` (8/8 cas courants, residuel trace).
- `parsePostfix .str` resolu, `string_ends_with` Bool.

## 2026-10-20 (suite) — ontology + closures refutees

- `stdlib/ontology.hvn` : RDF/KB en `.hvn` pur, 14/14 tests.
  `kb_query`, `kb_count`, `kb_has`, `filter_subj`, `filter_pred`.
  Mots reserves prefixes (`query`, `count` collisionnent avec kanren).
- `examples/ontology/socrates.hvn` : 10 triples Socrate -> Platon ->
  Aristote -> Alexandre, 3 queries.
- Book ch. 11 §7 "En .hvn pur", B-erreurs "Mots reserves".
- Closure §2 (`mk_ds`) refute : test malforme, pas un bug runtime.
  `_closure_capture_bug.md` clos.

## 2026-10-20 (soir) -- TLS, DNS, open data, effects v0

**TLS OpenSSL FFI** :
- `src/platform/tls.zig` : SSL_CTX_new/SSL_new/SSL_set_fd/SSL_connect/
  SSL_read/SSL_write/SSL_shutdown. SNI.
- `src/platform/tls_stub.zig` (wasm, error.Unsupported).
- 4 magics : `@tls_connect fd host`, `@tls_write h data`,
  `@tls_read h` (buffer dynamique 16MB), `@tls_close h`.
- Test live : `wikidata_live.hvn` -> `HTTP/1.1 200 OK`.

**DNS parametre** :
- `dns_qname(host)` generique, `dns_resolve_a_com(host, server)`.
- 6/6 tests offline. Note : 8.8.8.8 bloque par la box, utiliser
  192.168.1.1 ou 10.100.92.20.

**Stdlib** :
- `stdlib/effects.hvn` (resume alias, 5/5).
- `stdlib/ontology.hvn` (14/14 + Socrate).
- `stdlib/net/urlencode.hvn` (9/9).
- `@char_string`, `@store_*` (5 magics).

**Pieges connus** :
- Magics non reexportes par `import "X" as E` (B-erreurs).
- Fossile #4 : import transitif qualifie (self-contained workaround).

**Baseline** : Debug=0, TEST=0, RF=0, wasm x2=0.
`test_bigint_d20` isole KO (pre-existant, memoire 175 Mo).

## Chantiers ouverts (etat 2026-10-20 matin)

**B3 (let-chain) — 3 bugs séparés, cutoff après 2 tentatives.**
1. Let-chain top-level `heaven run` : **FIXÉ** (`66f0b32`,
   `normalizeLetChain`).
2. Let-chain helper `f _ = (let ... in let ... in body)` : **KO**,
   `parseBodySmart`/`convertLetIn` non couvert, rollback.
3. Pattern `_` + `heaven run` : `helper _ = 42` + `(helper 0)` ->
   `ArityMismatch`. **Découvert en fin de session**, probablement
   `splitStatements`/`runEvalFile` qui perd le lien def -> sym_arity.
   **Bloque E4b.**
Session fraîche : discriminant `helper _ = 42` vs `helper x = 42`
vs `helper 0 = 42`, puis `heaven run` vs `--run-test` sur même
fichier. Voir `docs/spec/_let_chain_bug.md`.

**E4b (http_server.hvn) — bloqué par B3 #3.** Les magics `@net_*`
existent (13, câblés), `@net_listen` + `@net_accept` marchent en
isolation. Dès que B3 #3 est fixé, E4b = réécrire `http_server.hvn`
en top-level (pas helper), boucle accept, routing `/telemetry`.

**E5-bis (matrix → legacy)** — `main.zig` porte encore
`matrix_lib`/`autofab_lib` (`Matrix.init`, `bob_loop`,
`syncMatrixWithFile` stub). Extraction de `bob_loop` en
`src/runtime/` = 1 session.

**effects-consolidation** (1-2 sessions) — `handle_rec`/`resume`
public, `stdlib/effects.hvn` façade, composition. Voir
`_handle_rec_status.md`.

**HKT V1b pas 3 (optionnel)** — dispatch sur sym `List` sans
quotes (accès au nom d'un nœud `.sym`). 1 bloc. Voir
`_hkt_v1b_plan.md`.

**quotients-expose** (2-3 sessions) — kernel prêt (quot/class/lift,
ι-réduction, PI réactivée), pont `kernel_bridge` manquant
(`elabQuot`/`elabClass`/`elabLift`). Voir
`_quotients_expose_plan.md`.

**Debug-triage runner** — 3 crashes Debug-only (`test_parser`,
`test_hashmap`, `test_bigint_d20`), ReleaseFast = 0 fail. Priorité
basse. Voir `_runner_crashes_2026-10.md`.

## Ordre de priorité pour la suite

1. **_closure_capture_bug.md §2** (1 session) -- ctor pattern 2-arg
   + ctor body SIGSEGV (`mk_ds`). Debloque Fantasy Land complet,
   Classy Optics, stdlib/profunctor.hvn entier.
2. **effects-consolidation** (2-3 sessions) -- `resume` public,
   `stdlib/effects.hvn` facade, semantique `handle_rec` stable.
   Debloque MPST-V2, A-3b-3, book ch. 25 §3.
3. **scheduler preemptif** (2-3 sessions) -- budget, `.preempted`,
   A3A-PREEMPT consolides. Debloque actors Phase 3.
4. **Actors Erlang + green threads** (11-14 sessions, voir
   `_actors_green_threads_plan.md`). Phase 1 = 2 sessions minimum.
5. **HKT rank-2 verifie** (`forall`, kind polymorphism) 5-7 sessions.
   Voir `_hkt_rank2_plan.md`. Debloque profunctor encoding complet.
6. **Livre Pony + preuves formelles** (10+ sessions). Aucune session
   dediee pour l'instant.
7. **E4-final** (2-3 sessions) -- bascule `main.zig` -> `heaven.eval`,
   suppression Vessel Zig. Bloque sur `@telemetry_json` UB.

**Hors-scope court terme** : Cubical (multi-années,
`_hott_cubical_plan.md`), DHCP (dépriorisé, SCTP/RTP/WebRTC avant),
stubs macOS/Windows (SDK requis), Debug-triage runner (priorité basse,
ReleaseFast = 0 fail).

## Contraintes de communication

- Signaler à l'utilisateur quand on entre en tunnel (> 3 blocs sur un
  diagnostic). Proposer rollback + doc + pause.
- Ne pas prétendre qu'un chantier est faisable si c'est une session
  de conception. Dire « 2 sessions », pas « un bloc ». E4 est dans ce
  cas : le plan disait 30 min, c'est 1-2 sessions.
- Demander la sortie après CHAQUE bloc, ne pas supposer.
- Pas de « bon week-end » : l'utilisateur conduit cette session quand
  il veut.
- Le navigateur corrompt parfois les heredocs Python (backticks,
  fences). Si `python3 - <<'PYPATCH'` échoue avec `SyntaxError`,
  vérifier que la dernière ligne du heredoc n'a pas de `""` ou de
  fragment collé — c'est arrivé 3 fois le 2026-10-19.

## Régénération docs (source de vérité)

- `docs/status.json` → `docs/STATUS.md` via `scripts/status_gen.py`
- `README.md` via `scripts/docgen.py` (lit les marqueurs
  `<!-- DOCGEN:xxx -->` dans le repo)
- `go.sh` et `build.sh` appellent les deux (non bloquant).
- **Ne jamais éditer `STATUS.md` ou `README.md` à la main.** Patcher
  `status.json` et relancer `python3 scripts/status_gen.py &&
  python3 scripts/docgen.py`.

**Alternative STATUS.md-first** (petit patch) : éditer `STATUS.md`,
puis `python3 scripts/status_import.py` (met à jour `status.json`),
puis commit les deux. **Risque** : une section non importée est perdue
au prochain `status_gen.py` (qui réécrit `STATUS.md` entier depuis le
json). La voie `status.json`-first (2026-10-19) est plus sûre et
prouvée.

Le CI échoue si un chiffre est périmé (`--check` sur `docgen.py`).
`PROMPT_CONTINUITE.md`, `docs/DECISIONS.md`, `docs/ROADMAP.md`,
`docs/spec/*.md` sont **manuels**.

## Fichiers de référence

- `docs/DECISIONS.md` — ADR (D10 à D21, D-SH1..3, D-HTTP1/2, D-CI1)
- `docs/spec/_syntax_gaps.md` — limites parser infixe + quirks
- `docs/spec/_style_infix.md` — style Heaven (infixe, 0-pattern def)
- `docs/STATUS.md` — généré, état des features
- `docs/STDLIB.md` — modules stdlib
- `docs/spec/_http_fullstack_plan.md` — D9 statut E1-E5
- `docs/spec/_hkt_v1b_plan.md` — V1b (2 sessions)
- `docs/spec/_mpst_v2_plan.md` — MPST-V2
- `docs/spec/_metacircularite_chantier.md` — manques #2-#4
- `_runner_crashes_2026-10.md` (racine) — 3 crashes Debug-only
- `docs/book/src/14-concurrency.md` — scheduler coopératif
- `core/std/array.hvn`, `core/std/string.hvn` — Jalon 2
- `src/syntax/lower.zig` — pont Tree-sitter → Expr.Store (D21)
- `tests/test_array.hvn`, `tests/test_string.hvn`, `tests/test_scheduler.hvn`,
  `tests/test_effects_rec.hvn`

---

Colle ce prompt au début de la prochaine session.

## Session 2026-10-26 close (préemption + selfparse)

### Acquis
- Préemption WASI validée (`SuspendRequested` sous wasmtime).
- `wasi_main.zig` : `--eval-file <path>`, `--fuel <n>`.
- `test_selfparse.hvn` : 3/3 actifs (B-v1 documenté).
- Abort-relaunch (A-3a) validé + `test_abort_relaunch.hvn`.
- `@disarm_preempt` ajouté.

### État CI (à vérifier avant de pousser)
- `core/test_suite.hvn` : `proto2_run_drains` et
  `proto2_two_procs_run` échouent (pré-existant, non introduit).
- Le reste est vert : scheduler (3+12+3+4+11), docgen (91 files,
  131 tests Heaven, 406 tests Zig).

### Priorités suggérées pour la prochaine session
1. **Vérifier le CI** : les deux échecs proto2 sont-ils tolérés
   (skip explicite) ou faut-il les corriger ? Décision à prendre.
2. **A-3b** : reprise exacte (gros chantier, `_capture_eval.md`).
3. **Unification acteurs ↔ scheduler** (1-2 sessions).
4. **B-v1** : patterns imbriqués dans `heaven_parse.hvn`.


## Backlog session 2026-10-27

### Priorité 1 (cette session)
- CI `proto2_run_drains` et `proto2_two_procs_run` : clarifier
  (corriger `run` ou `-- SKIPPED` explicite).

### Backlog outils test qualité (noté 2026-10-27)
- **Quickchecker** : property-based testing (lois des algèbres,
  round-trip parser, invariants Store).
- **Smocker** : mock des effets (IO, réseau, acteurs) pour
  débloquer les tests de `http_get`/`serve`/proto1/proto2.
- **Fuzzer** : entrées aléatoires pour trouver les panics du
  parser/évaluateur.
- Ordre suggéré : smocker → quickchecker → fuzzer.
- Détail dans `docs/ROADMAP.md` section « Outils de test qualité ».


## proto2 corrigé (2026-10-27)

Priorité 1 de la session précédente **résolue** : `proto2_run_drains`
et `proto2_two_procs_run` passent (`test_suite.hvn` 98/98).
Fix : `run()` doit évaluer le body du handler avec `new_env`
(state/msg), pas `engine.env` (global). Commit `8c64a31`.

### Priorités suivantes
1. **Smocker** (backlog noté 2026-10-27) — débloque les tests
   `http_get`/`serve`/acteurs sans réseau.
2. **Quickchecker** — property-based testing sur les lois des
   algèbres (`tests/test_laws.hvn`), round-trip parser.
3. **Fuzzer** — entrées aléatoires pour trouver les panics du
   parser/évaluateur.
4. **A-3b** (reprise exacte) — multi-sessions, `_capture_eval.md`.
5. **B-v1** — patterns imbriqués dans `heaven_parse.hvn`.

