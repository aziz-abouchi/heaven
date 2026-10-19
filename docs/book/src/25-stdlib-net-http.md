# Stdlib — HTTP, réseau, FS

Ce chapitre montre ce qui **marche aujourd'hui** (testé en CI)
et ce qui est **la cible** (streams + effets algébriques).

État au 2026-10-19 : parsers HTTP testés 7/7, `http_get` (le vrai
fetch) cassé par le bug B3 (let-chain dans helper), serveur HTTP
idem. Voir §6.

## 1. Parsing HTTP (testé)

`stdlib/net/http_client.hvn` fournit trois fonctions testables
sans réseau :

    http_parse_status raw      -- "HTTP/1.1 200 OK" -> 200
    http_parse_body raw        -- "...\r\n\r\nhello" -> "hello"
    http_build_get host path   -- construit la requête GET

Exemple :

    test "parse_200": (http_parse_status "HTTP/1.1 200 OK") == 200
    test "parse_404": (http_parse_status "HTTP/1.1 404 Not Found") == 404
    test "body_hello": (http_parse_body "HTTP/1.1 200 OK\r\n\r\nhello") == "hello"

Côté serveur, `stdlib/net/http.hvn` fournit :

    parse_request raw          -- -> (pair method (pair path nil))
    req_method req / req_path req
    format_response (pair 200 (pair body nil))

      -- -> "HTTP/1.1 200 OK\r\nContent-Length: N\r\n\r\n<body>"

Les deux parsers sont utilisés dans `tests/test_http_client.hvn`
(7/7).

## 2. Client HTTP — la cible

`http_get host port path` existe dans `http_client.hvn` :

    http_get host port path =
      let sock_cap = (cap_acquire "net:socket") in
      let conn_cap = (cap_acquire "net:connect") in
      let fd = (net_connect conn_cap host port) in
      let req = (http_build_get host path) in
      let resp = (net_read read_cap fd) in ...

**Ce code ne marche pas** aujourd'hui (B3 #2 : let-chain dans un
helper, voir §6). Il est conservé comme cible. Version qui marche
en `fn`/`seq` :

    fn do_connect host port _ = (net_connect (cap_acquire "net:connect") host port)
    fn do_req host path _ = (http_build_get host path)
    fn do_write fd req _ = (seq (net_write (cap_acquire "net:write") fd req) fd)
    fn do_read fd _ = (net_read (cap_acquire "net:read") fd)
    fn do_close fd _ = (seq (net_close (cap_acquire "net:close") fd) 0)

C'est verbeux. C'est le prix de B3 tant qu'il n'est pas fixé.

## 3. Serveur HTTP — ce qui marche

Les 13 magics réseau sont **câblés** (`engine_expr.zig:2361-2551`) :

    @net_listen cap port      -- -> fd serveur
    @net_accept cap fd        -- -> fd client (bloque)
    @net_read cap fd          -- -> string (max 4096)
    @net_write cap fd str     -- -> 0
    @net_close cap fd
    @net_http_respond cap fd port body -- listen+accept+read+write+close

**Ce qui marche en isolation** (testé) :

    (@net_listen (cap_acquire "net:listen:8080") 8080)  -- -> fd 4

