# Contrat MIR — invariants pour les consommateurs (backends)

> M1 (docs/BACKENDS.md). Dérivé d'une lecture complète de
> src/core/mir.zig le 2026-09-29. mir.zig est gelé : ce document
> décrit, il ne modifie pas.

## 1. Modèle de valeurs
- Type unique : **i64** (const, arithmétique, cmp → 1/0).
- `Reg = u32` : indice dans une table conceptuelle de valeurs ;
  chaque reg est écrit par exactement une instruction le long d'un
  chemin (pseudo-SSA).
- L'interprète matérialise `values: ArrayList(i64)` avec resize
  paresseux — un backend peut l'ignorer : le graphe des regs suffit.

## 2. CFG
- `blocks: []BasicBlock` ; un bloc = instrs + **un unique
  terminator** (`jump | branch | ret | fallthrough`).
- `jump/branch/ret` existent dans l'union `Instr` mais ne doivent
  JAMAIS apparaître dans `instrs` (l'interprète : `unreachable`).
  Terminators only. Bloc 0 = entrée. `fallthrough` = retour 0.

## 3. Sémantique instruction par instruction
| Instr | Effet |
|---|---|
| `const_int d v` | `d := v` |
| `add/sub/mul/div d l r` | arithmétique ; div tronque vers 0 |
| `cmp_lt/cmp_eq d l r` | `d := 1/0` (i64) |
| `load d sym` | `d := global[sym]` (error si non défini) |
| `store sym r` | `global[sym] := r` |
| `call_user d name args` | voir §6 |
| `phi d incoming` | `d := valeur du prédécesseur exécuté` |

## 4. Phi
En tête du bloc cible ; sélection par prédécesseur réellement
emprunté (`prev_block` dans l'interprète). Dégénérés autorisés par le compileur : 1 incoming
(branche sœur = break), 0 incoming (les deux branches ont rompu) —
remplacé par `const_int 0`.

## 5. Globals
`load/store` adressent des variables globales par `Sym` (u32).
L'interprète les prend dans une `AutoHashMap(u32, i64)` fournie
par l'appelant. Non défini au load → `error.UndefinedVariable`.

**Note exécution** : `execute()` est destructif — `values` est
libéré en sortie (defer deinit interne d'executeLegacy). Un
consommateur ne doit PAS appeler `deinit()` après `execute()` :
double free. (Contournement : deinitSansValues dans test_mir_wat.zig.)

## 6. call_user — la vraie frontière
Deux résolutions, dans cet ordre :
1. `fn_defs[name]` : lambda compilée (via `bind` d'une lambda,
   `compileLambda` — engine absent, donc ces corps ne contiennent
   pas de call_user). **Compilable vers un backend.**
2. Sinon fallback `engine.evalFunction` — fonctions définies par
   équations, interprète only. **Un backend doit rejeter
   (error explicite — jamais de repli silencieux).**

## 7. Divergences interprète → WASM (acceptées, documentées)
| Comportement | Interprète | WASM |
|---|---|---|
| div par 0 | error.DivisionByzero | **trap** |
| boucle infinie | error.TooManyIterations (1000) | boucle réelle |
| load global non défini | error.UndefinedVariable | global = 0 |
| globals d'un appel fn MIR | map fraîche par appel | **partagés** |
| perf des appels | cloneFunction par appel | call natif |

## 8. Sous-ensemble consommé par M2 (mir_wat.zig)
const_int, add, sub, mul, div, cmp_lt, cmp_eq, jump, branch, ret,
phi (→ local.set prédécesseur), load/store (→ globals WASM),
call_user restreint à fn_defs. Rejet explicite sinon.
