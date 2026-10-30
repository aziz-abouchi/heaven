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
