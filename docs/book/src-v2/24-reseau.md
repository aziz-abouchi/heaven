# Chapitre 24 — HTTP et réseau : trois couches

> **Piège d'entrée.** HTTP n'est pas un protocole magique. C'est une
> string, trois espaces, un retour chariot — et derrière, un socket.
> Heaven traite ces trois couches séparément, et **ce chapitre montre
> ce qui est testé, ce qui marche, et ce qui est encore une cible**.
> La tentation, quand on lit les specs (`_network_osi.md`,
> `25-stdlib-net-http.md`), c'est de croire que tout tourne. Ce n'est
> pas le cas. Voici la frontière exacte.

## 1. Trois couches, une seule est magique

Un serveur HTTP en Heaven, ça tient en trois couches empilées :

| Couche | Rôle | État |
|---|---|---|
| **Parser** | string → status, headers, body, path | testé (pur, sans socket) |
| **Construire** | request/response → string | testé |
| **Servir** | string ↔ socket réel | testé en natif, v0 en Heaven pur |

La première et la deuxième sont **pures** — elles prennent une string,
rendent une string (ou un entier). Pas de socket, pas d'effet, pas
d'`import` de module système. C'est pour ça qu'elles sont faciles à
tester, et c'est ce que ce chapitre couvre en priorité.

La troisième est un **effet** — un syscall `connect`, un `read`, un
`write`. Elle est plus fragile, plus lente, plus dépendante de
l'environnement. Vous verrez.

## 2. Parser HTTP (testé, pur)

Trois modules, trois responsabilités. Tous dans `stdlib/`.

### `http_parse_status` — la ligne de statut

```heaven
import "stdlib/net/http_client.hvn" as HC

(HC.http_parse_status "HTTP/1.1 200 OK")     # => 200
(HC.http_parse_status "HTTP/1.1 404 Not Found") # => 404
(HC.http_parse_status "HTTP/1.1 500 Internal")  # => 500
```

Extrait littéral de `tests/test_http_client.hvn` (7 tests). Rien de
plus : pas de headers, pas de body, juste le code. **C'est déjà ça**,
parce qu'un parser de status correct est la fondation de tout client
HTTP.

### `http_parse_body` — le corps de la réponse

```heaven
(HC.http_parse_body "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
# => "hello"
(HC.http_parse_body "HTTP/1.1 200 OK\r\n\r\n")
# => ""
(HC.http_parse_body "A: 1\r\nB: 2\r\n\r\nX")
# => "X"
```

Le parser trouve le premier `\r\n\r\n` (double CRLF = fin des headers)
et rend tout ce qui suit. **Pas de gestion de Content-Length, pas de
chunked encoding, pas de gzip** — juste la découpe. C'est suffisant
pour un serveur statique qui renvoie du texte.

### `http_build_get` — construire une requête

```heaven
(HC.http_build_get "example.com" "/")
# => "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
```

L'inverse : on part d'un host et d'un path, on construit une requête
qu'un socket pourrait envoyer. La sortie est **déterministe** — c'est
ce qui permet de la tester sans réseau (`tests/test_http_client.hvn`,
test `build_get`).

### `extract_path` et `http_normalize_path` — côté serveur

```heaven
extract_path "GET /egraph-viz/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
# => "/egraph-viz/"
(http_normalize_path "/")      # => "/index.html"
(http_normalize_path "/foo/")   # => "/foo/index.html"
(http_normalize_path "/foo.html") # => "/foo.html"
```

`extract_path` fait le travail inverse de `build_get` : à partir d'une
requête brute (string), il extrait le path. `normalize_path` applique
la règle du web : `/` devient `/index.html`, `/foo/` devient
`/foo/index.html`, un path avec extension reste inchangé.

**Ensemble, ces deux fonctions font le boulot d'un serveur statique
minimal** : lire une requête, décider quoi servir. Sans toucher à un
socket. C'est `tests/test_http.hvn` — 32 lignes, et les 5 tests visibles
couvrent `extract_path` (2) et `normalize_path` (3).

### `body_parse` et `body_get` — POST form-encoded

```heaven
import "stdlib/http_body.hvn" as HB

(HB.body_get (HB.body_parse "a=1") "a")             # => "1"
(HB.body_get (HB.body_parse "a=1&b=2") "b")         # => "2"
(HB.body_get (HB.body_parse "name=hello&age=42") "age") # => "42"
(HB.body_get (HB.body_parse "") "a")                # => ""
```

`tests/test_http_body.hvn` (9 tests) couvre le format `application/x-
www-form-urlencoded` : pas de URL-decode, pas de multipart, mais le
cas le plus courant (formulaire simple) fonctionne. Les valeurs sont
rendues **telles quelles** — `ip=8.8.8.8` donne `"8.8.8.8"`, pas une
IP décodée.

**Bilan de la couche 1** : ~21 tests couvrent le parsing pur. On sait
lire un statut, un corps, un path, un formulaire, et construire une
requête. On ne sait **pas** gérer un header individuel, ni un corps
chunked, ni un POST multipart. Pour un serveur statique + un client
minimal, ça suffit.

