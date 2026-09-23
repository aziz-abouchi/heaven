# Changelog du langage (récent)

Ce chapitre liste les fonctionnalités **récentes** (2026-09-23) qui
ne sont **pas encore** reflétées dans les autres chapitres du book.
Un chantier `docs(book)` dédié les intégrera quand le merge
astra-core ↔ heaven sera stabilisé.

## Types dépendants (chantier #type-dep)

- `data Vec (n : Nat) = Nil | Cons a (Vec n)` — parsing + registre.
- `sig head : (n : Nat) -> Vec (succ n) -> a` — vérification qu'une
  signature Π est bien formée (règle CIC).
- Vérification structurelle des patterns : arité ctor, kind, et
  compatibilité base/step (`head _ Nil` rejeté, `head _ (Cons x _)` OK).

## Modules et imports (#module)

- `module M` ouvre un namespace.
- `import "path.hvn" [as Name]` charge un fichier et l'alias sous `Name.x`.
- `import Name` cherche `core/std/<nom>.hvn` puis `core/<nom>.hvn`.
- `export foo` : contrôle des alias sous `Name.x`.
- Détection de cycles, `HEAVEN_PATH`.
- `strict on/off` : mode opt-in qui n'enregistre les définitions que
  sous `M.x`.

## Tactics et preuves (#tactics v1→v4)

- `prove t by { simplify; induction x; rewrite IH }` — bloc composable.
- Tactiques : `simplify`, `reflexivity`, `assumption`, `auto`,
  `cases x`, `induction x`, `rewrite H`, `apply H`, `exact h`,
  `seq`, `try`, `repeat`.
- REPL interactif : `prove t by {` ouvre un prompt `>` avec affichage
  `Goal N/N`.
- Unification simple via `Tag.evar` (métavariables internes).

## Stdlib (#stdlib)

Chargés au boot (`core/std/*.hvn`) :
- `Bool` : `true`, `false`, `not`, `and`, `or`.
- `List` : `nil`, `cons`, `head`, `tail`, `length`, `append`.
- `Option` : `none`, `some`, `is_some`, `is_none`, `map_option`.
- `Pair` : `pair`, `fst`, `snd`.
- `Result` : `ok`, `err`, `is_ok`, `is_err`, `map_result`.

## Noyau

- `Tag.evar` — métavariables internes (distinctes de `Tag.hole`).
- `Store.pi` — fix d'un bug historique (`payload` = Sym, pas Id).
- Pattern matching : `_` traité comme wildcard (tag `.hole`).

## Runner de tests

- `heaven --run-tests <dir>` — multi-fichiers.
- `heaven --run-test <file>` — multi-lignes (parenthèses et accolades).
