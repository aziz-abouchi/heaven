<!-- HEAVEN:http-fullstack-plan -->
# HTTP fullstack Heaven — remplace D9 (plan 2026-10-19)

## Décision

Remplacer D9 (découpler Vessel de Matrix) par : **stack HTTP
entièrement Heaven**, sans bridge.zig sur le chemin HTTP.

## Constat réel (vérifié 2026-10-19)

`_vessel_decouple.md` (inventaire D9) sous-estimé :
- 14/16 routes Vessel : aucune dépendance Astra.
- 2 routes couplées : /telemetry (Matrix + net2.known_peers) et
  LSP didSave (syncMatrixWithFile).
- `core/http_server.hvn` existe déjà : handle_request/handle_api
  (via @egraph_snapshot, magic Store, déjà Heaven).
- `bridge.zig` (474 l.) = couplage Matrix + net2 pour les 2 routes.

## 5 étapes

### E1 — telemetry_store (1-2h)
`src/vessel/telemetry_store.zig` : génère JSON depuis `expr.Store`
au lieu de `matrix`. Champs : node_count, symbol_count, nodes
(tag/payload/aux). Peers via `net2.known_peers` conservés.
Testable isolément.

### E2 — handleLsp didSave (1h)
`heavenIngestSource(path, source)` = `heaven.eval(source)` +
stats. Remplace `syncMatrixWithFile`. Le Store est peuplé par
l'éval, le dashboard lit le Store.

### E3 — Bascule bridge.zig (30 min)
`serveTelemetry` -> `telemetry_store`. `handleLsp` -> `heavenIngestSource`.
Supprimer `import matrix_lib`, `import autofab_lib` du bridge.

### E4 — Bascule main.zig (30 min)
`src/main.zig` appelle `http_serve` (core/http_server.hvn) au lieu
du bridge pour les 14 routes statiques + /api/egraph.

### E5 — Move Astra vers legacy (15 min)
`matrix.zig`, `matrix_bridge.zig`, `autofab.zig` -> `src/legacy/`.
D1 complète (Astra hors du chemin runtime).

## Effort total : 4-5h, 1 session longue.

## Ce qui ne change pas
- 14 routes statiques (IDE, REPL web, frames, assets).
- `@egraph_snapshot` (déjà Heaven).
- `bridge.zig` peut rester pour TCC/IDE hors HTTP.

## Dettes résiduelles
- LSP `didSave` : hors-scope (IDE couplé, à traiter séparément).
- `net2.known_peers` : conservé, couplage réseau Vessel/Scut.

---

## Etat 2026-10-19

- **E1** : DONE. `src/vessel/telemetry_store.zig` livre, cable au CI
  (`test_telemetry_store`). Commit `e65dc66`.
- **E2** : DONE (implicite). Le helper `heavenIngestSource` n'a pas
  ete extrait en fonction nommee : le pattern est repris inline
  dans E3b (read + splitStatements + heaven.eval loop). Refactor
  eventuel si E4 le reutilise.
- **E3a** : DONE. `serveTelemetry -> telemetry_store.render`, store
  plombe `WebBridge.store: *expr.Store`. Commit `0bdc6e9`.
- **E3b** : DONE. `didSave -> Heaven.eval` (read + split + eval
  loop). `WebBridge.heaven: *Heaven` remplace `.store`. Accesseur
  `Heaven.getStore()`, `splitStatements` passe pub.
  `syncMatrixWithFile` (stub) n'est plus appele par bridge.
  Commit `00e1475`.
- **E3c** : DONE. Dedup `heaven_expr`/`heaven_expr_mod`, retire
  `main_mod` orphelin de bridge. Commit `584e5e2`.
