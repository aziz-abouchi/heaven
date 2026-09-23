# Capabilities

## Décisions de design

### Reference capabilities : **pas de Pony**

Pas d'`iso`/`val`/`ref`/`box`/`tag` en tant que types dédiés.
La discipline d'usage est portée par **QTT** :

| Pony | Équivalent Heaven |
|---|---|
| `iso` | `linear x` (exactement 1 usage) |
| `val` | défaut (implicite `many`, valeurs pures) |
| `ref` | `many` + effets contrôlés via `perform` |
| `box` | lecture seule, dérivée du contexte |
| `tag` | identité, via `sym` + cap dédiée |

Raisons : QTT est strictement plus général, cohérent avec les
6 primitives, non-effacé au niveau WASM (contrairement à Pony).

### Authority capabilities : **à implémenter**

Inspiré de Goblins (Scheme distribué), réduit à l'essentiel :

- `FsCap`    — accès fichiers.
- `NetCap`   — accès réseau.
- `SpawnCap` — création d'acteurs.
- `ClockCap` — accès horloge / temps.

Ce ne sont **pas** des redondances de WASI / Cap'n Proto, mais
les **types statiques** qui garantissent l'usage correct de ces
mécanismes runtime.

| Aspect | WASI / Cap'n Proto | Heaven caps |
|---|---|---|
| Quand | Runtime | Compile-time |
| Erreur si absent | À l'appel | Rejet du programme |
| Révocation | Non standard | `linear` cap = épuisée après usage |
| Traversée d'acteurs | Ad hoc | QTT + MPST |

## Design pressenti

1. **Capability = valeur linéaire QTT** :

linear fs : FsCap
Impossible de la copier, possible de la transférer.

2. **Enforcement sur les perform** :

perform "ReadFile" path
Le TypeChecker exige une `FsCap` en contexte. Sinon erreur.

3. **Backends** :
- **WASI** : `FsCap` = fd pré-ouvert, `NetCap` = socket pré-ouvert.
- **Cap'n Proto** : `SpawnCap` sérialisable, transmis par message.
- **Natif** : caps injectées au démarrage du REPL.

4. **Intégration MPST** : les caps sont des **labels** de session.
Un acteur Alice avec `NetCap` peut être contraint à ne parler
qu'aux acteurs déclarés dans le protocole global.

## Statut

- 🚧 Roadmap `#capabilities`.
- Trigger : quand Heaven fera du **vrai I/O** (files, réseau) en
WASM — pas avant.
- Effort estimé : 1–2 sessions.

## Historique

- Inspiration initiale (astra-core, 2026-02) : Pony + Goblins.
- Révision (heaven, 2026-09) : Pony supprimé, Goblins gardé.
