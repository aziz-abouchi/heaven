# SICP lineage — Heaven as a post-SICP language (2026-11-09)

**Statut** : document de référence.
**Question** : quelle est la dette réelle de Heaven envers SICP ?
**Réponse courte** : chaque chapitre de SICP a un équivalent Heaven,
mais l'implémentation diverge là où SICP enseignait en Scheme non-typé.

## Vue d'ensemble

| SICP | Sujet | Heaven |
|---|---|---|
| Ch. 1 | Construire des abstractions (procédures) | `01-pourquoi` … `05-recursion`, `06-higher-order` |
| Ch. 2 | Construire des abstractions (données) | `08-definir-types`, `10-structures-recursives`, `12-bigint` |
| Ch. 3 | Modularité, objets, état | `17-effects`, `18-handlers`, `20-actors`, `21-otp` |
| Ch. 4 | Évaluation métalinguistique | `27-selfhost`, `28-eval`, `src/core/heaven_expr.zig` |
| Ch. 5 | Machines à registres, compilation | `src/backend/mir_qbe.zig`, `mir_wat.zig`, `wasm.zig` |

## Chapitre 1 — Abstractions par procédures

SICP : `(define (square x) (* x x))`, composition, higher-order.
Heaven : identique, mais avec **types inférés** (HM) et
**multiplicités QTT** (linear, erased, many).

    -- SICP
    (define (square x) (* x x))

    -- Heaven
    square x = x * x   -- multiplicity many (défaut)

## Chapitre 2 — Abstractions par données

SICP : `cons`, `list`, barrières d'abstraction, données comme procédures.
Heaven : `data` + pattern matching, mais **pas d'égalité automatique**
sur les types utilisateur (cf. `_h1_qualified_sym.md`). Le "data as
procedures" est remplacé par le hash-consing du store
(`expr.Store`) : deux `Cons 1 Nil` construits séparément partagent
le même Id (structural sharing, invisible à l'utilisateur).

## Chapitre 3 — Modularité, objets, état

SICP : `set!`, fermetures mutables, banques et comptes.
Heaven : **pas de `set!`**. L'état passe par les **effets
algébriques** (`perform`/`handle`) et les **acteurs**
(`spawn`/`send`/`receive`). C'est la divergence la plus nette :
SICP enseigne l'état mutable local, Heaven force la discipline
`handler`.

## Chapitre 4 — Évaluateur métalinguistique

SICP : `eval` et `apply` mutuellement récursifs, `analyze` pour la
compilation (exercice 4.1), `amb` pour le non-déterminisme.
Heaven : même architecture dans `src/core/heaven_expr.zig` (`eval`),
`src/core/engine_expr.zig` (`evalMagic`). QTT erasure joue le rôle
de `analyze` (élagage à la compilation). `amb` est remplacé par les
**effets algébriques** (`perform` + `handle_rec`).

## Chapitre 5 — Machines à registres, compilation

SICP : machine à registres explicite, chemin de compilation
Scheme → registres.
Heaven : `src/backend/mir_*.zig` (QBE, WAT, WASM). Le MIR est la
"register machine" de Heaven. La compilation est en deux temps :
`heaven → MIR → QBE/WAT/WASM`.

## Ce que Heaven ajoute (au-delà de SICP)

1. **QTT** : SICP ne type pas, Heaven quantifie.
2. **EGraph** : SICP réécrit à la main, Heaven le fait par saturation.
3. **Effets algébriques** : SICP utilise `call/cc`, Heaven `handle_rec`.
4. **Preuve vérifiée par construction** : absent de SICP.
5. **MPST, OTP, acteurs** : absents de SICP (SICP est séquentiel).

## Ce que Heaven perd (par rapport à SICP)

1. **`set!` libre** : remplacé par effets explicites — plus safe,
   moins direct pour les débutants.
2. **`call/cc`** : remplacé par effets algébriques + continuations
   (`src/core/continuation.zig`).
3. **Interpréteur en 200 lignes** : Heaven fait 96 lignes pour `eval`
   pur (`28-eval.md`), mais l'interpréteur complet fait plusieurs
   milliers de lignes. SICP reste plus pédagogique.
4. **Auto-modification** (`eval` d'une expression construite à
   l'exécution) : partiellement supporté, voir `_runtime_gaps.md`.

## Le point pédagogique

Le livre Heaven (v2) suit l'arc SICP mais avec des **types**. Pour
un lecteur qui vient de SICP, la transition est :

1. Remplacer `set!` par `perform`/`handle`
2. Remplacer `call/cc` par `handle_rec`
3. Accepter QTT sur les paramètres (souvent `many` par défaut)
4. Comprendre que `analyze` devient QTT erasure + EGraph rewrite

Voir aussi :
- `docs/book/src-v2/31-sicp.md`
- `docs/book/src-v2/28-eval.md`
- `docs/spec/_runtime_gaps.md`
- `docs/spec/_h1_qualified_sym.md`
- `docs/spec/_check_v2_plan.md` (typage des variables)
