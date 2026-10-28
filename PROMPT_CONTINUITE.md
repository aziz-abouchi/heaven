# ÉTAT AU 2026-10-28 NUIT — Phase 7a, Hab W1b, 3 plateformes

## Phase 7a validée (commit fda410b)

- collectTailSpine étendu : if/seq/block/force (5000 iters OK)
- **@loop_until retiré** de server_loop (récursion TCO native)
- HTTP 500 req natif, sans @loop_until
- loadtest 100/500/1000 OK (avant : max 50)
- @loop_until dead code retiré (commit suivant)

## Phase 7b (dettes, prochaine session)

1. **let + self-call → SIGSEGV ~500**
   Handler let casse la propagation TCO_BOUNCE (cause non isolée :
   markArgDone, depth, ou interaction env.delete).
   Contournement actuel : self-call direct via (force ...) ou seq.
   Fichier : engine_expr.zig, fonction evalMagic, branche "let".

2. **loadtest 10000 → SIGSEGV l.1048 (UAF)**
   Stack : engine_expr.zig:1048, `for (args, 0..) |a_, i_|`
   `args` est un slice sur store.pool.items (ou nodes). Si evaluate
   réalloue le pool pendant la boucle, args.ptr devient dangling.
   À 1000 iters pas de realloc, à 10000 oui.
   Fix probable : snapshot args (comme args_snap dans evalFunction),
   ~5 lignes.

## État session (12+ commits poussés)

- HTTP natif 3 plateformes (Linux/macOS/Windows, 500 req)
- Hab W1b navigateur : bouton 0→18 (MVU Heaven pur, wasm)
- 5 outils test Heaven : mocker (4), smocker (6), quickcheck (6),
  fuzzer (4), loadtest (4). 43 tests.
- Livre : ch.13 @loop_until+TCO, ch.23 5 outils, ch.25 3 plateformes,
  ch.27 Hab. SUMMARY.md à jour.
- test_suite 98/98 partout.

## Environnement

HEAD : fda410b (+ cleanup à venir). origin/main à jour.
PROMPT_CONTINUITE a 3 headers empilés (nettoyer au prochain commit).

## Prochaines étapes (ordre suggéré)

1. Phase 7b UAF (loadtest 10000, 5 lignes) — rapide, satisfaisant.
2. Phase 7b let (complexe, markArgDone ?).
3. 3.4b-ter : if cond then a else b multi-ligne (parser).
4. W1c Hab : serialize_tree, todo.hvn, test headless.

---

# ÉTAT AU 2026-10-28 SOIR — Hab W1b VALIDÉ

## Milestone : Hab tourne dans un vrai navigateur

`heaven --http-serve 18080` + http://127.0.0.1:18080/hab/runtime/index.html
→ bouton 0 qui s'incrémente au clic (vu à 18).

Console : [hab] prelude: 21 defs ok, 0 failed
          [hab] mounted counter at #app

## Commits Hab (5)

`3148908` W1b-fix3 : heavenEvalRaw + retrait std.debug.print
  - Sans ce commit, wasm ne builde pas (std.Thread/std.posix
    via les 2 std.debug.print de diagnostic).

`717aa95` W1b-fix2 : data Pair + data List au prelude
  - Sans les data constructors, pair/cons/nil = UnknownSymbol
    (core/std/pair.hvn et list.hvn non importables sur wasm
    freestanding, pas de FS).

`3ff3f36` W1b : runtime navigateur (hab_runtime.js +
  index.html) + fix strip_query HTTP (cache-buster ?t=).
  Prelude inline 19 defs, mount(counter, '#app').

`72cbdb0` W1d : 5 outils test Heaven pur — mocker (4),
  smocker v2 (6, vrai spy avec record/verify/seq),
  fuzzer (4, trajectoires via Q.check), loadtest (4, charge
  in-process, max 50 iters), quickcheck (6). 43 tests verts.

`103e0d2` W1a : MVU core (mk_component, apply_one, apply_msgs,
  tree) + counter + 24 tests (mocker, quickcheck, purity).

## Architecture Hab validée

- MVU pur, zéro DOM dans le noyau
- Component = (init, update, view) = pair imbriqué
- View = tree (node tag children | leaf text)
- Runtime JS : load wasm, eval prelude, mount, dispatch click
- Evaluation : heavenEvalRaw → h.eval (pas cmds.eval, qui
  refuse les patterns user-defined)

