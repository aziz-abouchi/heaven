# handle_rec / effects — état (MAJ 2026-11-05)

**Statut** : V0 **fonctionnel**, CI-verrouillé. La spec `_effects.md` (2026-10-20)
décrit encore l'ancien mécanisme (`handle` V0, `last_performed`) — elle n'est
**pas** à jour pour `handle_rec`. Ce fichier complète `_effects.md` §18.

## Ce qui existe (prouvé)

- `handle_rec` : `(handle_rec body handler init)` — 3 args, `body` paramétré
  par l'état, `handler : (lambda v k -> ...)`, `k` = continuation.
- `perform "label" val` : émet un signal, capturé par le handler le plus
  proche (pile `prompts`).
- **Imbrication** : `(handle_rec outer (handle_rec inner ...))` fonctionne.
  Test `tests/test_effects_rec_nested.hvn` (67 l., 4 scénarios).
- **Abandon** : ne pas appeler `k` = `throw` (abandonne le calcul).
- **`stdlib/effects.hvn`** (31 l.) : expose `resume k v = (k v)` pour la
  lisibilité. Les magics (`handle_rec`, `perform`, `yield`) ne sont **pas**
  réexportés par `import "X" as E` — appel direct obligatoire.
- **`@prompt` / `@throw`** : continuations délimitées. `test_continuations.hvn`
  (15/15), `test_prompt_depth.hvn` (13/13).

## Ce qui reste (spec `_effects.md` §18 à écrire)

- **Sémantique deep vs shallow** : non décidée. `handle_rec` est ni l'un ni
  l'autre — c'est un mécanisme ad-hoc one-shot.
- **Multi-shot** : non testé, non garanti. Tous les tests appellent `k` **une
  fois**. Ne pas parier dessus.
- **`handle` (V0)** : expérimental, single-slot `last_performed`, sans
  continuation. Ancêtre de `handle_rec`. **Ne pas utiliser.**
- **D8** (mécanique générale de suspension) : futur, non implémenté.

## Décision 2026-11-05

- `handle_rec` est **stable** pour usage one-shot + imbrication. C'est la
  primitive réelle.
- `handle` reste documenté comme **expérimental** — pas de consolidation
  prévue (le temps est investi ailleurs).
- Deep/shallow : **non prioritaire**. Attendre un cas d'usage réel.

## Références

- `docs/spec/_effects.md` (303 l., §1-17 obsolètes pour `handle_rec`, §18 à ajouter)
- `docs/book/src-v2/18-handlers.md` (234 l., chapitre pédagogique)
- `stdlib/effects.hvn` (31 l.)
- `tests/test_effects_rec.hvn` (4/4), `test_effects_rec_nested.hvn` (4 scénarios),
  `test_continuations.hvn` (15/15), `test_prompt_depth.hvn` (13/13)
- `src/core/engine_expr.zig:187-350` (PendingCapture, prompts, scheduler)
