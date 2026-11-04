# Annexe G — Pièges runtime et parser

> Les 22 pièges rencontrés en session 2026-10-30. Chaque piège a coûté
> entre 10 minutes et 2 heures de diagnostic. À lire AVANT d'écrire du
> code non-trivial.

## A. Parser et syntaxe

### G.1 — Lambda 2-params ne parse pas

    -- PIEGE : 3 lambdas imbriques, handler malforme
    fn_test = (lambda s m. (pair s m))

    -- CORRECT
    fn test_ok(s, m) = (pair s m)

`(lambda a b. body)` produit 3 lambdas imbriqués. Utiliser `fn name(a,b)`.

### G.2 — let-in en RHS de = casse le parser

    -- PIEGE
    f x = (let many n = (+ x 1) in n)

    -- CORRECT : let-in dans une lambda
    f x = ((lambda _ -> (let many n = (+ x 1) in n)) 0)

### G.3 — `(= X Y)` préfixe ne matche pas le runner

    -- PIEGE : "operateur '==' manquant"
    test "x":
      (= (+ 1 2) 3)

    -- CORRECT : == top-level
    test "x":
      (+ 1 2) == 3

### G.4 — N lets + body = N+1 closes

    -- PIEGE : close manquante
    test "x":
      (let many a = 1 in
       (let many b = 2 in
        (+ a b)) == 3

    -- CORRECT : 2 lets + body = 3 closes
    test "x":
      (let many a = 1 in
       (let many b = 2 in
        (+ a b))) == 3

Règle : `scripts/check_parens.py` vérifie l'équilibre.

### G.5 — `print` est variadic

    -- PIEGE : (print s) "avale" == true
    test "x": (print s) == true

    -- CORRECT : pas de print dans un test
    test "x": s == true

### G.6 — `range` n'existe pas

`range lo hi` n'est pas défini. Utiliser `cons`-chain :

    (cons 0 (cons 1 (cons 2 nil)))

### G.7 — `>`, `<=`, `>=` sont partiels

`>` marche en QBE (via `cmp_lt` inversé). `<=`, `>=` ajoutés mais
pas testés exhaustivement. `sign (0 - 5)` échoue (phi3).

### G.8 — `lambda x. body` (dot) vs `lambda x -> body` (arrow)

Le `.` casse en multi-args. Utiliser `->` ou `fn`.

## B. Eval et runtime

### G.9 — `module X` casse les imports qualifiés

Fichier `core/std/X.hvn` avec `module X` → `X.foo` retourne un thunk.
Fix : retirer `module X` (cf. `lens.hvn`).

### G.10 — `import ... as X` casse les fonctions 2-args

    -- PIEGE : SV.child_mk retourne un thunk
    import "core/std/otp/supervisor.hvn" as SV
    (SV.child_mk inc 0)

    -- CORRECT : unprefixed
    import "core/std/otp/supervisor.hvn"
    (child_mk inc 0)

### G.11 — `fst param` dans une closure = thunk non forcé

    -- PIEGE
    make_getter o = (lambda s. ((fst o) s))

    -- CORRECT : pattern matching
    make_getter (pair go _) = (lambda s. (go s))

Fix 4+5 (v0.95) résout `apply(X, [])` et `apply(apply(X, []), [y])`.

### G.12 — Thunks top-level non-déballables

    -- PIEGE : thunk
    counter_comp = (mk_component 0 upd vw)

    -- CORRECT : fonction 0-arg
    counter_comp _ = (mk_component 0 upd vw)

### G.13 — `let erased` = 0 usage strict

    -- PIEGE : LinearViolation
    (let erased x = 5 in x == 5)

    -- CORRECT
    (let erased _ = 5 in 42)

QTT : `erased` = 0 usage, `linear` = 1, `many` = 0+.

### G.14 — `run` multi-message perd des messages

    -- PIEGE : messages droppés
    (tell p m1) (tell p m2) (tell p m3)
    (run p)

Workaround : `dispatch_from` (pur). Dette STATUS.md:303.

### G.15 — Ordre d'eval top-level compte

    -- PIEGE : tree_random undefined
    test "x": (tree_random 5)
    tree_random 0 = (leaf "x")

    -- CORRECT : définitions AVANT
    tree_random 0 = (leaf "x")
    test "x": (tree_random 5)

## C. Test runner

### G.16 — `heaven run` exécute UN test

    $ heaven run tests/foo.hvn   # 1 test
    $ heaven test tests/foo.hvn  # tous

### G.17 — Un fichier par test quand ils interagissent

Éclater en `tests/foo_1.hvn`, ..., `foo_5.hvn` si contamination.

### G.18 — `exit: 0` avec tests ✗

Bug sémantique `runTestDir` (fixé). Vérifier la version.

## D. Compilation et backend

### G.19 — `zig build` inutile pour `.hvn`

`std_loader.zig:57` = `readFileAlloc` (runtime). 0 rebuild pour `.hvn`.

### G.20 — `mir.zig` touché = 2m05s

1700 lignes, 10 imports. Split `types.zig` + `compile.zig` = 8× gain.

### G.21 — QBE refuse les phis orphelins

    ; PIEGE : predecessors not matched in phi
    ; CORRECT : emit copy 0

Fixé dans `mir_qbe.zig`.

### G.22 — WASM ne supporte pas heap (session future)

`mir_wat.zig` rejette `alloc`/`load_at`/`store_at`. Émet `unreachable`.

## Référence

Détail complet : `docs/spec/_runtime_gaps.md` (25 sections).

### G.23 — `let` supplémentaire dans `handle_static` → UnknownSymbol

    -- PIEGE : dans core/http_server.hvn, après les 3 lets existants
    handle_static p =
      let clean_path = (strip_query p) in
      let path0 = (if (clean_path == "/") "index.html" clean_path) in
      let path_raw = (strip_slash path0) in              -- ❌ déclenche
      let path = (if (== path_raw "") "index.html" path_raw) in
      ...

    -- Le serveur meurt dès la 1ère requête statique avec :
    --   [http_run] http_serve result: [eval error] error.UnknownSymbol

    -- CORRECT V0 : revenir à la forme à 3 lets
    handle_static p =
      let clean_path = (strip_query p) in
      let path0 = (if (clean_path == "/") "index.html" clean_path) in
      let path = (strip_slash path0) in
      ...

Hypothèse : soit le 4ᵉ `let` dépasse un seuil de profondeur dans le
handler `let` d'`evalMagic`, soit `(== x "")` sur string vide n'est
pas supporté dans ce contexte. Bisection A/B/C du 2026-10-30 :
v6 pur et v6+cache OK, v6+cache+guard mort. À isoler en session
dédiée (micro-test avec un `let` puis `(== x "")` séparés).

Conséquence pratique : `handle_static ""` (si path vide) appelle
`fs_read_public ""` → tentative d'ouverture du répertoire
`src/vessel/public/`, qui retourne une erreur EISDIR. Le serveur ne
crashe PAS sur ce cas (v6 pur tient 500 req séquentielles), donc
pas de guard nécessaire en V0.

### G.3-bis — `(== X Y)` préfixe : confirmé en session 2026-10-30

Test mené sur `core/http_server.hvn` (commit c3941e4 → fix) :

    -- PIEGE : préfixe (== ...) dans une cascade de if
    (if (== clean "/hab") (h_ok ...) (if ...))

    -- Résultat : UnknownSymbol dès la 1ʳᵉ requête /hab
    -- Le runner ne dispatche pas `==` en position préfixe dans ce contexte.

    -- CORRECT : infixe (X == Y) ou dispatch hors cascade
    (if (clean == "/hab/") (h_ok ...) ...)
    -- Pour /hab bare : dispatcher dans handle_request, pas dans handle_hab
    (if (p == "/hab") (h_ok ...) (if (string_starts_with p "/hab/") ...))

Confirmé empiriquement après 3 itérations. Toujours privilégier l'infixe
`X == Y` dans les cascades `if`, ou sortir le cas bare dans une couche
supérieure (moins de if imbriqués, moins de risque).

### G.24 — Cascade `if` : 5 niveaux max en pratique

`handle_hab` fonctionne avec 5 `if` imbriqués (testé 2026-10-30).
Un 6ᵉ `if` ajouté pour `/hab` bare a cassé le serveur (UnknownSymbol),
mais le fix G.3-bis a permis de garder 5 `if` et de déporter `/hab`
dans `handle_request`. Règle empirique :

- ≤ 5 `if` imbriqués : OK
- ≥ 6 : dispatcher dans une couche supérieure (routing `handle_request`)

Ça reste à isoler précisément (micro-test 5 vs 6 if purs), mais en
pratique la limite 5 est un bon garde-fou.

### G.25 — multi-clauses exclues [RESOLU 2026-10-30 soir]

`precompileUserFns` (mir.zig:694) filtre `num_clauses != 1 → continue`.
`dispatch 0 = 0 | dispatch 1 = 1 | ...` n'est jamais dans `fn_defs`
→ appels unresolved → stub `ret 0`. Tous les dispatches retournent 0.

**RESOLU** : merge au parse dans `qbe_cmd.zig` (commit `f4e910b`, tag
`selfhost-multiclause-v0`). `parseClause` + `flushPendingClauses`
collectent les clauses et fusionnent en cascade `if` + `@strcmp` :

    -- utilisateur
    dispatch 0 = 42
    dispatch 1 = 99
    dispatch x = 0

    -- merge parse-time
    dispatch __x = (if (= __x 0) 42 (if (= __x 1) 99 0))

**Validation** : `dispatch 1` → 99, `dispatch 0` → 42. Voir
`bin/heaven.hvn` V0.7.

Voir aussi : G.3-bis (`==` préfixe), G.24 (cascade `if` ≤ 5),
G.33/G.34 (fn user), ch. 39 selfhosting.

### G.26 — `$main` QBE void → exit code ignoré

Diagnostic 2026-10-30 : `emitQbeLoop` émettait `export function $main()`
(sans type de retour). QBE traitait donc `ret %r` comme `ret` void, et
le shell lisait `eax` = code de retour de `printf` (=2, car `"%ld\n"`
fait 3 caractères + null → 2 en bas 32 bits de rax après multiply-add).
Fix : `export function l $main()` + `ret %r` (long/i64).
glibc lit `eax & 0xFFFFFFFF` → exit = valeur de dispatch.

**Reste ouvert** : wrapper `loop_count > 1` utilise `%loop_r` mais
`ret %r` (bug latent, non testé, cf. bench-qbe `--loop N`).

### G.27 — `heaven.eval("name = \"str\"")` pollue les warnings unresolved

Diagnostic 2026-10-30 : `compile-qbe` sur un fichier contenant un string
binding (`msg = "hello"`) émet ~54 `[mir_qbe] warn: unresolved call sym=...`.
Cause probable : `heaven.eval("msg = \"hello\"")` peuple `engine.fns` avec
des symboles stdlib (`string_concat`, etc.) que `precompileUserFns` tente
ensuite de compiler mais qui ne sont pas dans `fn_defs`.

Non bloquant (`main = 42` compile OK), mais pollution bruyante. À
investiguer : `precompileUserFns` devrait filtrer les symboles stdlib
connus, ou `heaven.eval` ne devrait pas peupler `engine.fns` pour une
définition de valeur pure (pas une fonction).

Voir aussi : G.25 (multi-clauses), G.26 (wrapper $main).

### G.28 — String binding (`version = "..."`) non inliné

Diagnostic 2026-10-30 : `version = "..."` puis `main = (@puts version)`
compile QBE en `load $gSym` pour `version`, mais `$gSym` n'est jamais
initialisé (le string literal est bien dans `.data`, mais le global
pointeur n'est pas émis). Résultat : `cc` échoue avec `ChildFailed`.

**Workaround V0.2** : inliner le string directement :
`main = (@puts "heaven 0.2.0-natif")`.

**Fix propre** : détecter les bindings de string et émettre
`data $gSym = { l $str_N }` (l = long, adresse du string) dans le
préambule QBE. Ou substituer le binding directement (inline).

### G.29 — `@nom` accepté par `parse.Parser` mais pas par `heaven parse`

Diagnostic 2026-10-30 : deux parseurs coexistent :
- `parse.Parser` (utilisé par `compile-qbe`/`compile-wasm`) → accepte `@`
- `heaven parse` subcommand (probablement tree-sitter) → rejette `@`
  avec `ERROR [1:8-1:9] @` + `MISSING ;`

Non bloquant (compile-qbe fonctionne), mais divergence à unifier en
session dédiée. Soit ajouter `@` à la grammaire tree-sitter, soit
router `heaven parse` vers `parse.Parser`.

Voir aussi : G.28, G.27.

### G.30 — Parser splitte les strings sur espaces (bug V0.2)

Diagnostic 2026-10-30 : `parseSExpr` (utilisé par `compile-qbe`/
`compile-wasm`) ne gère pas les espaces à l'intérieur des strings.

    main = (@puts "hello world")   -- parse en @puts("hello", "world")

Conséquence : `@puts` reçoit 2 args, le 1er (`"hello"`) est un
`const_str` (mais `data $str_0` manquante → ld: undefined ref
`str_0`), le 2e (`.world`) génère du bruit.

**Workaround V0.2.1** : utiliser des hyphens (`"heaven-0.2.0-natif"`)
au lieu d'espaces. `"hello-world"` fonctionne.

**Fix propre** : dans `parseSExpr`, la lexer de strings doit consommer
jusqu'à la prochaine `"` (pas jusqu'au prochain whitespace). Session
dédiée (~30 min).

Voir aussi : G.29 (`@` rejeté par `heaven parse`), G.28 (string
binding non inliné).

### G.32 — `@argv` nativement (ABI SysV)

Implémenté 2026-10-30 :
- `@argv N` → magic lowering (mir.zig) : `load $heaven_argv` +
  `mul idx*8` + `add` + `load_at 0` → `char*`
- wrapper conditionnel `export function l $main(l argc, l argv)` si
  `argv_sym` non-null, sinon wrapper `l $main()` original
- `storel %argv, $heaven_argv` en entrée + `data $heaven_argv = { l 0 }`
- `collectGlobals` ajoute `argv_sym` pour émettre le `data`

Test ABI préalable (QBE 1.2) : `function w $main(w %argc, l %argv)`
accepté, argc en `%edi`, argv en `%rsi`, retour dans `%eax`.
On utilise `l` (i64) pour le retour — glibc lit `eax & 0xFFFFFFFF`.

Vérifié :
    ./t_arg.bin version         → 'version'
    ./t_arg.bin help            → 'help'
    ./t_arg.bin 'hello world'   → 'hello world'

Dispatch réel (strcmp + if) : session suivante (nécessite `extern_call
strcmp` + multi-clauses ou cascade if sur char*).

Voir aussi : G.28 (string binding), G.30 (strings + espaces), G.31.

### G.32-bis — `@strcmp` natif (via extern_call)

Découvert 2026-10-30 : `@strcmp` est **déjà fonctionnel** via le
fallback `@nom` dans `mir.zig`. `(@strcmp a b)` émet
`extern_call strcmp(a, b)` → glibc link → retour int (0 si égal).

Vérifié : `(@strcmp "a" "a")` → 0, exit 0.

Permet le dispatch CLI sans multi-clauses (G.25) :

    main = (if (= (@strcmp (@argv 1) "version") 0) 1 0)
    ./bin/heaven-natif version → exit 1

Note : `@getenv` (externe aussi) est vérifié fonctionnel (session G.28).

### G.33 — `@argv` dans une fn user [RESOLU 2026-10-30 soir]

> **RESOLU** : `effective_argv_sym` scanne fn_defs dans emitQbeLoop
> (commit a0218de, tag `selfhost-argv-fnuser-v0`).

Diagnostic 2026-10-30 (test C) :

    getarg __i = (@argv __i)
    main = (getarg 1)
    ./t_C.bin abc   → Erreur de segmentation (exit 139)

Cause : `argv_sym` est stocké sur le `MirFunction` courant (la fn
user `getarg.fn_mir.argv_sym`), pas sur `root.argv_sym`. Le wrapper
`$main()` n'émet pas `storel %argv, $heaven_argv` (car
`root.argv_sym == null`). À l'exécution :

