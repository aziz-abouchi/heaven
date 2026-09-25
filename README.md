# Heaven

Langage de programmation expérimental unifiant raisonnement mathématique,
preuves formelles, métaprogrammation et concurrence.

> **Vision** : un « OS cognitif » capable de s'auto-optimiser (via E-Graphs)
> et de prouver formellement ses propriétés — y compris énergétiques.
> Le langage repose sur un **noyau minimal de 6 primitives fondamentales**
> (`lit`, `sym`, `apply`, `bind`, `lambda`, `relation`). Tout le reste —
> modules, types dépendants, tactiques, effets — est du **sucre syntaxique**
> abaissé via `Store.lower()` avant d'atteindre l'évaluateur.

## Ce qui marche aujourd'hui

Source de vérité : **[docs/STATUS.md](docs/STATUS.md)** (✅ stable, ⚠️ partiel,
🚧 roadmap). Points forts actuels :

- **Noyau** : 6 primitives strictes, hash-consing, `Tag.evar` (métavariables
  internes distinctes de `Tag.hole`).
- **Modules** : `module M`, `import "path.hvn" as Name`, transitif, cycles
  détectés, `HEAVEN_PATH`, `export`, idempotence, mode `strict on/off`.
- **Types dépendants (surface)** : `data Vec (n : Nat) = Nil | Cons a (Vec n)`,
  `sig head : (n : Nat) -> Vec (succ n) -> a`, vérification structurelle des
  patterns (arité, kind, compatibilité base/step).
- **Tactiques composables** : blocs `prove t by { ... }`, REPL interactif de
  buts, `simplify / reflexivity / assumption / auto / cases / induction /
  rewrite / apply / exact / seq / try / repeat`.
- **Stdlib** : `Bool`, `List`, `Option`, `Pair`, `Result` chargés au boot.
- **IO par effets** : `perform / handle`, handler par défaut
  (`print`, `readFile`, `writeFile`, `readLine`).
- **QTT** : `let linear / erased / many x = … in …`.
- **Pipeline logique** : miniKanren (`kanren_expr`), `typeo`/`evalo`,
  synthèse → E-Graph → extraction.

## Les 6 primitives

| # | Primitive | Rôle | Encodage |
|---|-----------|------|----------|
| 1 | `lit` | Valeurs immédiates (int, float, str, bool, unit, runtime) | `aux` → index dans `lits` |
| 2 | `sym` | Variables, symboles, noms de constructeurs | `payload` → index interner |
| 3 | `apply` | Application *n-aire* | `payload` → fonction, `span_a` → arguments |
| 4 | `bind` | Définition globale | `payload` → nom (Sym), `aux` → valeur |
| 5 | `lambda` | Abstraction | `payload` → paramètre (Sym), `span_a` → corps |
| 6 | `relation` | Règles de réécriture / théorèmes | `payload` → tête, `span_a` → LHS, `span_b` → RHS |

**Extensions** (sucre abaissé avant évaluation) :

- `let x = v in b` → `apply(lambda(x, b), v)`
- `f x = body` (équation) → clause dans `engine.fns`
- `module M` / `import "path" as Name` → alias `M.x` dans `engine.fns`
- `data Vec (n : Nat) = ...` → `TypeRegistry` + ctor_arity + ctor_parents
- `sig f : A -> B -> C` → arité + domaines (heads + full) dans `Heaven`
- `theorem t : a = b` + `prove t by { ... }` → `ProofState` + `Tactic`
- `perform(op, args)` → `apply(perform, op, args...)`
- `handle(body, h)` → `apply(handle, body, h)`
- `_` (hole) → `Tag.hole`
- `Type` / `Prop` → `sym("Type")` / `sym("Prop")`

L'évaluateur (`src/core/engine_expr.zig`) ne dispatch que sur ces 6 primitives.
Si une extension non-abaissée atteint l'évaluateur, elle déclenche
`error.ExtensionNotLowered`.

## Installation

