# Audit du langage Heaven — pour spec formelle

**Date** : 2026-09-25
**Source** : dispatch `eval` dans `src/core/heaven_expr.zig` (lignes ~570-1052)
**But** : inventaire **descriptif** des formes acceptées. Base pour `docs/spec/heaven.md`.

## Méthode

Lecture ligne à ligne du dispatch `eval`. Chaque `startsWith` ou `eql` sur
`trimmed` est une **forme acceptée**. Relevé : numéro de ligne, pattern,
handler, famille.

Ce document est **descriptif** (WYSIWYG) : il décrit ce qui est accepté
aujourd'hui, pas ce qui devrait l'être. Les incohérences sont listées
en fin, dans « Écarts connus ».

## Ordre de dispatch (crucial)

Le dispatch teste les formes dans un ordre **précis**. L'ordre compte :

- `let ` (l.743) **avant** `let macro ` (l.796) → `let macro x` passe par le
  premier test, à ne pas confondre.
- `:=` (walrus, l.915) **avant** `=` (l.924) → une ligne
  `f x := body` est traitée comme une équation convertie.
- `sig ` **après** `type ` : une ligne `type ...` n'entre jamais dans `sig`.

Un réordonnancement du dispatch peut casser des cas silencieusement.

## Familles

### F1. Déclarations top-level

| Forme | Ligne | Handler | Notes |
|---|---|---|---|
| `module NAME` | 616 | ouvre namespace | `NAME` = 1er token, pas d'espaces |
| `import "path" [as Name]` | 626 | `import_mod.evalImport` | idempotent, cycle-détecté |
| `import Name` | 626 | idem | cherche `core/std/<min>.hvn` puis `core/<min>.hvn` |
| `export name1 name2 ...` | 608 | marque exports | no-op hors import |
| `strict on` / `strict off` | 717 | toggle mode | opt-in par module |
| `data T p1 p2 = C1 \| C2 args` | 904 | `evalDataDecl` | params typés ou non |
| `sig f : A -> B -> C` | 631 | enregistre signature | vérifie Π bien formé |
| `theorem N : e1 = e2` | 730 | `proof_core` | ouvre un but |

### F2. Définitions équationnelles

| Forme | Ligne | Handler | Notes |
|---|---|---|---|
| `f x = body` | 924 | `evalEquation` | équation (pattern → RHS) |
| `f x := body` | 915 | converti en `=`, puis `evalEquation` | walrus, testé avant `=` |
| `fn name arg1 ... = body` | 796 | mécanisme runtime | acteur/effet, pas clause |
| `let x = v in b` | 743 | liaision locale | **attention** au `in` requis |
| `let macro name(x) = ...` | 796 | macro hygiénique | quote/unquote |
| `let actor A = 0 with h` | 796 | spawn acteur | voir F4 |

### F3. Preuves

| Forme | Ligne | Handler | Notes |
|---|---|---|---|
| `theorem N : e1 = e2` | 730 | `evalTheorem` | statement, pas preuve |
| `prove N by tactic` | 733 | `evalProve` | applique une tactique |
| `prove N by { t1; t2 }` | 733 | bloc interactif | prompt `>` |
| `skill NAME [on x]` | 736 | `evalSkill` | théorème actif requis |

### F4. Mécanismes runtime (acteurs, macros)

| Forme | Ligne | Handler |
|---|---|---|
| `let actor A = init with handler` | 796 | spawn |
| `let macro M(x) = body` | 796 | macro |
| `fn name args = body` | 796 | handler/effet |
| `send(A, msg)` | 796 | envoie message |
| `state(A)` | 796 | lit l'état d'un acteur |
| `spawn(...)` | 796 | spawn bas niveau |

### F5. Tests

Deux syntaxes cohabitent (parens ou non) — **piège à connaître** :

| Forme | Ligne | Notes |
|---|---|---|
| `test "name": lhs == rhs` | 829 | quotes obligatoires |
| `(test "name" lhs rhs)` | 817 | form S-expr |
| `assert_eq lhs rhs` | 829 | sans parens |
| `(assert_eq lhs rhs)` | 817 | avec parens |
| `assert_err e` | 829 | sans parens |
| `(assert_err e)` | 817 | avec parens |

