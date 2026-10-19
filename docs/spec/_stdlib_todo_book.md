<!-- HEAVEN:stdlib-todo-book -->
# TODO — Documenter la stdlib dans le livre

**Contexte** : `stdlib/` a été refactoré (phases 0-3, 5, udp, ip).
12 modules, chacun avec une responsabilité unique. `docs/STDLIB.md`
sert de référence technique. Le **livre** (`docs/book/`) ne couvre
pas encore la stdlib en tant que chapitre.

## État actuel du livre

Chapitres existants (00-11) : syntaxe, types, récursion, HOF,
effets, streams, preuves, real-world, modules, knowledge. Aucun
chapitre dédié à la **bibliothèque standard**.

## Objectif

Ajouter un chapitre `12-stdlib.md` (ou intégrer dans `10-modules.md`)
qui présente les modules de `stdlib/` avec exemples **doctest-ables**.

## Plan

### Section 1 — Vue d'ensemble
- Structure `stdlib/` (string, fs, json/, net/).
- Convention : un module = une responsabilité.
- Différence avec `core/` (primitives, prelude, http_server).

### Section 2 — `stdlib/string.hvn`
- `string_split`, `string_eq`, `string_matches_at`.
- Exemples : split une ligne CSV, comparer deux strings.

### Section 3 — `stdlib/json/`
- `json_parse` + `jv_get` sur arrays (stable).
- `json_build` (`json_obj`, `json_arr`, `json_str`, `json_int`).
- ⚠️ Mentionner la limite objects avec clés (V0).

### Section 4 — `stdlib/net/`
- `ip_to_string` (exemple : 1572395042 → "93.184.216.34").
- `udp_sendto`/`udp_recvfrom` (exemple : envoyer un ping UDP).
- `tcp`/`http` : serveur + client, exemple echo server.
- `dns` : résoudre "a.com" (exemple avec mention réseau requis).
- `http_client` : GET une URL (V0, mention limites).

### Section 5 — `stdlib/fs.hvn` + capabilities
- `fs_read_public` (V0 : scope `src/vessel/public/`).
- Capabilities : pourquoi `cap_acquire`, comment le sandbox bloque.

### Section 6 — Tests et doctests
- Chaque exemple de cette section doit être un `test "..."` valide.
- Le chapitre doit passer `python3 scripts/doctest.py` (0 warning).

## Effort

1 session. Priorité moyenne (le livre est déjà bien avancé, mais
la stdlib est invisible pour l'utilisateur actuel).

## Prérequis

- `docs/STDLIB.md` à jour (fait 2026-10-19).
- Tous les modules stdlib ont des tests (fait).
- Le doctest passe sur les chapitres 00-11 (à vérifier avant).

## Hors-scope

- Documenter `core/` (c'est le sujet d'autres chapitres).
- Documenter `lib/` (legacy self-hosting, voir roadmap métacircularité).