1. `$heaven_argv = { l 0 }` (initialisé à zéro)
2. `getarg` fait `load $heaven_argv` → 0
3. `add 0, idx*8` → `idx*8`
4. `load_at idx*8` → segfault (adresse invalide)

**Fix prévu** : dans `emitQbeLoop`, scanner tous les
`fn_defs.fn_mir.argv_sym` ; si un seul est non-null, utiliser le
wrapper `l $main(l argc, l argv)` et émettre `data $gN` pour ce sym.
Ou alternativement, propager `argv_sym` au root lors du
`precompileUserFns`.

**Contournement actuel** : ne pas utiliser `@argv` dans une fn user ;
garder l'appel `(@argv N)` directement dans `main`.

### G.34 — `@strcmp "str"` dans une fn user [RESOLU 2026-10-30 soir]

> **RESOLU** : migration str_pool fn_defs → root dans precompileUserFns
> (commit 3ac0044, tag `selfhost-strcmp-fnuser-v0`). → `undef fN`

Diagnostic 2026-10-30 (test B) :

    cmp __x = (@strcmp __x "version")
    main = (cmp "version")
    → ld: référence indéfinie vers « f<N> » (exit ChildFailed)

Cause : `@strcmp __x "version"` dans `cmp.fn_mir` remplit
`cmp.fn_mir.str_pool`. G.31 (workaround) skip l'émission des fns
avec `str_pool` non vide. Donc `cmp` n'est pas émise, et `main`
appelle `$f<N>` → undef.

