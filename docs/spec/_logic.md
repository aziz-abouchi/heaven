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
