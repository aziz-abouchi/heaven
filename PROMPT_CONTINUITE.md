# Prompt de continuité — Heaven

## Contexte projet

**Heaven** est un langage de programmation expérimental unifiant :
- Raisonnement mathématique (CIC, preuves, tactiques)
- Métaprogrammation (egraph, kanren, macros)
- Concurrence (acteurs, scheduler coopératif, effets algébriques)

**Invariants fondateurs** (docs/VISION.md) :
- 6 primitives de noyau (`lit`, `sym`, `apply`, `bind`, `lambda`, `relation`)
- Le reste = sucre abaissé avant évaluation
- Vérité mathématique comme source unique (kernel CIC)
- Esthétique comme heuristique (théorème en 3 lignes > 30 lignes)

**Repo** : https://github.com/aziz-abouchi/heaven
**Machine** : Linux x86_64, Guix, Zig 0.15.2
**Working dir** : `~/Desktop/Dev/langage/boot`

---

## Convention doc critique

- **`README.md`** et **`docs/STATUS.md`** sont **GÉNÉRÉS**. Ne jamais les éditer à la main.
- Regen : `python3 scripts/docgen.py` et `python3 scripts/status_gen.py`
- **`STATUS.md`** : seule exception outillée — on édite, puis TOUJOURS `python3 scripts/status_import.py` et on committe `status.json` avec. `status_gen.py` réécrit le fichier **entier** depuis le json : une section non importée est une section perdue au prochain build.
- Le CI échoue si un chiffre est périmé (`--check`)
- `PROMPT_CONTINUITE.md`, `docs/DECISIONS.md`, `docs/ROADMAP.md` sont manuels

---

## État git actuel

**HEAD** : `5f1fdba` (feat(syntax): pont expérimental Tree-sitter → Expr.Store)

**Working tree** : `src/syntax/lower.zig` et `src/syntax/lower_test.zig`
modifiés par une session parallèle (chantier D21 — extension à `call`/`app_expr`).
**Ne pas toucher.** Ne pas `git add -A`.

**Commits poussés cette session (2026-10-08)** :

| Commit | Contenu |
|---|---|
| `c029802` | `defs.zig` : retire `normalizeOps` + distingue `fn` vs équation |
| `2db23f0` | `test_runner.zig` : support blocs `{ ... }` multi-lignes (brace_depth) |
| `c5b59d6` | regen README + STATUS |
| `5f1fdba` | pont Tree-sitter → Expr.Store (session parallèle D21) |

---

## Session 2026-10-08 — trois chantiers

### Chantier 1 — Bug `evalFnDef` (src/core/commands/defs.zig)

- `normalizeOps` transformait `+` en `add` dans les bodies. Or `add` est **aussi**
  une primitive Peano (3 args). Le dispatcher préférait la version user et
  refusait les appels à 2 args.
  → Fix : retire l'appel (`parseBodySmart` wrappe déjà).
- Distinction `fn name(args) = body` (remplace) vs `name args = body` (multi-clause) absente.
  → Fix : ajout de `is_fn_keyword` + branche `put`/`addClause` explicite.

Impact : 89/99 → 95/98.

### Chantier 2 — Bug `splitStatements` (src/runtime/test_runner.zig)

- Découpait uniquement par indentation, ignorant le `brace_depth` documenté en
  en-tête. Conséquence : le `}` en colonne 0 fermait un statement avant l'heure,
  et `prove X by { ... }` arrivait tronqué à `evalProve` → `InvalidSyntax`.
- Fix : compteur `brace_depth`. Tant qu'il est `> 0`, une ligne non-indentée
  (y compris `}`) est une continuation, pas un nouveau statement.

Impact : 95/98 → **98/98**.

**Note méthode** : le bug des tactiques n'était PAS dans `runTacticsBlock`
(hypothèse du prompt précédent) mais dans `test_runner.splitStatements`.
Toujours vérifier par lecture + bisect, pas par confiance au prompt.

### Chantier 3 — Pont Tree-sitter → Expr.Store (D21, session parallèle)

- `lowerExprToStore` dans `src/syntax/lower.zig` abaisse directement les nœuds
  Tree-sitter vers `core.Expr.Store` (6 primitives).
- Couvre actuellement : `identifier`, `int`, `binary`, `call`/`app_expr` et `pattern` (VALIDÉ 2026-10-08).
- Helper `lowerExprSource` encapsule le parsing Tree-sitter.
- `build.zig` : dépendances `core` + `platform` ajoutées au module `syntax_lower`.

