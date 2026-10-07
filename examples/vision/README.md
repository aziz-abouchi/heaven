# Examples / Vision

Fichiers ecrits en "Heaven pur" mais qui utilisent des **features
qui n'existent pas encore** dans le langage. Conserves comme
specimens de la direction architecturale.

## Features utilisees (non implementees)

- `match x with | A => B | C => D` -- **n'existe pas**.
  Heaven utilise des equations multi-clauses :
  `f A = B` puis `f C = D`.
  Reference : `docs/spec/_validation.md:41` (le LLM l'a invente).

- `inline_qbe "..."` -- **n'existe pas**. Pas d'assembly inline.

- `@syscall(...)`, `@extern("c", ...)` -- **n'existent pas**.

- `@if(target_os == ...) { ... }` -- compilation conditionnelle,
  **non implementee**.

- Types `Ptr`, `Fd`, `Buf`, `Unit` -- **n'existent pas**.

- `linear` en argument (`fn f(linear x)`) -- **non supporte**.
  QTT existe en `let linear x = ...`.

- `where` (Haskell) et `Refl : Eq A x x` -- **non supportes**.

## Fichiers

| Fichier | Feature manquante principale |
|---|---|
| `platform/emitter.hvn` | `inline_qbe` + `match` |
| `platform/sys.hvn`, `syscall_table.hvn` | `inline_qbe` + syscall |
| `platform/abi.hvn`, `mod.hvn`, `target.hvn` | `match`, `@if` |
| `platform/*_x86_64.hvn`, `*_arm64.hvn` | `@syscall` / `@extern` |
| `io.hvn`, `memory.hvn`, `arena.hvn` | syscalls + `linear` en arg |
| `test_pure.hvn` | tout ci-dessus |

## Ce qui EST reecrivable

Voir `lib/prelude.hvn` et `lib/list.hvn` : ceux-la ont ete reecrits
en syntaxe reelle (equations multi-clauses, plus de `match`).

## Pour aller plus loin

Voir `docs/spec/_syntax_gaps.md` section "Vision" pour la liste
precise des chantiers (match, inline_qbe, syscalls, pointeurs).

Le chemin le plus court pour rendre ces fichiers fonctionnels :
1. Implementer `match ... with` (sucre pour equations multi-clauses).
2. Ajouter des primitives bas niveau (au moins `@syscall` ou une
   convention d'appel QBE/WAT).
3. Introduire des types pointeur dans le MIR.
Effort : 4-6 sessions.