**Ce qui ne marche pas** : `core/http_server.hvn` (let-chains,
B3 #2 et #3). Le fichier à la racine `http_server.hvn` idem.

**Workaround `fn`/`seq`** (partiellement testé, `@net_listen` OK,
`@net_accept` non atteint à cause de l'ordre du test curl) :

    fn respond cap cl _ = (seq (@net_write cap cl "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi") (@net_close cap cl))
    fn accept cap sock _ = (respond cap (@net_accept cap sock) 0)
    fn setup _ = (seq (print "listen") (accept (cap_acquire "net:1") (@net_listen (cap_acquire "net:1") 8080) 0))

Attention : `\r\n` dans une string **casse le parse** (B2, voir
§6). Utiliser `@net_http_respond` qui formate côté Zig, ou
construire la string avec `string_concat` char par char.

## 4. FS (`stdlib/fs.hvn`)

API minimale (8 l.) :

    fs_read  cap path          -- -> string
    fs_write cap path content  -- -> 0
    fs_read_public path        -- = fs_read cap ("src/vessel/public/" ++ path)

`fs_read_public` est **restreint** à `src/vessel/public/` — c'est
une capability : si le chemin sort de ce préfixe, l'appel échoue.
C'est intentionnel (sandbox Vessel).

Exemple (testé dans `stdlib/http_body.hvn`) :

    test "read_index": (> (string_length (fs_read_public "index.html")) 100)

Pour lire hors de `src/vessel/public/`, acquérir la capability
correspondante :

    let cap = (cap_acquire "fs:read:/tmp/*") in
    (fs_read cap "/tmp/file.txt")

Note : `fs_write` n'a **pas** de variante `_public` (pas d'écriture
publique par défaut, volontairement).

## 5. La cible — streams + effets algébriques (`handle_rec`)

### Streams (chapitre 7)

`delay expr` et `force t` sont les briques de base (voir
chapitre 7). Une stream est une suite paresseuse :

    stream_nats = (cons 0 (delay stream_nats_from_1))
    -- accès : (take 3 stream_nats)

Ce mécanisme n'est **pas** couplé au réseau aujourd'hui. La cible
est de faire un serveur qui produit une stream de requêtes :

    serve stream =
      let client = (delay (@net_accept cap listen_fd)) in
      (cons (handle_one (force client)) (delay (serve stream)))

### Effets algébriques : `handle_rec`

Syntaxe réelle (testée 4/4 dans `tests/test_effects_rec.hvn`) :

    (handle_rec thunk handler init)

    -- thunk     : la computation, paramétrée par l'état
    -- handler   : (lambda val k -> ...), k = continuation
    -- init      : état initial

Exemple (compteur d'effets) :

    test "handle_rec countdown 5":
      (handle_rec
        (lambda s -> (if (= s 0) 0 (perform "tick" s)))
        (lambda v k -> (if (= v 0) 0 (k (- v 1))))
        5) == 0

Le handler reçoit `(v, k)` : la valeur de `perform` et la
continuation. S'il n'appelle pas `k`, c'est un one-shot (abandon
du reste). C'est la base des **effects**. Voir aussi :

    perform "label" val        -- émettre un signal
    @prompt_depth              -- profondeur de handlers ouverts
    @prompt / @throw           -- continuations délimitées

### Serveur cible (sketch)

    serve listen_fd = (delay (serve_step listen_fd))

    serve_step listen_fd =
      (handle_rec
        (lambda _ -> (perform "accept" ()))
        (lambda _ k ->
          (let client = (@net_accept cap listen_fd) in
            (k (@net_read cap client))))
        ())

**Ce sketch ne marche pas** aujourd'hui (let dans handler, B3 #3,
et `k` comme continuation pas câblée). C'est la cible.

## 6. Bug B3 — let-chain et pattern `_`

Trois bugs séparés, voir `docs/spec/_let_chain_bug.md` :

1. **Fixé** (`66f0b32`) : `heaven run script.hvn` avec let-chain
   top-level.
2. **KO** : let-chain dans un helper `.hvn` (`f _ = (let ... in
   let ... in body)`). C'est ce qui casse `http_get` et
   `core/http_server.hvn`.
3. **KO** : pattern `_` + `heaven run` — `helper _ = 42` puis
   `(helper 0)` -> `ArityMismatch`. **Bloque E4b** (serveur HTTP
   en `.hvn`).

### Workarounds (testés)

- **`fn` + `seq`** : `fn f _ = (seq e1 (seq e2 e3))` — voir
  `docs/tutorials/no_let_chain.md`.
- **S-expr nested** : `(let a 1 (let b 2 body))` au lieu de
  `let a = 1 in let b = 2 in body`.
- **Éviter `\r\n` dans les strings** : utiliser `@net_http_respond`
  qui formate côté Zig.

### Référence

- `docs/tutorials/no_let_chain.md` — tuto workaround complet.
- `docs/spec/_let_chain_bug.md` — diagnostic détaillé.
- `docs/spec/_handle_rec_status.md` — état effects.