**Fix prévu** : pool global partagé (root.str_pool utilisé par tous
les fn_defs). Alors `emitInstr.const_str` utilise le pool du root, et
G.31 devient inutile.

**Contournement actuel** : ne pas mettre de string littérale dans une
fn user destinée à QBE. Garder `@strcmp` inline dans `main`.

Voir aussi : G.25 (mise à jour merge), G.31 (skip fn_defs str_pool).

### G.35 — `call_user` unresolved en WASM (fail-fast) [RESOLU]

`mir_wat.zig` levait `error.UnsupportedCall` pour tout `call_user`
dont le sym n'était pas dans `fn_defs`. Une fn std non compilée
bloquait la compilation, même `main = 42`.

**RESOLU** (commit selfhost-wasm-v0) : stub silencieux
`(local.set $rN (i64.const 0)) ;; stub fN` au lieu de fail. Même
pattern que G.31 pour QBE.

### G.36 — `main = EXPR` ignoré en WASM [RESOLU]

`wasm_cmd.zig` n'avait pas le fix `main = EXPR` (fait pour
`qbe_cmd.zig` en eda3c24). `main = 42` → NoExpression.

**RESOLU** (commit selfhost-wasm-v0) : détection `main =` avant
`isDefinition`, port du fix qbe_cmd.