## Dettes W1c (prochain)

1. serialize_tree en .hvn : node/leaf → JSON récursif, plus de
   hardcoded button dans JS.
2. Test navigateur headless (Playwright/jsdom) pour CI.
3. 2e composant (todo.hvn) avec optiques (filtre, map).
4. Fallback fs_read_public vers hab/ (supprimer duplication
   src/vessel/public/hab/).

## Dettes W2 (effets algébriques UI)

- perform DOM.click, perform State.get, handle au niveau runtime.
- Le modèle complet Lustre-Heaven (Lustre + Elm MVU + OTP).

## Dettes Phase 7 (TCO, toujours ouvertes)

- loadtest max 50 iters (TCO let-in non supporté).
- fuzz_run retiré (même raison).
- server_loop via @loop_until (contournement documenté).

## État 3 plateformes (inchangé)

Linux/macOS/Windows : build ✓, test_suite 98/98,
--http-serve 200 (500 req).

## Environnement

HEAD : 3148908 (origin/main)
Machine devilHope Linux + laptop macOS + PC Windows.
Zig 0.15.2. HEAVEN_NO_LEAK_CHECK=1 en Debug.

---

# ÉTAT AU 2026-10-28 (mise à jour)

## Milestone : HTTP natif Heaven sur 3 plateformes

`heaven --http-serve N` sert /repl.html + /heaven.wasm sur Linux,
macOS ET Windows — serveur écrit en Heaven pur (core/http_server.hvn),
aucun code spécifique par plateforme.

Commit `681ed7c` (Phase 6b) : HTTP natif Windows.

Tests validés :
  Linux   : 200 /repl.html (38261 o), 200 /heaven.wasm (584755 o)
  macOS   : 200 /repl.html (38261 o), 200 /heaven.wasm (460811 o)
  Windows : 200 /repl.html (39299 o), 200 /heaven.wasm (592034 o)
            500 requêtes séquentielles OK, rotation 180 assets OK

## Bugs corrigés en Phase 6b (commit 681ed7c)

1. `std.posix.socket_t` : i32 sur POSIX, *SOCKET__opaque sur
   Windows. Helpers `handleFromI64`/`handleToI64`.
2. `std.posix.read/write` : ReadFile/WriteFile (HANDLE fichiers),
   pas sockets. Sur Windows → `ws2_32.recv`/`ws2_32.send`.
3. `std.posix.close` : CloseHandle, pas closesocket. Sur Windows
   → `ws2_32.closesocket`.
4. `setsockopt SO_REUSEADDR` : buggé sur Windows (TigerBeetle
   issue). Skip sur Windows.
5. `WSAStartup` obligatoire : `ensureWsaInit()` one-time dans
   socket/bind/listen/accept.
6. Erreurs `std.posix.*` (AddressError, SocketError) hors EvalError :
   wrapper `catch return error.InvalidInput` dans net_sockets.zig.
7. Stub Windows retiré : `x86_64_windows.zig` importe le vrai
   `net_sockets.zig`. 10 guards `@net_*` : Windows retiré,
   wasm/freestanding restent.

## État des 3 plateformes (build + tests)

| Plateforme | build | test_suite | --http-serve |
|---|---|---|---|
| Linux x86_64 | ✓ | 98/98 | 200 /repl.html |
| macOS aarch64 | ✓ | 98/98 | 200 /repl.html |
| Windows x86_64 | ✓ | 98/98 | 200 /repl.html |

Règle `src/platform/` : 0 violation (audit `grep` automatique).

## Piège Windows MINGW64 (à documenter)

`python3` sur MINGW64 = stub Windows Store qui ne s'exécute pas
(retourne 0 silencieusement). Avoir toujours :

    PY=""
    for py in /c/Users/<user>/AppData/Local/Programs/Python/Python3XX/python.exe python3 python; do
        "$py" --version 2>/dev/null | grep -q "Python 3" && PY="$py" && break
    done

Sans ça, les scripts Python échouent silencieusement (`git commit`
disait « nothing to commit » alors que le patch n'avait pas été
appliqué).

## Acquis session précédente (rappel)