**Décision D21** : `Expr.Store` devient l'unique IR intermédiaire.
`UniversalIngestor` (Matrix/BobId) → `SurvivalTranspiler` (C) sera déprécié.

**Prochaines étapes** : étendre à `let` et `lambda` (dernière étape avant migration progressive).

---

## Suites de tests (après fix)

- test_suite.hvn   : 98/98  (3 tactiques reparees)
- array.hvn        : 11/11
- string.hvn       : 15/15
- scheduler.hvn    :  3/3
- bigint.hvn       : 30/30
- effects_rec.hvn  :  4/4
- io_stream.hvn    :  4/4
- stream_lazy.hvn  :  8/8
- smoke.sh         : 16/16
- zig build test   : 383 tests Zig

### Jalon 2 (auto-hébergement) en cours

- **`core/std/array.hvn`** : array mutable via `raw_alloc`, resize auto. 11 tests.
- **`core/std/string.hvn`** : `char_code`, `string_char_at`, `string_index_of`,
  `string_starts_with`, `string_substring`. 15 tests.
- **Garde anti-shadowing** : `evalEquation` refuse les magics.
- **Nouveaux magics** : `peek_int64`, `poke_int64`, `string_of_bytes`.

---

## Décisions structurantes (DECISIONS.md)

| # | Contenu |
|---|---|
| D10 | Syscalls : 3 chemins A/B/C (`raw_syscall`, `@nom`, `HEAVEN_NO_LIBC`) |
| D11 | Perimetre multi-plateforme (amd64-linux seulement pour D10) |
| D12 | Laziness (`Tag.thunk` + `delay`/`force` + memoization) |
| D14 | IO en Heaven (5 magics fins) |
| D15 | `let` magic symbol S-expr |
| D16 | Serveur HTTP 100% Heaven |
| D17 | BigInt v0 (badd/bsub/bcmp) |
| D17-2 | BigInt signe + bmul + bto_string |
| D18 | Style Haskell multi-ligne (loader par indentation) |
| D19 | Stack guard + TCO let-in (partiel) |
| D20 | ReleaseFast par defaut (recursion profonde ~500 niveaux) |
| D21 | Unification Lowering vers Expr.Store (pont Tree-sitter) |

---

## Limites parser infixe (docs/spec/_syntax_gaps.md)

| Forme | Supporté |
|---|---|
| `f x y` | oui |
| `a + b` | oui |
| `let x = v in body` multi-ligne | oui (D18) |
| `if (cond) A B` | oui |
| `if cond A B` sans parens | non |
| `if` multi-ligne avec `let-in` dans branche | non |
| opérateur préfixe dans `if` : `if < a b A B` | non |
| bloc `{ ... }` multi-lignes dans test_runner | oui (fix 2026-10-08) |

**Workaround** : helpers nommés (`array_copy_body`, `string_copy_body`).

**Chantier futur** : parser indentation-aware complet (Python/Haskell-style).
1-2 sessions. Casse potentiellement des tests. À faire à froid.

---

## Bugs ouverts

| Bug | Impact | Effort |
|---|---|---|
| `bdiv > 1000` sur BigInt | Limite pratique | 2-3 sessions (tree-walker iteratif) |
| `if` multi-ligne avec `let-in` | Friction stdlib | 1-2 sessions (parser indentation) |
| DebugAllocator panic intermittent | Contourne via `HEAVEN_NO_LEAK_CHECK=1` | 1 session a froid |

---

## Passe de contradictions — session stratégie 2026-10-08

Convergences : frontière syscall = D10 · HTTP pur = D16 · pipeline = D21 ·
Jalon 2 = prérequis des services purs · streams = D12 (D8 = park/backpressure).

Corrections au plan stratégique :
1. README ×3 « Mise à jour Architecture » = signature d'agent en boucle.
   Protocole : ps aux + timestamps AVANT patch. Contenu déjà couvert par D21
   → suppression pure (README généré de toute façon).
2. « Un chantier à la fois » → « un chantier PAR SESSION » (règles de
   coordination multi-sessions ci-dessous).
3. Bitstrings : RFC + grammar.js + parse.zig = zéro conflit ; pont
   Tree-sitter (lower.zig) APRÈS land de D21.