Voir aussi : ch. 39 selfhosting, G.25/G.31 (patterns QBE équivalents).

### G.37 — `parse_file` sur token unique → programme vide [RESOLU 2026-11-02]

> **RESOLU 2026-11-02** : `parse_top (TCons (TSymTok name) TNil) = (parse_one (TCons (TSymTok name) TNil))` ajouté. `nil`/`true`/`false` bare → `(ECons (ESym "...") ENil)`. Non-régression : `f x = ...` reste parsé via `top_named` → `def_scan`. 13/13 `test_eval`, 7/7 `test_meta_if`.

> **Mise à jour 2026-11-02.** `[16]`→`[32]` dans `engine_expr.zig` a
> débloqué 14 tests (`test_eval` 4, `test_meta_if` 10) : les clauses
> `VClosure`/`VRecClosure`/catch-all de `eval_apply2` (17-19) et les
> cascades `EApply` de `parse_if` étaient silencieusement droppées.
> Une partie des `ArityMismatch` attribués à ce piège venait en fait
> de `[16]`, pas du parser. Les limitations restantes (listées
> ci-dessous) sont vérifiées après `[32]`.

Découvert 2026-10-30 (session heaven_eval). `HP.parse_file (HP.lex "nil")`
retourne `ENil` (programme vide) au lieu d'un programme à 1 instruction.