### F6. CAS (calcul symbolique)

| Forme | Ligne | Notes |
|---|---|---|
| `simplify e` | 861 | sans parens |
| `(simplify e)` | 866 | avec parens |
| `derive e` | 871 | var implicite `x` |
| `integrate e` | 875 | var implicite `x` |
| `solve e` | 879 | var implicite `x` |
| `expand e` | 883 | développement |
| `plot e` | 887 | var implicite `x` |

### F7. Logique (étape 1)

| Forme | Ligne | Notes |
|---|---|---|
| `fact name arg1 arg2 ...` | 896 | assert fait |
| `query name arg1 ...` | 899 | `_` = hole, compte les solutions |
| `rules` | 891 | KB comme valeur |
| `meta` | 891 | **déprécié** (voir Écarts) |

### F8. Effets

| Forme | Ligne | Notes |
|---|---|---|
| `perform "E" v` | 856 | effet algébrique |
| `handle (perform ...) h` | 856 | handler |
| `green e` | 579 | évaluation avec profilage |

### F9. Types et introspection

**Constat vérifié** (2026-09-25, lecture de `evalTypeExpr`) :

`type e` → introspection uniquement (inférence HM, retourne la string
du type). **Aucune logique d'alias** — `type age Nat` échouerait à
l'inférence (symbole `age` inconnu).

| Forme | Ligne | Notes |
|---|---|---|
| `type e` | 575 | **introspection** : string du type de `e` |
| `(relation f args)` | 856 | construit une relation |

**Note** : `type NAME T` (alias) est une feature **souhaitée mais non
implémentée** — voir `decisions.md` section 2.

### F10. Fallback générique (l.953-1052)

Trois étages, dans l'ordre :

1. **Infixe → S-expr** : `(+ 1 2)` via `nativeToSExpr`, évalué par `engine.eval`.
   Ne s'applique pas aux opérateurs (pas de `+ 1 2` sans parens).
2. **Application nom-args** : `f a b` → `(f a b)`, évalué par `engine.eval`.
   Rejeté si `f` est un opérateur (`+ - * / ^ % == != < > <= >=`).
3. **Atome nu** : `x` cherché dans `env`, sinon retourné tel quel (string).

### F11. I/O

| Forme | Notes |
|---|---|
| `print e` | depuis `core/io.hvn` |
| `readFile p` | idem |
| `readLine()` | idem |
| `writeFile p c` | idem |
| `latex e` | l.938, sortie LaTeX |

## Erreurs canoniques

Deux formats standard :

| Format | Origine | Exemple |
|---|---|---|
| `usage: <cmd> <args>` | arité invalide | `usage: module <nom>` (l.619) |
| `\u{2717} <message>` | erreur métier | `\u{2717} unknown skill: {s}` (l.1779) |

Règle : les erreurs de **parse** ou **arité** utilisent `usage:`, les erreurs
de **sémantique** utilisent `\u{2717}`.

Erreurs de test (F5) :
- `\u{2717} assert_eq failed: {s} != {s}` (l.2659)
- `\u{2717} test {s}: opérateur '==' manquant` (l.2750)
- `\u{2717} test {s}: {s} != {s}` (l.2766)

## Écarts connus

**Ces points doivent être tranchés avant une spec normative.**

1. **`meta` double-comportement.**
   - l.599 : `meta ` → retourne `"meta supprimé, utilisez rules"` (déprécié).
   - l.891 : `meta` (sans espace) → `listRules()` (fonctionnel).
   - **Incohérent** : `meta foo` et `meta` ont des comportements opposés.

2. **`type` — passthrough ou évaluation ?**
   - l.575 : `type ` → `evalTypeExpr` (retourne le type).
   - l.585 : `type ` dans `is_command` → renvoyé **tel quel** sans évaluation.
   - **Ambigu** : le premier test gagne toujours, mais `is_command` est
     un vestige.

3. **`=` vs `:=` — deux syntaxes équivalentes.**
   - l.915 : `:=` converti en `=`, puis `evalEquation`.
   - l.924 : `=` direct, mais rejeté si suivi d'un autre `=` (`==`).
   - **Décision à prendre** : garder les deux, ou déprécier l'un ?

