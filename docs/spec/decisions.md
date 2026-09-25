# Décisions — spec formelle du langage Heaven

**Date** : 2026-09-25
**Statut** : **à valider par l'auteur du langage.**
**Source des écarts** : `docs/spec/_audit.md`, section « Écarts connus ».

Chaque écart identifié reçoit une recommandation. L'auteur valide,
corrige ou rejette. Une fois validées, ces décisions servent de base
à `heaven.md` (Phase 2).

## Format

- **Décision** : la règle cible.
- **Justification** : pourquoi ce choix plutôt qu'un autre.
- **Migration** : ce qu'il faut changer dans le code ou les tests.
- **Effort** : coût estimé.

---

## 1. `meta` — double-comportement

**Décision** : **Supprimer `meta` complètement**.

**Justification** : `rules` est déjà l'alias officiel (STATUS, COMMANDS.md).
`meta` sans argument fonctionne (via `listRules`), `meta foo` renvoie
« meta supprimé ». Deux comportements pour une même racine = source de
bugs et de confusion. Un langage propre n'a qu'une façon de nommer une
chose.

**Migration** :
- `heaven_expr.zig` : retirer `meta` du `eql` ligne ~891 (garder `rules`).
- Ligne ~599 : supprimer la branche `meta ` (le message « meta supprimé »
  n'a plus lieu d'être si `meta` n'est plus un cas spécial).
- COMMANDS.md : retirer toute mention de `meta`.
- `test_suite.hvn` : vérifier qu'aucun test n'utilise `meta`.

**Effort** : 10 min.

---

## 2. `type` — passthrough vs évaluation

**Décision** : **Garder `type e` en langage, supprimer la branche
`is_command`** (lignes 585-591).

**Justification** : `type e` est utilisé dans `test_suite.hvn`
(`type (+ 1 x)`) et retourne une valeur exploitable. Le check
`is_command` liste `type `, `green `, `help`, `stats`, `theorems`,
`rules` — mais le dispatch les a déjà interceptés plus haut. C'est du
code mort qui laisse croire qu'il y a une seconde voie.

**Migration** :
- `heaven_expr.zig` : retirer le bloc `is_command` (l.585-591). Vérifier
  qu'aucune des branches listées n'est atteinte uniquement par lui.
- Cas particulier : `help`, `stats`, `theorems` — vérifier s'ils sont
  shell-only ou langage. S'ils sont shell-only, il faut les déplacer.

**Effort** : 30 min (avec vérification des usages).

---

## 3. `=` vs `:=` — deux syntaxes équivalentes

**Décision** : **Garder les deux, documenter les deux comme équivalents**.

**Justification** : `=` est standard (Haskell, OCaml). `:=` est plus
explicite pour les définitions (Pascal, Go). Beaucoup d'auteurs de
langage hésitent — Heaven accepte les deux sans coût réel. Les deux
aboutissent au même `evalEquation` après conversion. Un utilisateur qui
préfère `:=` (moins ambigu visuellement avec `==`) doit pouvoir l'utiliser.

**Nuance** : dans les **exemples de la spec**, on utilisera `=` comme
forme canonique. `:=` sera documenté en « forme alternative ».

**Migration** : aucune.

**Effort** : 0.

---

## 4. `assert_eq` / `assert_err` / `test` — double syntaxe

**Décision** : **Garder les deux, marquer l'infixe comme canonique dans
la spec**.

**Justification** : les deux formes servent des cas différents :
- `test "name": a == b` : test **nommé** (avec identifiant).
- `(assert_eq a b)` : test **anonyme** dans un contexte parenthésé.

Le parenthésé est nécessaire quand on veut enchaîner dans une seule
expression S-expr. L'infixe est plus lisible au top-level. On garde
les deux mais on documente :
- **Nommé** : `test "name": a == b` (canonique).
- **Anonyme dans un contexte parenthésé** : `(assert_eq a b)`.
- **Anonyme au top-level** : `assert_eq a b` (infixe sans nom).

**Migration** : aucune (documentation seulement).

**Effort** : 0.

---

## 5. `let ` vs `let actor ` / `let macro `

**Décision** : **Ne pas toucher au dispatch**, mais spécifier clairement
dans `heaven.md` que `let` a **deux modes** :

- `let x = v in body` → liaison locale (mode par défaut).
- `let actor A = init with h` → mécanisme runtime (mode « acteur »).
- `let macro M(x) = body` → mécanisme runtime (mode « macro »).

Le second token détermine le mode. **Un utilisateur ne doit jamais
nommer une variable `actor` ou `macro` en position de let** — ces mots
sont réservés au second token après `let`.

**Justification** : le dispatch actuel teste `let ` avant `let actor `,
donc `let actor A = 0` matche le premier. Le handler local (l.743)
regarde ce qui suit pour savoir s'il doit rediriger. C'est correct en
pratique, mais subtil. La spec doit le documenter explicitement, pas
cacher la complexité.

**Migration** : aucune. Documenter.

**Effort** : 0.

---

## 6. `?` / `?-` / `ask` — trois façons pour Prolog

**Décision** : **Ajouter `?-` en langage**, **retirer `ask` du shell**,
**garder `?` comme shell-only** (aide des commandes).

**Justification** :
- `?-` est la notation Prolog universelle. La reconnaissance immédiate
  par un LLM est totale.
- `ask` est redondant avec `?-` et prend un nom utile pour l'IA
  (`ai "..."` doit pouvoir prendre `ask` — cf. COMMANDS.md).
- `?` seul (shell) liste les commandes — c'est un usage interactif,
  pas du langage.

**Migration** :
- `heaven_expr.zig` : ajouter un dispatch `startsWith(trimmed, "?- ")`
  qui appelle un handler Prolog (à câbler). C'est l'étape 3 du
  pipeline logique (roadmap).
- Shell : retirer `ask` des commandes. Ajouter `ai "..."` (roadmap).
- COMMANDS.md : acter.

**Effort** : 2-3 sessions (le handler Prolog lui-même).

**Note** : décision « cible », pas « immédiat ».

---

## 7. `send` / `state` / `spawn` sans parenthèses

**Décision** : **Accepter les deux formes** — `send(A, 5)` et `send A 5`.

**Justification** : cohérent avec le reste du langage (`simplify e` et
`(simplify e)` marchent tous les deux). Un LLM qui génère du code ne
devrait pas avoir à deviner si `send A 5` ou `send(A, 5)` est requis.
Les deux sont naturels.

**Migration** :
- `heaven_expr.zig` : assouplir `is_mechanism` (l.796-802) pour tester
  `startsWith("send ")` en plus de `startsWith("send(")`.
- Idem `state ` et `spawn `.
- Le handler convertit ensuite `send A 5` en `(send A 5)` avant de
  dispatcher.

**Effort** : 1h (petit refactor du dispatch).

---

## 8. `(test "name" lhs rhs)` — arguments séparés, pas `==`

**Décision** : **Uniformiser sur `test "name": lhs == rhs`** (infixe).

**Justification** :
- `test_suite.hvn` utilise **déjà** la forme infixe dans 100 % des cas
  (`test "addition": (+ 1 2) == 3`). La forme parenthésée
  `(test "n" a b)` n'apparaît nulle part dans les tests officiels —
  c'est du code mort qui traîne dans le dispatch.
- L'infixe est plus lisible et standard.
- Un LLM qui voit `test` dans la spec verra une seule forme.

**Migration** :
- `heaven_expr.zig` : vérifier l.817 si `(test ...)` est utilisé par un
  test réel. Si non, retirer la branche.
- Spec : documenter seulement `test "name": lhs == rhs`.

**Effort** : 15 min (vérification + retrait éventuel).

---

## Résumé

| # | Écart | Décision | Effort |
|---|---|---|---|
| 1 | `meta` | Supprimer | 10 min |
| 2 | `type` + `is_command` | Retirer `is_command` | 30 min |
| 3 | `=` vs `:=` | Garder les deux | 0 |
| 4 | `assert_eq` double | Garder, doc infixe canonique | 0 |
| 5 | `let` vs `let actor` | Documenter 2 modes | 0 |
| 6 | `?` / `?-` / `ask` | Ajouter `?-`, retirer `ask` | 2-3 sessions |
| 7 | `send` sans parens | Accepter les deux | 1h |
| 8 | `(test ...)` | Uniformiser sur infixe | 15 min |

**Total code** : ~2h pour les décisions 1, 2, 7, 8.
**Décision 6** : chantier séparé (roadmap logique étape 3).

**Décisions 3, 4, 5** : documentation pure — pas de migration.

---

## Prochaines étapes (Phase 2)

Une fois ce document validé/corrigé par l'auteur :

1. **Appliquer les décisions « immédiates »** (#1, #2, #7, #8) en un ou
   deux commits — petits, testables, sans risque.
2. **Rédiger `grammar.ebnf`** — EBNF à partir du dispatch + `expr_parser.zig`.
3. **Rédiger `heaven.md`** — 14 sections, chacune avec un exemple
   exécutable.
4. **Validation** : donner `heaven.md` seul à un LLM, lui demander 5
   programmes, vérifier qu'ils compilent.

---

## Notes pour l'auteur

Ces décisions sont des **recommandations**, pas des obligations. Si tu
préfères une autre voie sur un point (par exemple, garder `ask` en
langage parce que tu y es habitué), dis-le — je réécris la section.

L'objectif est **une spec qui ne ment pas** : chaque forme documentée
doit exister dans le code, et chaque forme du code doit exister dans
la spec.