- **E4** : TODO. Reestimation : **1-2 sessions de conception**, pas
  "30 min". Blocages identifies :
  1. `stdlib/net/http.hvn` n'a pas de serveur (0 match `serve|
     listen|accept|recv`). Il faut un `http_serve` en `.hvn`.
  2. JSON-RPC en `.hvn` : objets maintenant OK (H1/H2 clos), mais
     ni `encode_jsonrpc` ni `decode_jsonrpc` n'existent.
  3. `@embedFile` n'existe pas en `.hvn`. Decision a poser : soit
     statiques en Zig (seul `/api/*` porte en `.hvn`), soit
     `fs.read_file` + manifest.
  Voir `_vessel_decouple.md` pour le decoupage E4a/E4b.
- **E5** : TODO. matrix/autofab/matrix_bridge -> `src/legacy/`.
  6 usages residuels de `self.matrix` dans `bridge.zig` (`/graph`,
  `/rules`, `/bob`...). Apres E4.

## E4-D (routing HTTP en .hvn) -- cutoff 2026-10-19

**Fait** :
- `http_server.hvn` v0 (commit `2c35724`) : serveur multi-client,
  repond "hi" a toute requete. 10 lignes.
- `parse_request` ✓ 4/4 (teste).
- `fs_read_public` ✓ (test mal ecrit, mais la fonction marche).
- `format_response` : test exact KO mais probablement OK (a
  verifier via curl).
- `string_ends_with` : n'existe pas dans `stdlib/string.hvn`.

**Blocage E4-D2 (routing v1)** : construire la reponse HTTP avec
Content-Type + body + Content-Length en `.hvn` **sans let chain
dans les helpers** force a dupliquer
`(do_path (H.req_path (H.parse_request raw)))` 3 fois, ce qui est
illisible et fragile. Un essai a ete rollback.

**Deux approches pour une session fraiche** :

1. **Helpers separes + passage d'arguments** :
       do_parse raw _ = (H.parse_request raw)
       do_path_of req _ = (do_path (H.req_path req))
       do_mime_of path _ = (do_mime path)
       do_body_of path _ = (FS.fs_read_public path)
       do_respond client req _ = (seq (@net_write unit client
         (do_http_response (do_path_of req 0) (do_body_of (do_path_of req 0) 0) 0))
         (@net_close unit client))
       -- 6 petites fonctions, pas de let chain.
    Verbeux mais lisible.

2. **Ajouter `let` chain dans `do_*` helpers** : tester si
   `do_path req = (let p = ... in ...)` marche apres `is_command`
   fix. Si oui, factoriser.

3. **Faire le routing en Zig** (garder `bridge.zig` pour les
   statiques), et n'utiliser `http_server.hvn` que pour /telemetry
   (une seule route, pas de Content-Type lookup).

**Reco** : approche 1 (6 fonctions plates), session fraiche.
C'est 30 lignes de .hvn, testable avec curl.

**E4c-B (magic @telemetry_json)** : bloque par le module
`telemetry_store` non importable depuis `engine_expr`. Approche :
ajouter un module `telemetry_store` dans `build.zig` (3 lignes),
ou callback depuis `Heaven`. Session fraiche.

**E4-final (suppression Vessel Zig)** : apres D + E4c-B.

**Etat** : `http_server.hvn` v0 shippe, prouve que le serveur
multi-client en Heaven pur marche. Le routing demande 1 session.

## E4-D2bis (routing v1) -- cutoff 2026-10-19 (fin de session)

**Contraintes parser identifiees** (diagnostic chirurgical) :

| Pattern | Resultat |
|---|---|
| `string_eq` en condition d'`if` dans helper local | SIGSEGV |
| `string_eq` importe qualifie (`S.string_eq`) idem | SIGSEGV |
| `==` infixe en condition d'`if` | OK |
| `string_ends_with` en condition d'`if` | SIGSEGV |
| `>` en condition d'`if` | OK |
| let-chain 2 niveaux dans helper | OK |
| let-chain >= 3 niveaux dans helper | valeur fausse (5 au lieu de 6) |
| Chaîne de helpers (a->b) ordonnee (b avant a) | OK |
| Chaîne de helpers avec forward ref (a->b, a avant b) | KO (mauvaise branche) |
| 3-arg helper + 2 lets | OK |

**Ce qui marche en theorie** : `==` infixe, `>`, let-chain 2, ordre
helpers, 3-arg. Mais la v1 (30 lignes, 8 helpers, chaine
`do_handle -> do_final -> do_file -> do_path_to_file` + `do_build`
+ `do_mime`) a produit `InvalidSyntax` x3 + `ArityMismatch` sans
curl de succes. Un seul essai, rollback.

**Raison probable** : `H.parse_request raw` (import qualifie sur
`
` request) peut etre affecte par le bug `string_eq` sous-jacent
(`string_split` utilise peut-etre `string_eq`). Pas investigate.

**Prochaine session** :

1. Diagnostiquer le SIGSEGV `string_eq` (probablement le fix
   debloque tout E4-D2).
2. `parse_request` importe sur raw (test `raw = "GET / HTTP/1.1\r\n\r\n"`).
3. Puis v1 par etapes : une seule route (`/` -> index.html), curl,
   commit. Puis `/foo.css`, commit. Puis general.

**http_server.hvn v0** (commit `2c35724`) reste le serveur shipped.
Test : `curl http://127.0.0.1:8080/` -> "hi". 24 commits pousses
dans la session, v0 est un jalon propre.

## E4-D2bis DONE (2026-10-20)

**`http_server.hvn` v1** livre, commit `a_venir`. Serveur HTTP en
`.hvn` pur avec routing statique (mime, path, build, send).

**4 curls OK** : `/`, `/common.css`, `/repl.html`, `/heaven.wasm`.

**Contraintes parser respectees** :
- `if (string_ends_with p ".css") then ...` (infixe) -- OK apres
  fix `parsePostfix .str` (commit `bb2b725`).
- `let resp = ... in seq (...)` (1 let par helper) -- OK.
- Helpers ordonnes (definis avant usage) -- OK.
- `string_ends_with` retourne Bool -- fix `0ada8a0`.

**Ce qui reste (E4-final)** :
- E4c-B : `@telemetry_json` magic (module `telemetry_store` non
  importable depuis `engine_expr`, approche build.zig).
- Bascule `main.zig` -> `heaven.eval("(serve_listen 8080)")`.
- Suppression Vessel Zig (routes statiques historiques).