Phase 6f (`3abc8a9`) : serveur HTTP stable 500+ requêtes
  - `@loop_until` (boucle Zig native) car TCO ne traverse ni `let`
    ni `seq` (tests `loop_let_500`/`loop_if_seq_500` SIGSEGV).
  - `@clear_thunks`, `@store_stats` (diagnostic cross-requête).

Phase 6a (`128cd0b`) : net_sockets cross-platform POSIX (Linux+macOS).

E4 macOS (`b14da6a`) : règle plateforme respectée.

E4 Windows (`232b130`) : build Windows débloqué (tls_stub, x86_64_windows
  réécrit, network_windows stub, .gitattributes LF).

Migration S-expr 3.4c (5 fichiers) :
  array.hvn (7), memory.hvn (5), free.hvn (2), string.hvn (11),
  hashmap.hvn (60). Tous verts.

## Dettes Phase 7 (ordre proposé)

1. **TCO `let`/`seq`** (`engine_expr.zig`)
   - Étendre la détection self-tail-call pour traverser
     `let _ = e in call` et `(seq e call)`
   - Bénéfice : supprime `@loop_until`, permet server_loop récursif
   - Complexité : moyenne

2. **Audit `*Node` retenus** à travers `evaluate()` (vrai fix du
   crash 43 requêtes)
   - Workaround actuel : `ensureTotalCapacity` 200K/50K/100K
   - Vrai fix : snapshot des pointeurs ou re-get après eval
   - Complexité : élevée

3. **Scheduler préemptif 3.3a** : server_loop devient une tâche
   scheduler, supprime `@loop_until`

## Dettes Phase 6 (rappel)

- **Phase 6c** : TLS macOS (OpenSSL brew ou tls_stub) + Windows
  (SChannel/wolfSSL). tls_stub Windows est en place, macOS garde le
  vrai TLS via OpenSSL FFI (dépend de brew install openssl).
- **Phase 6d** : `build.sh` Windows/macOS (QBE download sans
  cc/make), `go.sh` Python PATH (stub Windows Store).
- **Phase 6e** : CI matrix Linux/macOS/Windows/WASI/WEB.

## Dettes langage

- **3.4b-ter** : `if cond then a else b` multi-ligne sans
  parenthèses (parser). Bloque migration complète de test_suite.hvn,
  bigint.hvn, heaven_parse.hvn, json/parse.hvn.
- **3.4b-bis** : `let` bind thunk non forcé sur magic RHS
  (`@spawn` non lisible via `let tid = @spawn ... in tid > 0`).
- **Migration S-expr restante** : ~13 fichiers.

## Environnement

- Machine devilHope (Linux x86_64) + laptop macOS aarch64
  + PC Windows (MINGW64)
- Zig 0.15.2 (Linux/macOS : Homebrew/store ; Windows : winget)
- `HEAVEN_NO_LEAK_CHECK=1` requis en Debug (heap corruption
  préexistante, cf. `_http_debug_crash.md`)
- `test_suite` : 98/98 stable sur les 3 plateformes
- HEAD : `681ed7c` (origin/main)

---

# ÉTAT AU 2026-10-28 — Session plateformes + HTTP stable

## Acquis (commits poussés sur origin/main)

`3abc8a9` Phase 6f : **serveur HTTP stable, 500+ requêtes**
  - `@loop_until(cond_thunk, body_thunk)` : boucle Zig native (while)
  - Remplace la récursion `server_loop` (TCO cassé par `let`/`seq`)
  - Tests : 500 requêtes `/repl.html` OK, rotation 180 assets × 10 OK
  - `@clear_thunks`, `@store_stats` (diagnostic cross-requête)

`128cd0b` Phase 6a : **net_sockets cross-platform**
  - 209 → 116 lignes, `std.os.linux.syscallN` (15 sites) → `std.posix`
  - HTTP natif `--http-serve` fonctionne **Linux + macOS** (plus Windows)
  - 200 /repl.html (38261 o), 200 /heaven.wasm (460811 o)

`b14da6a` E4/macos : **règle plateforme respectée**
  - `intrinsics.zig` : `rawSyscall` portable (`-1` hors Linux)
  - 10 guards `@net_*` → `NotSupported` propre (plus de SIGSYS)
  - `isatty`, `armPreemptTimer` (no-op macOS)
  - Audit règle plateforme : 0 violation

