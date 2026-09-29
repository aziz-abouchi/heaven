# Contrat MIR — invariants pour les consommateurs (backends)

> M1 de la feuille de route BACKENDS.md. Dérivé d'une lecture
> complète de src/core/mir.zig (978 l.) le 2026-09-29. mir.zig est
> gelé : ce document décrit, il ne modifie pas.

## 1. Modèle de valeurs

- Type unique : **i64** (const, arithmétique, comparaisons → 1/0).
- `Reg = u32` : indice dans une table conceptuelle de valeurs.
- **Pseudo-SSA** : chaque reg est écrit par exactement une
  instruction le long d'un chemin d'exécution (phi ou const).
- L'interprète matérialise la table en `values: ArrayList(i64)`
  avec resize paresseux. Un backend peut l'ignorer : le graphe
  des regs suffit.

## 2. CFG

- `blocks: []BasicBlock`, chaque bloc = liste d'instrs + **un
  unique terminator** (`jump | branch | ret | fallthrough`).
- **Invariant** : `jump`, `branch`, `ret` existent dans l'union
  `Instr` mais ne doivent JAMAIS apparaître dans `instrs` —
  l'interprète les marque `unreachable`. Terminators only.
- Bloc 0 = point d'entrée. `fallthrough` = retour implicite 0.

## 3. Sémantique instruction par instruction

| Instr | Effet |
|---|---|
| `const_int d v` | `d := v` |
| `add/sub/mul/div d l r` | `d := l ⊕ r` ; div = troncature vers 0 |
| `cmp_lt/cmp_eq d l r` | `d := 1 si vrai sinon 0` (i64) |
| `load d sym` | `d := global[sym]` (error si non défini) |
| `store sym r` | `global[sym] := r` |
| `call_user d name args` | appel — voir §6 |
| `phi d incoming` | `d := valeur du prédécesseur d'exécution` |

## 4. Phi

Position : **tête du bloc cible**. Sélection par bloc prédécesseur
réellement emprunté (`prev_block`). Cas dégénérés autorisés par le
compileur : 1 incoming (branche sœur = break), 0 incoming (les deux
branches ont rompu) → le compileur émet `const_int 0` à la place.

## 5. Globals

`load/store` adressent des variables globales par `Sym` (u32).
L'interprète les prend dans une `AutoHashMap(u32, i64)` fournie
par l'appelant. Non défini au load → `error.UndefinedVariable`.

## 6. call_user — la frontière des 40 %

Deux résolutions à l'exécution, dans cet ordre :
1. `fn_defs[name]` : lambda compilée (via `bind` d'une lambda,
   `compileLambda`). **Ceci est compilable vers un backend.**
2. Sinon : fallback `engine.evalFunction` — fonctions définies par
   équations (`fn f x = ...`), qui n'existent qu'en interprète.
   **Non compilable en l'état** — un backend doit rejeter
   (erreur explicite, convention : pas de repli silencieux).

## 7. Divergences interprète → WASM (acceptées, documentées)

| Comportement | Interprète | WASM |
|---|---|---|
| div par 0 | error.DivisionByzero | **trap** |
| boucle infinie | error.TooManyIterations (1000) | boucle réelle |
| load global non défini | error.UndefinedVariable | global init à 0 |
| perf des appels | cloneFunction **par appel** | call natif |

## 8. Sous-ensemble consommé par M2 (émetteur WAT)

const_int, add, sub, mul, div, cmp_lt, cmp_eq, jump, branch, ret,
phi (→ local.set en prédécesseur), load/store (→ globals WASM),
call_user **restreint à fn_defs**. Rejet explicite sinon.
