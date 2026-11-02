# Moteurs logiques — architecture et responsabilités

**Date** : 2026-09-28
**Statut** : audit descriptif. D2 du `docs/DECISIONS.md`.

## Constat

Il y a **3 moteurs logiques distincts** dans Heaven, avec des
paradigmes et des consommateurs différents :

| Module | Paradigme | Taille | Consommateur principal |
|---|---|---|---|
| `core/kanren_expr.zig` | miniKanren **Store-based** (Core `Id`) | 188 l. | `heaven_expr` (langage : `fact`/`query`) |
| `logic/kanren.zig` | miniKanren **Term-based** (union `Term`) | 969 l. | shell (`run*`), pipeline `typeo`/`evalo` |
| `runtime/prolog.zig` | **Prolog** (SLD, unif. de chaînes) | 308 l. | shell (`ask`) |

Ce ne sont **pas** des duplications :
- `kanren_expr` opère directement sur le `Store` (6 primitives Core)
- `logic/kanren` opère sur des `Term` de plus haut niveau (utilisé
  par le pipeline sémantique et le shell)
- `prolog` opère sur des chaînes (résolution SLD classique)

## Le problème : nommage ambigu

Dans `build.zig`, **deux modules distincts** sont exposés sous le
même nom `"kanren"` :

- `kanren_expr_mod` (source : `core/kanren_expr.zig`) → exposé
  comme `"kanren"` pour `egraph_mod`, `heaven_expr_mod`,
  `commands_mod`, `test_he_imports`.
- `kanren_legacy_mod` (source : `logic/kanren.zig`) → exposé
  comme `"kanren"` pour les modules du shell et du pipeline
  (`runtime/shell/*`, `logic/typeo*`, `logic/evalo`, etc.).

**Conséquence** : un même `@import("kanren")` renvoie à deux
fichiers différents selon le module appelant. C'est fonctionnel
(chaque module a sa propre portée d'imports), mais c'est une
bombe à retardement : un futur contributeur qui ajoute
`@import("kanren")` dans le mauvais module obtient silencieusement
le mauvais moteur.

**Fix recommandé** : renommer l'exposition de `kanren_expr_mod`
en `"kanren_expr"` (4 endroits dans `build.zig`, 1 ligne dans
`heaven_expr.zig`). Voir ticket associé.

## Pipeline d'un fait logique

Depuis le langage (`heaven_expr.eval`) :

    fact human socrate
       │
       ▼
    evalFact() (heaven_expr.zig)
       │
       ▼
    self.kanren.assertFact(id)  ← kanren_expr.Kanren (Store-based)
       │
       ▼
    KB: ArrayListUnmanaged(Id)

Depuis le shell (`run*`, `ask`) :

    run* (parent ?x ?y)
       │
       ▼
    Shell.cmdRunStar()
       │
       ▼
    self.kanren.solve(pred, args)  ← logic/kanren.KanrenEngine (Term-based)

Deux pipelines **indépendants**. Pas de partage d'état.

## Décision D2

**Aucun refactor de fusion.** Les 3 moteurs ont des rôles légitimes
et des paradigmes incompatibles (Store vs Term vs chaîne).

**Action unique** : renommer l'exposition du module `kanren_expr_mod`
pour éliminer l'ambiguïté de nom.

D2 fermée (avec cette nuance).

## Mise à jour 2026-11-02 — tests `.hvn` + limitations

**Kanren (`core/kanren_expr.zig`, exposé comme magic `query`)** :
- ✅ `fact name arg1 ...` + `query name pat1 ...` (N args) → **18 tests verts**
  (`tests/test_kanren.hvn`, `93bcfc0`).
- ✅ Wildcard `_` et N-args : `_` = hole frais par arg
  (`core/hole.zig:50`), `unify(hole_frais, arg)` réussit — pas de
  traitement spécial dans `unify`.

**Prolog (`runtime/prolog.zig`, 368 l., SLD + unification de chaînes)** :
- ✅ Exposé au shell (`ask`).
- ✅ **Magic `@prolog_fact` / `@prolog_query` (2026-11-02 nuit, `8ea2f05`, 8/8 tests)** :
  vtable `prolog_fact`/`prolog_query` (`engine_expr.zig`, post-`query`),
  `prologFactHeavenExpr`/`prologQueryHeavenExpr` (`heaven_expr.zig`).
  - Arity 0..8 (`PrologAtom.args = [8]`).
  - Args : `.sym` → string, `.lit` (et `.int`) → `store.lits.items[aux].int`.
  - `.hole` rejeté (`InvalidInput`) — V0 strict.
  - Variables Prolog = `A-Z` strict (`isVariable`, `prolog.zig:364`).
  - Wildcard `_` en query : **non supporté** (V1 : mapper hole → `Q0/Q1`).
  - **Piège** : int args taggés `.lit` (payload=0), valeur dans
    `store.lits.items[aux].int`.

**Kanren Term (`logic/kanren.zig`, 969 l.)** :
- Utilisé par `typeo`/`evalo`, pas exposé en `.hvn`.

**Trois systèmes logiques** (kanren Store, kanren Term, prolog) avec
**API `.hvn` en place** pour Store + Prolog (2026-11-02 nuit).
Priorité : **Propagators V1** (unification egraph + kanren + ontologies).
Kanren et Prolog magic : **résolus** (18/18 et 8/8). Prolog V1
(wildcard `_`) : optionnel. Pas de dépendance bloquante.
