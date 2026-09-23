# tests/experimental/

Fichiers `.hvn` qui dépendent de fonctionnalités **non encore implémentées**.
Ils sont **exclus** de `heaven --run-tests tests/` (qui ne parcourt que les
fichiers `.hvn` du dossier racine, pas les sous-dossiers).

Conservés comme spécimens — ce sont des cas d'usage cibles qui serviront
de critères de validation quand les fonctionnalités correspondantes seront là.

| Fichier | Dépend de | Statut |
|---|---|---|
| `01_types.hvn` | CIC (`Type(0)`, `refl Type`) non branché au shell | 🚧 |
| `02_recursion_tco.hvn` | `let rec`, TCO | 🚧 |
| `03_streams.hvn` | `Stream.cons`, `thunk` (paresse) | 🚧 |

Voir `docs/ROADMAP.md` pour les chantiers correspondants.