## 3. Piège : parser ≠ servir

Un parser correct **ne garantit pas** un serveur correct. Voici la
frontière, en une phrase : un parser transforme une string en
structure ; un serveur transforme un socket en string, applique le
parser, puis transforme la réponse en string et l’écrit sur le socket.

Ce qui peut casser entre les deux :

- **Le socket ne rend pas une string complète.** `read` peut rendre
  100 octets, puis 0, puis 100 de plus. Un parser qui attend un
  `\r\n\r\n` doit gérer les lectures partielles — et la plupart des
  parsers du monde réel ne le font pas.
- **Le socket peut bloquer.** Un `read` sans timeout bloque le thread
  entier. `handle_rec` (ch. 16-17) ne change rien à ça — c’est un
  problème d’OS, pas de langage.
- **Le client peut se déconnecter.** Un `write` sur un socket fermé
  rend une erreur, pas une exception. Il faut la gérer.

C’est pour ça que les fonctions du §2 sont testées **sans** socket :
elles prennent une string complète en entrée. Le vrai serveur (chapitre
6 v1, `core/http.hvn`) fait le pont avec les syscalls, et c’est là que
les bugs apparaissent.

> **Capot pratique.** Quand un serveur Heaven renvoie une réponse
> malformée, 9 fois sur 10 le bug est dans le pont socket ↔ string,
> pas dans `http_parse_status` ni `http_parse_body`. Vérifiez d’abord
> que le socket a rendu *toute* la requête avant de parser.

## 4. Servir : le serveur natif `--http-serve`

Heaven embarque un serveur HTTP natif, piloté par un flag :

    $ ./zig-out/bin/heaven run serve.hvn
    # attendre ~8 secondes (chargement des modules std)
    # puis dans un autre terminal :
    $ curl http://localhost:8080/egraph-viz/

Le « ~8 secondes » n’est pas une blague — c’est le temps de chargement
des modules std au démarrage. **Le serveur est en Heaven pur** : il lit
des fichiers, construit des réponses, écrit sur un socket. Pas de libc,
pas de Zig std, pas de Python. Juste les **magics IO natives**
(`raw_syscall6`, `io_read`, `io_write`, `io_open`).

Pourquoi c’est important ? Parce que c’est **la preuve** que la
discipline « zéro dépendance Zig dans le code portable » (D-SH4) tient
sur un cas réel. Un jour, ces magics seront portés en Heaven pur à
leur tour — et le serveur sera auto-hébergé. En attendant, il rend des
fichiers, et c’est suffisant pour un site statique.

## 5. La couche basse : TCP, UDP, bitstrings

Sous HTTP, il y a des octets. Heaven les expose via deux magics et une
syntaxe :

### TCP client

```heaven
net_connect cap ip port = @net_connect cap ip port
fd = net_connect cap "1.1.1.1" 80
# fd >= 0  → succès
# fd == -1 → échec
```

`net_connect` rend un file descriptor. **Aucune dépendance Zig** : le
syscall `connect` est appelé directement via `raw_syscall`. C’est la
règle D-SH4 (zéro `std.posix` dans le code portable) appliquée à la
lettre. Le jour où Heaven sera self-hosté, ce code n’aura pas à être
réécrit.

### UDP

```heaven
net_socket_udp cap = @net_socket_udp cap
net_sendto cap fd ip port data = @net_sendto fd ip port data
```

UDP est **sans connexion**. Pas de handshake, pas de garantie d’ordre.
C’est le protocole de DNS (port 53), NTP, QUIC. Pour un langage qui
veut parler au monde, UDP est aussi important que TCP — et souvent
plus simple à implémenter (pas d’état de connexion).

### Bitstrings non alignés

Le vrai déblocage de la couche basse, c’est la capacité à parser des
en-têtes binaires **non alignés sur un octet**. Un en-tête DNS fait
12 octets avec des champs 4+4+8+16+16 :

```heaven
<<id:16, flags:16, qdcount:16, ancount:16, nscount:16, arcount:16>> = header
```

Un en-tête IPv4 est encore plus tordu — 4 bits de version, 4 bits
d’IHL, 8 bits de TOS, 16 bits de longueur totale :

```heaven
<<version:4, ihl:4, tos:8, total_len:16, ...rest:bits>> = ip_packet
```

Le parser génère des shifts et des masques pour chaque segment. C’est
ce qui permet de lire un paquet réseau en **pur Heaven**, sans appeler
de bibliothèque C. Le chapitre 5 (récursion) a déjà montré le principe
sur des cas simples ; ici, c’est la version industrielle.

> **Capot pratique.** Les bitstrings non alignés sont **testés** (voir
> `tests/test_bitstring*.hvn` — l’inventaire exact change trop vite
> pour être cité dans un livre ; regardez le repo). Ce qui **n’est
> pas testé** : un vrai paquet DNS reçu sur le réseau. La construction
> de la query est bloquée par l’absence d’escape `\x` dans les strings
> (voir `docs/spec/_string_escape_gap.md`) — workaround : `poke_byte`.
> Le chapitre suivant (24-hab) revient sur cette discipline.