`232b130` E4/windows : **build Windows débloqué**
  - `x86_64_windows.zig` réécrit (~280 lignes, modèle Linux)
  - `network_windows.zig` stub swarm P2P, `tls_stub` Windows
  - `.gitattributes` : `eol=lf` (CRLF → SIGSEGV sur 2ᵉ build)

`752ccb5` vendor tree-sitter-pie

Migration S-expr (3.4c partiel) :
  - `58aa425` array.hvn (7 conversions)
  - `3bfec6f` memory.hvn (5)
  - `c3075ad` free.hvn (2)
  - `a863237` string.hvn (11)
  - `hashmap.hvn` non commité mais migré (60 conversions, tests 15/15 puis SIGSEGV préexistant)

## État des 3 plateformes

| Plateforme | build | test_suite | --http-serve |
|---|---|---|---|
| Linux x86_64 | ✓ | 98/98 | 200 /repl.html |
| macOS aarch64 | ✓ | 98/98 | 200 /repl.html (500 req OK) |
| Windows x86_64 | ✓ | 98/98 | NotSupported (WSAStartup) |

Règle `src/platform/` : 0 violation (vérifié `grep`).

## Découvertes majeures

**TCO partiel** :
  - `if/then/else` TCO'd à 500+ (test `loop_if_then_else`)
  - `let _ = A in B` **casse le TCO** (`loop_let_500` SIGSEGV)
  - `seq A B` **casse le TCO** (`loop_if_seq_500` SIGSEGV)
  - Conséquence : `server_loop` ne PEUT PAS être self-récursif en TCO
  - Fix pragmatique : `@loop_until` (while Zig natif)

**UAF latent sur `*Node`** :
  - Crash HTTP à 43 requêtes = `ArrayListUnmanaged` realloc (~2048)
  - Workaround : `Store.init` prealloc 200K/50K/100K
  - Vrai fix : audit des `*Node` retenus à travers `evaluate()` (Phase 7)

## Dettes Phase 7 (nouvelles, prioritaires)

1. **TCO `let`/`seq`** dans `engine_expr.zig`
   - Étendre la détection self-tail-call pour traverser `let _ = e in call`
     et `(seq e call)`
   - Bénéfice : supprime `@loop_until`, permet `server_loop` self-récursif
   - Complexité : moyenne (2-3 jours)

2. **Audit `*Node` retenus** (vrai fix du crash 43)
   - Pattern : `const n = store.get(id); ... evaluate(...); n.tag`
   - Rechercher tous les sites, snapshot ou re-get après eval
   - Bénéfice : supprime `ensureTotalCapacity` workaround
   - Complexité : élevée (audit exhaustif, refactor profond)

3. **Scheduler préemptif** (3.3a)
   - `server_loop` devient une tâche scheduler (`schedule`/`yield`)
   - Supprime `@loop_until` (le scheduler boucle nativement)
   - C'est la voie Lustre Heaven

## Dettes antérieures (rappel)

- **Phase 6b** : Windows sockets (`WSAStartup` + ws2_32 → HTTP Windows)
- **Phase 6c** : TLS macOS (OpenSSL brew ou stub) + Windows (SChannel)
- **3.4b-ter** : `if cond then a else b` multi-ligne sans parenthèses
  (bloque migration S-expr complète, notamment `test_suite.hvn`)
- **3.4b-bis** : `let` bind thunk non forcé sur magic RHS
  (`@spawn` retour non lisible via `let tid = @spawn ... in tid > 0`)
- **Migration S-expr** : ~13 fichiers restants (`core/test_suite.hvn`,
  `core/bigint.hvn`, `lib/heaven_parse.hvn`, `stdlib/json/parse.hvn`,
  `stdlib/net/http_client.hvn`, ...)

## Ordre proposé pour la prochaine session

1. **3.4b-ter** — fix `if` infixe multi-ligne (parser)
   - Débloque la migration S-expr complète
   - Prérequis pour réécrire `test_suite.hvn` en infixe

2. **Migration S-expr restante** (3.4c suite)
   - `core/bigint.hvn` (40), `lib/heaven_parse.hvn` (34),
     `stdlib/json/parse.hvn` (30), `stdlib/net/http_client.hvn` (14)
   - `core/test_suite.hvn` en **dernier** (garde-fou)

