# Summary

> **Heaven 0.5** — État au 2026-10-21. Voir [Versions](#versions) en fin
> de page pour la grille complète.

## Partie I — Découverte (lecteur littéraire bienvenu)

- [Pourquoi Heaven ?](00-pourquoi-heaven.md)
- [Essayez le REPL](00b-repl.md)
- [Applications](00c-apps.md)
- [Starting Out](01-starting-out.md)
- [Believe the Type](02-believe-the-type.md)
- [Syntax in Functions](03-syntax-in-functions.md)
- [Hello, Recursion!](04-recursion.md)
- [Higher-Order Functions](05-higher-order.md)
- [Effects](06-effects.md)
  - [Effets réseau](06b-effects-network.md)
- [Streams](07-streams.md)
- [Proofs and Theorems](08-proofs.md)
- [Real World](09-real-world.md)
- [Modules et imports](10-modules.md)
- [Knowledge et raisonnement](11-knowledge.md)

## Partie II — Pratique et écosystème

- [BigInt](12-bigint.md)
- [Concurrence coopérative](13-concurrency.md)
- [Réseau](24-reseau.md)
- [Stdlib — HTTP, réseau, FS](25-stdlib-net-http.md)
- [Validation](23-validation.md)
- [QTT — gestion de la mémoire](26-qtt.md)

## Partie III — Théorie et abstraction

- [Schémas de récursion](14-recursion-schemes.md)
- [Optiques](15-optiques.md)
- [Free monads](16-free-monads.md)
- [Catégories](17-categories.md)
- [Algèbres](19-algebres.md)
- [HKT](20-hkt.md)
- [CAS et E-Graph](21-cas.md)
- [HoTT, HITs, Univalence](22-hott.md)

## Partie IV — Sous le capot (référence technique)

- [Under the Hood](18-under-the-hood.md)

---

- [Changelog du langage](./CHANGELOG.md)

## Annexes

- [A — Syntaxe complète](A-syntaxe.md)
- [B — Erreurs courantes](B-erreurs.md)
- [C — Glossaire](C-glossaire.md)
- [D — Contribuer](D-contribuer.md)
- [F — Références](F-references.md)

---

## Versions

| Version | Contenu | Statut |
|---|---|---|
| 0.1 | Parser, eval, types de base | historique |
| 0.2 | Types dépendants, kernel, proofs | historique |
| 0.3 | HKT V1a, optics, fantasy_land, MPST V0.5 | historique |
| 0.4 | stdlib net (IP/TCP/UDP/DNS/HTTP), TLS FFI, effects, QTT parse | historique |
| **0.5** | **`lib/syscall/`, `lib/time`, `lib/random`, `lib/json_rpc`, `lib/lsp/` (4 modules), `lib/mcp/` (5 tools), `lib/web/` (DBpedia live)** | **ACTUEL** |
| 0.6 | Fix `let+recursion`, loop MCP persistant, `web_lookup` 6e tool | prochain |
| 0.7 | QTT runtime (`linear` enforced), HKT rank-2 | à planifier |
| 1.0 | HoTT/Cubical, auto-hébergement complet | vision |

> **Partie I** = découverte narrative (littéraires bienvenus).
> **Partie II** = ce qui marche aujourd'hui dans l'écosystème `.hvn`.
> **Partie III** = théorie et abstraction (math dense, à lire après la pratique).
> **Partie IV** = référence technique du compilateur.