Conséquence : `HE.eval_file (HP.parse_file (HP.lex "nil")) HE.EnvNil`
retourne `EnvNil` au lieu de `VListNil`.

**Contournement** : tester dans un contexte multi-token (`(if true 42 99)`,
`(+ true 0)`), pas en bare.

**À investiguer** : `parse_file` (lib/heaven_parse.hvn) a probablement
un pattern qui nécessite au moins 2 tokens. Session dédiée si le bare
single-token devient critique.

Voir aussi : ch. 39 selfhosting, heaven_eval_v0.2.

### G.38 — `HP.lex`/`HP.parse_file` échouent sur `let`/`lambda` [RESOLU 2026-11-02]

> **RESOLU 2026-11-02.** Cause exacte : `heaven_expr.zig::eval` ligne ~1262 utilisait `std.mem.indexOf(trimmed, "let ")` (brut, y compris dans les strings) pour router `(let ...)`/`(lambda ...)` vers `importExpr`. Pour `(HP.lex "let x")`, `"let x"` contient `"let "` → branche `importExpr` → thunk au lieu de `(HP.lex ...)`. Fix : helper `containsKeywordAtRoot` (skip strings) remplace `indexOf`. `HP.lex "let x"` → `(TCons (TSymTok "let") ...)`. 13/13 `test_eval`, 7/7 `test_meta_if`. Tag `g38-resolved`.