4. À trancher par lecture (méthode du doc, appliquée au doc) :
   - hashmap.hvn + test_hashmap.hvn existent déjà alors que l'option B dit
     « nouveau fichier » — stub ? boucle ?
   - état réel de l'exhaustivité des patterns et de l'opacité des
     constructeurs en modules v0 — mesurer avant de chiffrer l'incrément.

## Prochaine session — options (v2)

**Option B (recommandée, session principale)** : HashMap — trancher le
point 4 par lecture d'abord. Si friction `if` multi-ligne : brique
prioritaire de l'audit d'abord (parse.zig:488, 1 session, risque faible).

**Option A (inchangée, session parallèle)** : D21 → `let`/`lambda`.
`lower.zig`/`lower_test.zig` occupés jusqu'à land.

**Option E (nouvelle, après land D21)** : bitstrings RFC-0002, impl en deux
temps (parse.zig + grammar.js, puis pont Tree-sitter).

## Arc stratégique (détail → docs/ROADMAP.md)

Principe : le statique d'abord · D8 quand ses consommateurs existeront ·
le Zig ne recule jamais.

1. bitstrings (RFC-0002)
2. incrément compilateur : filtrage dépendant sur indices + exhaustivité +
   constructeurs privés (état réel à mesurer d'abord)
3. édifice statique : caps (D22) · typestate (D23) · MPST-en-Heaven (D24)
4. tranche IA : MCP vérifié + mandats ToolCap/Budget (D25) — mcp_server.zig existe
5. D8 branchement : continuations × effets, QTT-aware (composer avec D19/D20)
6. services purs : Jalon 2 (HashMap/Set/List) puis Bitcask + Datalog sur D10
7. facette HTTP (D16) + demo day full-Heaven

Métrique-cliquet : `zig_hors_sanctuaire` dans status.json — lignes Zig hors
sanctuaire (platform/syscalls + moteur bootstrap). CI échoue si ça monte.

Hygiène (à froid, ½ journée, après vérif ps aux) : .backup_heaven/ ·
check_all.sh chemin QBE (vendor/qbe-1.2/qbe, pas vendor/qbe/obj/qbe) ·
fixtures dupliquées test_data/ ↔ fixtures/ · zig-pkg/ dupliqué.

## Décisions à enregistrer (proposition — DECISIONS.md reste manuel)

| # | Contenu |
|---|---|
| D22 | Caps : permissions = valeurs linéaires QTT, raffinables, constructeurs privés |
| D23 | Typestate : un type par état, transitions linéaires consommantes |
| D24 | MPST en Heaven : Proto/Chan, bouts issus d'un global unique |
| D25 | Position IA : notaire MCP vérifié + mandats ToolCap/Budget |

---

## Session 2026-10-09 (matin) — plomberie doc + HashMap durci (Jalon 2)

**Plomberie doc** (poussée) : pipeline STATUS guéri — dé-dup, sync
status.json, date dynamique, convention amendée : TOUTE édition de
STATUS.md -> `status_import.py` + committer le json avec.

**HashMap (Option B)** — `1808eff` :
- Le v0 existait deja (`db53128`, Int->Int, open addressing) — vert mais
  jamais intégré : l'option B du doc décrivait en fait la v1.
- Durci : `map_hash` (cles negatives), clamp cap, `map_free`, resize
  libere l'ancien buffer, commentaires honnêtes (mutable en place).
- **23/23** + batterie intacte : 98/98 · 11/11 · 15/15 · 3/3 · 30/30 ·
  4/4 · 4/4 · 8/8.
- **v1 (prochaine étape)** : cles Str — fnv1a viable (xor derivable :
  a xor b = (bor a b) - (band a b)) ou rolling 31h+c ; `map_del` (tombstones).

**Gap relevé — moins unaire** : `(- 5)` produit une valeur fausse/instable
(validé par probe P1-P4). Workaround : `(- 0 5)`. Fix future : 1 ligne
dans evalMagic — à froid, engine_expr.zig en zone active.

**Sessions parallèles (état 2026-10-09 midi)** :
- D21 : lower.zig/lower_test.zig (let/lambda) — en vol.
- Bitstrings : **P1 LANDÉ** (`216aff9` + `d731622` : les 4 opérateurs
  band/bor/shl/shr). Suite probable sur parse.zig (P2 ?).
- Terrain partagé : STATUS.md/status.json — git status avant édition.

**Suites (référence)** : test_suite 98/98 · array 11/11 · string 15/15 ·
scheduler 3/3 · bigint 30/30 · effects_rec 4/4 · io_stream 4/4 ·
stream_lazy 8/8 · **hashmap 23/23** · zig build test 383.

**Reste à faire** : néant — soldé en fin de session (le quirk négatifs
était déjà documenté le 2026-10-07, annoté d'une re-validation ; P1 coché
dans RFC-0002).

**Méthode validée** : le probe P1-P4 a tranché en une exécution ce que
deux tours de correctifs avaient embrouillé. Probes d'abord, fix ensuite.

---

## Chantiers parallèles — coordination

Le repo est travaillé par plusieurs sessions simultanées. Règles :

1. Ne jamais `git add -A` — toujours nommer les fichiers.
2. Vérifier `git status --short` avant chaque commit — d'autres fichiers
   peuvent être modifiés.
3. Si un fichier est modifié et n'est pas à toi → ne pas y toucher.
4. Agents IA qui bouclent : si un fichier contient des blocs dupliqués
   (`## 2026-10-08` × 3) ou des typos (`lover_` au lieu de `lower_`),
   c'est une signature de boucle. Vérifier `ps aux` et les timestamps
   (`ls -la --time-style=full-iso`) avant de patcher.

---

## Méthodes critiques

1. Toujours verifier par lecture + bisect avant de patcher un bug suppose.
2. Un fix = un commit = un test qui passe auparavant.
3. Ne jamais utiliser `git add -A` (plusieurs sessions parallèles tournent).
4. Helpers nommes pour eviter les `if` multi-lignes dans le parser infixe.
5. Regenerer doc : `python3 scripts/docgen.py && python3 scripts/status_gen.py` avant push.
6. `HEAVEN_NO_LEAK_CHECK=1` par defaut (contournement DebugAllocator).
7. `zig build -Doptimize=ReleaseFast` par defaut (D20).

---

## Fichiers de reference

- `docs/DECISIONS.md` — D10 a D21
- `docs/spec/_syntax_gaps.md` — limites parser infixe + quirks
- `docs/STATUS.md` — généré, état des features
- `docs/book/src/14-concurrency.md` — scheduler coopératif
- `core/std/array.hvn`, `core/std/string.hvn` — Jalon 2
- `src/syntax/lower.zig` — pont Tree-sitter → Expr.Store (D21)
- `tests/test_array.hvn`, `tests/test_string.hvn`, `tests/test_scheduler.hvn`,
  `tests/test_effects_rec.hvn`

---

## Chantier parser infixe — audit 2026-10-08

### Ce qui marche déjà (ne pas toucher)

- `f x y` en RHS, `a + b`, `if (cond) A B` mono-ligne
- `let x = v in body` multi-ligne (D18)
- `data T a b = ctor a b`
- `if` infix mono-ligne : `filter f xs = if (f x) A B`

### Ce qui manque (vrai périmètre, plus petit que prévu)

1. `if cond A B` **multi-ligne** (branche A ou B sur plusieurs lignes)
2. `if` avec `let-in` dans une branche (conséquence du #1)
3. `if < a b A B` (opérateur préfixe sans parenthèses autour de cond)

### Impact mesuré

- 64 fichiers `.hvn`, 1732 lignes
- 6 fichiers utilisent `(if ` Lisp (35 occurrences) :
  hashmap 13, test_suite 6, string 6, array 4, effects_rec 3, scheduler 3
- 2 fichiers utilisent déjà `if` infix mono-ligne (list.hvn, stream.hvn)
- Rien sur le multi-ligne côté parser → c'est le **loader** qui accumule
  (parenthèses équilibrées pour std_loader, brace_depth pour test_runner)

### Où c'est parsé

- `src/core/parse.zig:457` : forme S-expr `(if c A B)` num_parts == 4
- `src/core/parse.zig:488` : forme infix (cond_str / then_str / else_str)
- **Cible probable du fix** : parse.zig:488 (découpage infix)
- `src/core/heaven_expr.zig:2006` : liste magics (garde anti-shadowing)

### Brique prioritaire

Rendre `if cond A B` multi-ligne fonctionnel.
Effort : 1 session. Risque : faible (les tests mono-ligne passent déjà).

### Méthode

1. Test minimal qui échoue (voir Bloc B ci-dessous).
2. Étendre parse.zig:488 pour accepter branche multi-ligne.
3. Vérifier 98/98 + suites intactes. Commit.