4. **`assert_eq` / `assert_err` / `test` — double syntaxe.**
   - Parenthésée : `(assert_eq a b)`.
   - Infixe : `assert_eq a b`.
   - **Décision à prendre** : uniformiser sur une seule ?

5. **`let ` vs `let actor ` / `let macro ` — piège de préfixe.**
   - `let x = ...` (l.743) teste avant `let actor ` (l.796).
   - `let actor Counter = 0` matche-t-il `let ` ? Oui — donc il faut
     regarder le **second** token. Complexité inutile.

6. **`?` / `?-` / `ask` — trois façons pour Prolog, aucune cohérente.**
   - `?` : shell (liste les commandes).
   - `?-` : pas dans le dispatch → v2 roadmap.
   - `ask` : shell uniquement.
   - **Décision** : ajouter `?-` en langage, supprimer `ask`.

7. **`state` / `send` / `spawn` — parenthèses obligatoires.**
   - Détecté par `startsWith(trimmed, "send(")` etc.
   - `send A 5` (sans parens) → tombe dans le fallback F10 et échoue.
   - **Décision** : accepter les deux, ou documenter strictement.

8. **`(test "name" lhs rhs)` — arguments séparés, pas `==`.**
   - Parenthésée : `(test "n" a b)` (3 args).
   - Infixe : `test "n": a == b` (opérateur `==` explicite).
   - **Décision** : aligner.

## TODO Phase 2 (rédaction `heaven.md`)

- [ ] Décider descriptif vs normatif définitif (reco : descriptif).
- [ ] Rédiger EBNF complète (`grammar.ebnf`) — extraire depuis
      `expr_parser.zig` et `nativeToSExpr`.
- [ ] Documenter les 6 primitives (`lit`, `sym`, `apply`, `bind`,
      `lambda`, `relation`) + le lowering.
- [ ] Documenter chaque famille avec : forme, désucration, exemple
      exécutable (in → out), erreur canonique.
- [ ] Trancher les 8 écarts ci-dessus → migrer les décisions dans une
      section « normatif ».
- [ ] Test de validation : donner la spec seule à un LLM, lui demander
      de générer 5 programmes Heaven, vérifier qu'ils compilent.


## Chantiers identifiés non planifiés

### Test skippé : `syntax HIR — vector literal`

**Fichier** : `src/syntax/lower_test.zig:139`
**Statut** : skip inconditionnel (`if (true) return error.SkipZigTest;`)
**Plan déjà écrit dans le code** (4 étapes) :
1. Ajouter `Expr.range` à `syntax/ast.zig`
2. `syntax/lower.zig` : nœud Tree-sitter `range` → `Expr.range`
3. `syntax/core_lower.zig` : `Expr.range` → `apply(sym("range"), lo, hi)`
4. Tester `let v = 1..3` (pas `[1-3]`, invalide Tree-sitter)

**Note** : concerne le pipeline syntax (Tree-sitter, IDE/shell),
**pas** le pipeline natif (Heaven REPL). Ne pas confondre avec
le type dépendant `Vec` (v2d/v2e), qui utilise `nativeToSExpr`.

**Effort** : 1 session dédiée. Non prioritaire.


### `unlower` — infrastructure dormante

**Fichier** : `src/core/expr.zig:1210`
**Statut** : implémenté pour les **6 primitives** (lit, sym, bind,
lambda, apply, relation). Consommé uniquement par 2 tests dans
`mir.zig` — **jamais appelé en production**.

**Couverture** : exhaustif pour le Core. Les tags frontend
(`.vector_lit`, `.sum`, `.letrec`, `.if` sous forme `apply(sym("if"))`)
ne sont pas reconnus — `unlower` retourne `.call` générique pour eux.

**Cas manquants identifiés** (si on veut étendre) :
- `.letrec` (dans Tag mais pas dans le switch)
- `.hole`, `.evar` (à vérifier dans Tag)
- Reconnaissance `apply(sym("if"), ...)` comme variant conditionnel
- Reconnaissance `tuple`, `block`, `seq`

**Chantier futur** : brancher `unlower` dans `mir.compileExpr` (ou un
backend codegen) — c'est la vraie finalisation. ~1-2 sessions.
