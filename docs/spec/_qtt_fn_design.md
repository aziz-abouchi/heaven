# QTT fn/params — décision syntaxique (2026-11-10, session 47)

**Statut** : décision prise.
**Sujet** : syntaxe pour QTT sur les paramètres de fonction.
**Décision** : Option A, mot-clé nu `linear` / `erased` / `many`.

## Contexte

`_runtime_gaps.md:1502` (session 40) documentait 3 options. Le
diagnostic Session 46 a confirmé que QTT fn n'est pas implémenté :
`(linear x)` en pattern de paramètre est lu comme un ctor
`linear(x)`, pas comme un modificateur QTT.

## Options évaluées

| Option | Syntaxe | Avantages | Inconvénients |
|---|---|---|---|
| A (`linear!`) | `fn f (linear! x)` | Zéro ambiguïté | Nouvelle syntaxe `!` |
| A' (`[]`) | `fn f [linear x]` | Sémantique "scope QTT" | Conflit avec patterns liste `[a,b]` |
| **A (nu)** | `fn f (linear x)` | **Cohérent avec `let linear x`** | Conflit ctor `linear(x)` |
| B (postfix) | `fn f(x) linear` | — | Non conventionnel |
| C | Ne rien faire | Zéro changement | Contredit ch.29 |

## Décision retenue : Option A, `linear` nu

Mot-clé **nu** `linear` / `erased` / `many` en position de pattern
de paramètre de `fn`. Exemples :

    fn f (linear x) = x + 1
    fn g (erased proof) = 42
    fn h (many xs) = map g xs

**Réservation contextuelle** : `linear`, `erased`, `many` sont des
mots-clés réservés **uniquement en position de pattern de paramètre
de `fn`**. Un constructeur `linear(x)` reste possible hors de ce
contexte (par exemple `let y = linear x in ...`). Le parser
distingue les deux par contexte.

**Justification** :
- Cohérence avec `let linear x = v in body` (déjà supporté)
- Pas de nouvelle syntaxe (`!`, `[]` inédits)
- Conflit résolu par réservation contextuelle

## Implémentation (Session 48+)

Le parser doit, en position de pattern de paramètre de `fn` :
1. Détecter `linear` / `erased` / `many` en tête de pattern
2. Les traiter comme modificateurs QTT (pas comme ctor)
3. Construire `paramQTT(name, kw)` au lieu de `param(name)`
4. Étendre l'erasure runtime (déjà fonctionnel pour `let`, à
   propager aux paramètres)

Effort estimé : 1-2 sessions (parser + tests + propagation runtime).

## Impact

- `29-memoire.md` ch.29 : QTT « pour tout » (let + fn) devient
  vrai après impl.
- Différenciateur unique (Rust : pas de QTT, Idris2 : QTT mais
  pas EGraph, Lean4 : dependent mais pas QTT).

## Voir aussi

- `_runtime_gaps.md:1502` (contexte original, session 40)
- `_qtt_bindings_bugs.md` (3 bugs de pipeline `let`, session 46)
- `29-memoire.md` (chapitre livre)