## 6. Ce qui n'est pas prêt (et qu'il faut savoir)

Ce chapitre ne serait pas honnête sans une liste de ce qui **ne marche
pas encore**. Voici l'état au moment de l'écriture, tiré de
`docs/spec/_string_escape_gap.md` et de `_runtime_gaps.md` :

| Chose | État | Impact |
|---|---|---|
| **DNS pur Heaven** | bloqué par absence d'escape `\x` | workaround `poke_byte`, pas utilisable en prod |
| **HTTPS** | sandbox bloque les tests live | `lookup_label_with http_fn` testé en *mocked* uniquement |
| **WebSocket** | absent du stdlib | rien à tester, rien à documenter |
| **HTTP chunked** | non géré par le parser | un serveur qui renvoie du chunked casse |
| **POST multipart** | absent | seuls les formulaires URL-encoded marchent |
| **TLS** | dépend d'OpenSSL via FFI C | pas « zéro dépendance Zig » sur ce point |

**Règle de lecture du livre** : tout ce qui est dans le tableau ci-dessus
est *cible*, pas *état*. Si un chapitre vous dit « Heaven sait faire X »
et que X est dans ce tableau, vérifiez le code — pas la doc.

> **Capot final.** La discipline D-SH4 (« zéro dépendance Zig ») est
> **une direction**, pas un acquis. Le serveur HTTP natif la respecte ;
> TLS ne la respecte pas (OpenSSL). La cohérence du projet tient à ce
> qu'on le dit clairement, pas à ce qu'on le cache.

## Exercices

### Ex. 1 — Parser un status (guidé)

Écrivez `extract_code` qui prend une ligne de statut HTTP complète et
rend le code numérique.

```heaven
extract_code "HTTP/1.1 200 OK" == 200
extract_code "HTTP/1.1 404 Not Found" == 404
```

**Indice** : `string_index_of` + `string_substring`, comme dans
`tests/test_http.hvn`. Vous pouvez aussi utiliser
`stdlib/net/http_client.hvn` — mais l'idée est de le refaire à la main
pour comprendre. Testez les trois cas du livre (`200`, `404`, `500`).

### Ex. 2 — Body POST (libre)

Implémentez `body_get` sans `stdlib/http_body.hvn`. Prenez une string
`"a=1&b=2"`, rendez la valeur pour une clé donnée.

```heaven
body_get "a=1&b=2" "a" == "1"
body_get "a=1&b=2" "z" == ""
body_get "name=hello&age=42" "age" == "42"
```

**Question** : que se passe-t-il si la clé apparaît deux fois ? Que
se passe-t-il si la valeur contient `&` ? (Vous verrez pourquoi la
vraie stdlib ne gère ni l'un ni l'autre — c'est le piège du chapitre.)

### Ex. 3 — Normaliser un chemin (libre)

Implémentez `normalize_path` : `/` → `/index.html`, `/foo/` →
`/foo/index.html`, `/foo.html` → `/foo.html`. Testez avec
`tests/test_http.hvn` (5 cas visibles). **Question** : que fait votre
implémentation pour `/foo//` (deux slashes) ? Pour `//` ?

### Ex. 4 — Le serveur statique minimal (casse)

Écrivez un serveur en Heaven qui écoute sur `localhost:8080` et sert
`index.html` à `/` et `/index.html`. Utilisez
`stdlib/http_server.hvn` v0 (voir `25-stdlib-net-http.md` §3bis).

**Attendu** :
- `curl http://localhost:8080/` rend le contenu de `index.html`
- `curl http://localhost:8080/inexistant` rend `404 Not Found`

**Question** : que se passe-t-il si le fichier `index.html` est plus
gros que la string buffer que vous avez prévue pour `io_read` ?
(Indice : c'est exactement ce que le §3 appelle « le pont socket ↔
string ».)

---

## Ce qu'il faut retenir

1. **HTTP = trois couches** — parser (pur), construire (pur), servir
   (effet). Ne les confondez pas.
2. **Le parser est testé ~21 fois** ; le pont avec le socket l'est
   beaucoup moins. C'est là que ça casse.
3. **Le serveur natif est en Heaven pur** — preuve que D-SH4 tient
   sur un cas réel.
4. **Ce qui n'est pas prêt** est listé §6. C'est aussi important que
   ce qui l'est.
5. **La couche basse (TCP, UDP, bitstrings)** fonctionne, mais la
   construction de requêtes DNS est bloquée par l'absence d'escape
   `\x`. Workaround `poke_byte`, pas utilisable en prod.

Le chapitre suivant (24-hab) ferme la Partie III avec les acteurs OTP
et les modules distribués. Même règle : ce qui tourne, ce qui est
cible, et où est la frontière.