3. **Phase 6b** — Windows sockets
   - `WSAStartup`, `net_sockets` → ws2_32
   - Suppression stub `x86_64_windows.zig`

4. **Phase 7** — TCO + audit `*Node`
   - Plus profond, à faire quand le reste est stable

## Environnement

- Machine devilHope (Linux x86_64) + laptop macOS aarch64
- Zig 0.15.2
- `HEAVEN_NO_LEAK_CHECK=1` requis en Debug (heap corruption
  préexistante, cf. `_http_debug_crash.md`)
- `test_suite` : 98/98 stable
- Commit HEAD : `3abc8a9`

---

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

## OTP — O1 en cours (gen_server.hvn, préemptif)
- `core/std/otp/gen_server.hvn` : cast/call, préemptif sur linux-x86_64.
- Tests : `tests/test_gen_server{,_load,_prop,_fuzz}.hvn`
  avec quickcheck/fuzzer (core/std).
- O2 (links/monitors) : modifier `src/runtime/scheduler/scheduler.zig`.

## 2026-10-28 — Bilan OTP/Hab

Tags : otp-o1, otp-o2.0..4, otp-o3, tdd-v1, tdd-v1.1, hab-o4.1, check-v1.
Total : 11 tags, ~56 tests verts.

Livrés :
- OTP complet (GenServer, links, 3 stratégies polling+event-driven)
- MPST runtime (check_dual, check_protocol sur mpst_trace)
- TDD runtime (@hole, @is_hole, @assert_no_hole, refine_tdd, match1/2/3/list)
- Hab lens MVU (lens_mvu_get/set/over + dispatch_from + dispatch_list)
- Hab superviseur one_for_one (hab/supervisor.hvn, tick_all)
- Check v1 (arité, literal-as-function, partial-lambda)

Dettes documentées (`docs/spec/_runtime_gaps.md`) :
1. run multi-message perd des messages (STATUS.md:303)
2. thunks top-level non-déballables
3. (f a b) ne curryfie pas (force requis)
4. QTT erased = 0 usage strict (correct mais message cryptique)
5. check-v2 scope tracking TODO (~150 lignes)
6. heaven check = stub (utilise tree-sitter incomplet)

Prochaines étapes :
- O4.3 : app Hab complète (N enfants supervisés + chapitre livre 32)
- Fix runtime #1 : run multi-message (bloque actor mailbox)
- Fix runtime #2 : thunks top-level
- Fix runtime #3 : (f a b) curryfication
- check-v2 : unbound variables (filet complet)
- captureCont : N=1000 quickcheck



## TODO 2026-10-29 — Vérifier et compléter

### A. Triade test dynamique en Heaven pur

Objectif : `quickcheck` / `smocker` / `fuzzer` forment un pipeline complet
(PBT → isolation → stress). Tous en `.hvn`, zéro Zig.

| Module | État supposé | À vérifier | À ajouter |
|---|---|---|---|
| `quickcheck.hvn` (37 l.) | check + 1 `shrink` déjà là | `shrink` fonctionnel ou juste déclaré ? | `shrinkIter` récursif + tests |
| `smocker.hvn` (34 l.) | mock/seq/verify OK (O2.3) | 0 `perform`/`handle` — n'enregistre PAS les effets | `expect_effect`, `verify_effects`, `effect_trace` |
| `fuzzer.hvn` (30 l.) | génération de listes | 0 `mutate`/`truncate` — purement génératif | `mutate`, `truncate`, `bitflip`, `boundary` |

