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

**Derniers commits connus** :
- `584e5e2` chore(vessel): E3c — dedup heaven_expr, retire main_mod
- `f2ee36c` fix(json): H1/H2 clos — artefacts `\"`, pas bug parser
- `00e1475` feat(vessel): didSave via Heaven.eval (E3b/5, D9)
- `0bdc6e9` feat(vessel): serveTelemetry via telemetry_store (E3a/5, D9)
- `e65dc66` feat(vessel): telemetry_store.zig (E1/5, D9)

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

## Ordre de priorité pour la suite

1. **E4 HTTP fullstack** (1-2 sessions de conception, pas un bloc).
   `core/http_server.hvn` : (a) inventaire sockets `.hvn`
   (`stdlib/net/http.hvn` n'a pas de `serve|listen|accept`), (b)
   `encode_jsonrpc`/`decode_jsonrpc` en `.hvn` (H1/H2 clos = objet
   JSON OK), (c) décision statiques Zig vs `.hvn` (`@embedFile`
   n'existe pas en `.hvn`). Voir `_http_fullstack_plan.md`.
2. **E5** (1 session) — `matrix`/`autofab` → `src/legacy/`. 6 usages
   résiduels `self.matrix` dans `bridge.zig`. Après E4.
3. **effects-consolidation** (1-2 sessions) — `perform`/`handle`/
   `yield`/`resume` cohérents. Prérequis MPST-V2 et A-3b-3.
4. **hkt-v1b** (2 sessions, décision A vs B) — dispatch typeclass.
   V1a déclaratif livré (0 dispatch). Voir `_hkt_v1b_plan.md`.
5. **mpst-v2a** (2 sessions) — multipartite + projection. Voir
   `_mpst_v2_plan.md`.
6. **metacircularite-patterns** (2-3 sessions) — manque #2 de
   `_metacircularite_chantier.md`. Le fossile #4 sera attaqué ici.
7. **quotients-expose** (2-3 sessions) — kernel prêt, exposition
   `.hvn` reste.

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