> **Vérifié 2026-11-02 après [32] :** `λ`/`fn` marchent maintenant (cf. G.39). `let` échoue toujours (`(HP.parse_file (HP.lex "(let x 5 x)"))` retourne un thunk non forcé).

> **Mise à jour 2026-11-02.** `[16]`→`[32]` dans `engine_expr.zig` a
> débloqué 14 tests (`test_eval` 4, `test_meta_if` 10) : les clauses
> `VClosure`/`VRecClosure`/catch-all de `eval_apply2` (17-19) et les
> cascades `EApply` de `parse_if` étaient silencieusement droppées.
> Une partie des `ArityMismatch` attribués à ce piège venait en fait
> de `[16]`, pas du parser. Les limitations restantes (listées
> ci-dessous) sont vérifiées après `[32]`.

Découvert 2026-10-30 (session heaven_eval). `HP.parse_file` sur
`(lambda x x)` ou `(let x 5 x)` ne force pas le thunk (s'affiche brut)
ou lève `UnboundVariable`/`ArityMismatch` (Zig, pas `VErr`).

Contournement : AST hardcodé (`HP.ELambda`, `HP.EApply`, ...) ou
primitives sans keywords (`+`, `cons`, `string_concat`).

**À investiguer** (session parser) : `lex_loop`/`parse_file` doivent
forcer l'évaluation et accepter les keywords comme symbols.

Voir aussi : G.37 (1 token → ENil), ch. 39 selfhosting.

### G.39 — `λ`/`fn` dans un string littéral `.hvn` → ArityMismatch [RESOLU 2026-11-02]

> **RESOLU par [32]** : `HP.parse_file (HP.lex "(λ x x)")` produit maintenant `(ECons (EApply (EApply (ESym "λ") (ESym "x")) (ESym "x")) ENil)`. Le problème n'était pas le host parser mais les clauses `VClosure`/`VRecClosure` droppées par `[16]`. `test_eval` 13/13, `test_meta_if` 7/7.

> **Mise à jour 2026-11-02.** `[16]`→`[32]` dans `engine_expr.zig` a
> débloqué 14 tests (`test_eval` 4, `test_meta_if` 10) : les clauses
> `VClosure`/`VRecClosure`/catch-all de `eval_apply2` (17-19) et les
> cascades `EApply` de `parse_if` étaient silencieusement droppées.
> Une partie des `ArityMismatch` attribués à ce piège venait en fait
> de `[16]`, pas du parser. Les limitations restantes (listées
> ci-dessous) sont vérifiées après `[32]`.

Découvert 2026-10-30 (session parser). Le parser tree-sitter de Heaven
(qui parse le `.hvn` de test) intercepte `λ`/`fn` **même dans une
string** `"...((λ x x)...)"` → `error.ArityMismatch` (Zig, avant
l'éval).

`HP.lex`/`parse_file` marchent pourtant correctement sur ces mots
(testé via `HP.lex "(λ x x)"` → tokens corrects). C'est le parser
**de l'hôte** (le `.hvn` qui contient la string) qui chie.

Conséquence : tester `heaven_eval` sur `((λ x x) 5)` via `heaven run
/tmp/test.hvn` échoue. Contournement : AST hardcodé
(`HP.ELambda`, `HP.EApply`) ou parens sans keywords (`((+ x 1) 5)`).

Voir aussi : G.37, G.38, ch. 39 selfhosting.

### G.40 — `\"` n'est pas un escape valide

Découvert 2026-11-02 (test web_ontology). `(string_length "\"")` échoue
avec `error.UnboundVariable`.

**Cause identifiée 2026-11-02 (soir)** : `expr.zig::nativeToSExpr` (appelé
par `ExprParser.parseExpression` pour toute entrée non-`(`) convertit la
string en S-expr sans tenir compte des escapes. `"\""` devient un token
splitté, le check littéral (`sexpr[0] == '"' and sexpr[len-1] == '"'`)
ne matche jamais.

**Fix** : session dédiée dans `expr.zig::nativeToSExpr` (skip_next dans
le tokenizer). Contournement : `@char_string 34` (le byte `"`).

    q _ = @char_string 34
    s = (string_concat "a" (string_concat (q 0) "b"))  -- a"b

Pour tester des strings avec `"` (JSON, HTML), utiliser `@char_string 34`
ou `string_of_bytes` sur un buffer construit. Voir aussi G.28 (thunk
top-level : `raw = ...` doit être `raw _ = ...`).

### G.41 — Int args = `.lit`, pas `.int`

Un entier en argument d'appel est taggé `.lit` dans l'AST, **pas**
`.int`. `Node.payload` vaut alors `0` (inutilisable), et la valeur
est dans `store.lits.items[node.aux].int`.

    // FAUX : node.payload = 0 pour un .lit
    .int => bufPrint("{d}", .{node.payload}),   // produit "0"

    // FAUX : Node n'a pas de champ .int
    .int => bufPrint("{d}", .{node.int}),        // ne compile pas

    // CORRECT : lire le littéral via aux
    .lit, .int => bufPrint("{d}", .{store.lits.items[node.aux].int}),

**Coût réel** : 3 fausses pistes avant la trace (`payload`, `node.int`,
mauvais chemin `lits[aux].int`) sur l'implémentation Prolog magic
(`8ea2f05`). Le fix a pris 30 s après un `platform.debug.print` du tag,
payload et aux de chaque arg.

**Règle** : pour lire un int arg, toujours passer par
`store.lits.items[node.aux].int`, jamais `payload`. Le piège vaut
au-delà de Prolog (kanren query avec int, bridge C, etc.).


### G.42 — `git add` avec chemin inexistant échoue TOUT l'add

Si un `git add` liste plusieurs fichiers et qu'un seul n'existe pas
(souvent après un `git mv`), tout l'add échoue silencieusement.
Vérifier après chaque add :

    git status --porcelain | grep '^??'

Si un fichier attendu apparaît en `??`, l'add a raté. `git add -f` s'il
est gitignored, ou corriger le chemin.

Cas vécu 2026-11-03 : scripts/test_all_hvn.sh et test_all_hvn_known_fails.txt
restés untracked sur 97805a6 et c3f54b3, commités seulement avec `git add -f`.

### G.43 — `infix_migrate.py` : bug `needs_parens` partiellement réparé

**Contexte** : `scripts/infix_migrate.py` transforme `(f x (+ y z))`
en `f x y + z`, qui parse comme `(f x y) + z` au lieu de `f x (y + z)`.

**Fix 2026-11-04 (commit `2e0db77`)** : `needs_parens` étendu + wrap
systématique des opérateurs (`(a op b)`) et `if`/`let` (`(if c then a else b)`).
`unparen_rhs` autorise digit/paren en début d'expression.

**Validé sur** :
- `core/std/list.hvn` (P1a, `2e0db77`) : 99 lignes, 4 tests verts
  (list 50/50, propagator 27/27, kanren 18/18, bigint 28/28).
- `core/std/{base,eq,ord,option,pair}.hvn` (P1b, `11c4cce`) :
  5 fichiers, 21 lignes changées, tests verts (base 15/15, eq 5/5,
  ord 14/14, option 16/16, pair 7/7).
- 4 tests minimaux : `(+ 1 2)`, `(if ...)`, `else (if ...)`,
  `(lex_loop s (+ i 1) acc)` — tous produisent du code qui parse.

**Total migré** : 6 fichiers `core/std/*` (list + 5).

**NON résolu sur `lib/heaven_parse.hvn`** (500 lignes, 10 `if` imbriqués) :
migration casse `test_selfparse` (2/3), `test_eval` (9/13),
`test_meta_if` (2/7). Rollback définitif (`541044f`, `f218117`).
Pattern exact du bug **non identifié** — les 4 tests minimaux passent,
donc c'est un cas spécifique à `heaven_parse` (probablement
`unparen_rhs` qui strippe trop dans les constructeurs à argument
parenthésé, ou `string_substring` avec args imbriqués).

**Règle** : `infix_migrate.py` est sûr pour les fichiers simples
(`core/std/*.hvn` courts, `lib/*.hvn` sans `if` imbriqués > 3 niveaux).
Pour les fichiers complexes, migrer à la main ou laisser en S-expr.

**Ne PAS** relancer sur `lib/heaven_eval.hvn` ni `lib/heaven_parse.hvn`.