```bash
zig build                 # natif (Linux / macOS)
zig build wasm            # WebAssembly

Quickstart (REPL natif)

./zig-out/bin/heaven repl

Stdlib au boot
heaven> not true
false

heaven> length (cons 1 (cons 2 nil))
(succ (succ zero))

heaven> head (cons 1 (cons 2 nil))
1

heaven> is_some (some 42)
true

Définitions et récursion

heaven> fac n = if (== n 0) 1 (* n (fac (- n 1)))
✓ clause enregistrée pour 'fac'

heaven> fac 5
120

Modules et imports

heaven> module M
✓ module M ouvert

heaven> foo x = x + 1
✓ clause enregistrée pour 'foo'

heaven> import "core/stream.hvn" as Stream
✓ import core/stream.hvn as Stream (37 line(s))

heaven> M.foo 5
6

Types dépendants (surface)

heaven> data Vec (n : Nat) = Nil | Cons a (Vec n)
✓ data Vec registered (1 param(s), 2 constructor(s))

heaven> sig head : (n : Nat) -> Vec (succ n) -> a
✓ sig head : 2 arg(s)

heaven> head _ Nil = 42
✗ pattern 2 : Nil incompatible avec le domaine 'Vec (succ n)'

heaven> head _ (Cons x _) = x
✓ clause enregistrée pour 'head'

Preuves et tactiques

heaven> theorem add_zero : x + 0 = x
✓ theorem add_zero stated

heaven> prove add_zero by { simplify }
✓ [add_zero] proved (tactics)

REPL interactif :

heaven> prove add_zero by {
Goal 1/1
  ── Target ──
    (= (+ x 0) x)
> simplify
✓ All goals solved. Tapez '}' ou 'qed' pour valider.
> qed
✓ [add_zero] proved (interactive)

Effets / IO

heaven> print "hello, world"
hello, world

heaven> readFile "core/bootstrap.hvn"
...

Commandes disponibles

Commande	Description
help	Affiche l'aide
stats	Statistiques du moteur
theorems	Liste les théorèmes et axiomes
:hole / :refine	Trous (_) : liste, détail, raffinement
:io on/off/status	Activer / désactiver / status du handler IO
:skill <name>	Applique une tactique de preuve (skills)
module M / import	Namespaces, imports, strict on/off
data / sig	Types de données et signatures
theorem / prove	Déclarer et prouver (par eval, simplify, induction, ou by { ... })
simplify / derive / integrate / solve / expand	CAS
plot / latex	Rendu graphique et LaTeX
transform	Système de transformation unifié avec certificat
ask	Agent IA (suggestions de théorèmes / réécritures)
js / mir	Transpilation JS, compilation MIR

Architecture (par couches)

Surface : REPL / shell / vessel WASM / CLI
──────────────────────────────────────────
Façade : src/core/heaven_expr.zig (parse, eval, import, tactics…)
──────────────────────────────────────────
Core IR        Logic / Rewrite      Proof / Types
expr, engine   kanren_expr          tactics, kernel
pattern, canon logic/*, egraph      types, type_registry
               transform           elab, hole, proof_core
──────────────────────────────────────────
Lowering / Front  |  Élévation         |  Runtime
syntax/lower      |  translator/MLCPD  |  actors, swarm
parse, elab       |  codegen JS/C/Ltx  |  prolog, green
                  |  forge             |  scut/network

Documentation
docs/STATUS.md — source de vérité (ce qui marche)

docs/ROADMAP.md — specs actionnables (v0/v1/v2…)

docs/book/ — livre (mdBook) : 10 chapitres + annexes + CHANGELOG

docs/ARCHITECTURE.txt — architecture technique

docs/HEAVEN_LANGUAGE.md — syntaxe du langage

docs/capabilities.md — design des capabilities

docs/GUIDE_MLCPD_INTEGRATION.md — pont MLCPD

Tests
zig build test              # 167 tests unitaires (Zig)
zig build test-regression   # 77 tests Heaven (core/test_suite.hvn)
zig build test-files        # tests/*.hvn (multi-fichiers)

Statut global
Expérimental avancé. Le noyau et les briques récentes (modules, tactics,
type-dep surface, stdlib) sont utilisables au REPL. Manquent :
unification vraie des indexes (v2e, `Vec (n + m)`), unification du
pipeline logique derrière une API unique.

Voir docs/ROADMAP.md pour les chantiers en cours.

Licence
Apache 2.0
