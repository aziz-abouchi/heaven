# Specification -- Serveur HTTP statique natif

**Version** : v0.2 (2026-10-09)
**Module** : `core/http.hvn`
**Statut** : fonctionnel

---

## 1. Objectif

Permettre a Heaven de servir des fichiers statiques en HTTP, sans
dependance externe (pas de libc, pas de Zig, pas de Python). Le
serveur utilise uniquement les **magics IO natives** : `raw_syscall6`,
`io_read`, `io_write`, `io_open`, `io_close`, `raw_alloc`, `raw_free`,
`memset`, `string_of_bytes`.

Cible initiale : servir `src/vessel/public/` sur `localhost:8080`.

---

## 2. Syscalls Linux x86_64 utilises

| Syscall | Numero | Args | Role |
|---|---|---|---|
| `socket` | 41 | `AF_INET=2, SOCK_STREAM=1, 0` | creer un socket TCP |
| `accept` | 43 | `sock, 0, 0` | accepter une connexion |
| `bind` | 49 | `sock, addr, addrlen` | binder au port |
| `listen` | 50 | `sock, backlog=5` | ecouter |
| `setsockopt` | 54 | `sock, SOL_SOCKET=1, SO_REUSEADDR=2, ptr, 4` | reuse adresse |
| `openat` | 257 | `AT_FDCWD=-100, path, O_RDONLY=0` | ouvrir un fichier |
| `read` | 0 | `fd, buf, n` | lire |
| `write` | 1 | `fd, buf, n` | ecrire |
| `close` | 3 | `fd` | fermer |

Note : `raw_syscall6` prend **7 arguments** en Heaven (numero +
6 args). Passer un padding `0` quand la syscall a moins de 6 args.

---

## 3. Structure d'une requete HTTP/1.1

Format recu :

    GET /egraph-viz/ HTTP/1.1\r\n
    Host: 127.0.0.1:8080\r\n
    User-Agent: curl/8.6.0\r\n
    Accept: */*\r\n
    \r\n

Le serveur ne parse que la **premiere ligne** :
- Cherche le premier espace (code 32).
- Cherche le second espace.
- Extrait le path entre les deux.

---

## 4. Structure d'une reponse HTTP/1.1

Format envoye :

    HTTP/1.1 200 OK\r\n
    Content-Type: text/html\r\n
    Content-Length: <n>\r\n
    \r\n
    <body>

Le `Content-Type` est toujours `text/html` en v0 (pas de detection
d'extension). Le `Content-Length` est calcule avec `string_length`.

Reponse 404 :

    HTTP/1.1 404 Not Found\r\n
    Content-Length: 9\r\n
    \r\n
    not found

---

## 5. API Heaven

| Fonction | Role |
|---|---|
| `http_serve unit` | point d'entree : setup + boucle infinie |
| `http_serve_loop sock` | boucle accept + handle + recurse (TCO) |
| `http_handle_one sock` | accept, read, extract, serve, close |
| `http_read_request fd` | lit 4095 bytes, retourne une string |
| `http_extract_path req` | parse `GET /path HTTP/1.1` |
| `http_normalize_path p` | `/` → `/index.html`, `/foo/` → `/foo/index.html` |
| `http_serve_file cli path` | sert `src/vessel/public<path>` |
| `http_serve_fd cli fd` | lit un fd et envoie la reponse |
| `http_build_response body` | construit HTTP 200 + body |
| `http_404 unit` | message 404 pre-formate |
| `http_mk_sa_8080 unit` | construit `sockaddr_in` (AF_INET + port 8080) |
| `http_sock_reuse sock` | applique `SO_REUSEADDR` |

---

## 6. Limitations v0

- **Port hardcode** : 8080. Modifier `http_mk_sa_8080` pour un autre.
- **Content-Type fixe** : `text/html`. Pas de detection d'extension.
- **Pas de keep-alive** : une connexion = une requete, fermeture apres.
- **Pas de route dynamique** : `/api/...` non gere.
- **Pas de requetes HTTP methodes autres que GET** : POST/PUT ignores.
- **Buffer limite** : 64 Ko pour les fichiers, 4 Ko pour la requete.

---

## 7. Tests

`tests/test_http.hvn` couvre les fonctions pures (sans socket) :
- `http_extract_path` (parse path de requete)
- `http_normalize_path` (`/` → `/index.html`)
- `http_404` (longueur exacte)
- `http_build_response` (longueur exacte)
- `http_mk_sa_8080` (bytes AF_INET + port network order)

Le serveur complet (accept/read/write) est teste **manuellement** :

    $ ./zig-out/bin/heaven run serve.hvn &
    $ sleep 8
    $ curl http://localhost:8080/egraph-viz/

---

## 8. Historique

| Version | Date | Changement |
|---|---|---|
| v1 | 2026-10-07 | hello-world hardcode (`http_resp_hello`) |
| v2 | 2026-10-09 | serveur statique (extract_path, normalize, 404, boucle) |
| v2.1 | 2026-10-09 | `SO_REUSEADDR` + fix `raw_syscall6` padding |

Commits : `a73e29f` (v2), `9ae9df5` (SO_REUSEADDR).