**Décision** : ajouter ce qui manque, ou documenter les limites réelles.
Priorité : `quickcheck.shrink` (utile pour tous les tests d'invariant).

### B. 4 axes de refactoring par réflexivité

Idée : appliquer à Heaven ses propres principes pour réduire le Zig
(~96 % du code) et faire du langage son propre outil.

1. **I/O unifiés sous effets algébriques**
   - `src/platform/` devient un handler unique (`handle-rec`).
   - Les I/O sont des `perform "Syscall" (Write fd buf len)`.
   - Gain : mocker tout le système dans des tests `.hvn`.
   - **Fait vérifié (2026-10-28)** : `grep -c "perform|handle_rec|handler"`
     sur `platform/*.zig` = **0 partout**. Appels directs confirmés.
     Chantier complet à faire.

2. **Lowering strict aux 6 primitives (`Store.lower()`)**
   - **Fait vérifié (2026-10-28)** : `Store.lower()` existe déjà
     (`expr.zig:1215`) et `Store.lowerRec()` (`expr.zig:1363`).
     RFC-0001 en cours (« ImportState extrait dans import.zig
     (RFC-0001 5/5) »). D21 à relire.
   - **À vérifier** : les codegens (QBE, WASM, C) consomment-ils
     vraiment l'AST abaissé, ou voient-ils encore du sucre ?
   - **Chantier** : brancher les codegens sur `lowerRec()` si pas fait.

3. **Linter/Formatter via E-Graphs + miniKanren**
   - `fmt`, `check`, refactoring comme règles de réécriture déclaratives.
   - Utiliser `egraph` + `kanren_expr` (existent déjà).
   - Gain : le moteur de réécriture devient son propre refactoring.
   - **Vérif préalable** : `egraph_rewriter.zig` est-il branché sur `fmt` ?

4. **Auto-hébergement (`lib/parse/infix.hvn`)**
   - Transférer la passe infixe vers `.hvn`.
   - Zig réduit à TCB (moteur 6 primitives).
   - Gain : maintenance centralisée dans la stdlib.
   - **Vérif préalable** : combien de lignes dans `heaven_expr.zig` pour
     le parsing infixe ? Peut-on déjà l'écrire en `.hvn` ?

**Ordre suggéré** : 1 (I/O effects → débloque `smocker`) > 3 (egraphs → `fmt`) > 4 (self-hosting). Le #2 (lowering) est surtout une **vérification** de branchement, pas une implémentation.

### C. Dettes runtime (priorité fix)

Voir `docs/spec/_runtime_gaps.md`. Priorité :
1. `run` multi-message (STATUS.md:303) — 2 sessions Zig
2. thunks top-level — 1 session
3. `(f a b)` curryfication — 1 session

### D. Continuation

- O4.3 app Hab complète (après fix runtime #1 idéalement)
- check-v2 scope tracking (UnboundVariable)
- captureCont (débloque N=1000 quickcheck)

## OTP — COMPLET (2026-10-28)

Tags : otp-o1, otp-o2.0, otp-o2.1, otp-o2.2, otp-o2.3, otp-o2.4.
Tests : tests/otp_gs_*.hvn (3) + tests/otp2_*.hvn (19) = 22 verts.

Prochaines étapes possibles :
- **O3 MPST typé** : brancher engine_types.zig pour typer statiquement
  le protocole superviseur↔enfant. Complète la vision théorique du
  projet (MPST, duals, protocoles typés).
- **parse-level verification** : parser doit rejeter un `let` sans `in`
  correct. Dette instrumentale identifiée pendant O2.
- **captureCont** (3a-3b) : débloque N=1000 quickcheck, load 1000+,
  retrait de `run` dans gen_server. Chantier Zig scheduler.
- **O4 Hab/Lustre-Heaven** : intégration finale, objectif du projet.

Recommandation : O3 MPST typé d'abord (alignement théorique + premier
vrai test du sous-système de types), puis O4. captureCont en parallèle.

Voir docs/spec/_otp.md pour la spec complète (O1 à O2.4).


Spec complète : `docs/spec/_otp.md`.

Portage OTP en Heaven pur (7 étapes, ~7 sessions) :
- O1 GenServer (spawn/call/cast/info)
- O2 link/monitor/trap_exit dans le scheduler Zig
- O3 supervisor one_for_one (compteur restarts)
- O4 rest_for_one, one_for_all, simple_one_for_one
- O5 application (démarrage ordonné, deps)
- O6 intégration Hab : composant = gen_server supervisé

Vision : Hab + OTP = Lustre + Erlang en un langage. Un composant
Heaven tourne client (wasm) ou serveur (HTTP natif) ou distribué
(Swarm), supervisé côté serveur, dégradé côté client.

Décisions à acter (dans _otp.md) : gen_server_call sync via effet
ou polling, links table dans scheduler, EXIT comme message normal,
restart counter dans supervisor, app single-niveau.

