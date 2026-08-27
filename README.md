# Heaven

Langage de programmation expérimental unifiant raisonnement mathématique, preuves formelles, métaprogrammation et concurrence.

> **Vision** : Un "OS cognitif" capable de s'auto-optimiser (via E-Graphs) et de prouver formellement ses propriétés — y compris énergétiques. Le langage repose sur un **noyau minimal de 6 primitives fondamentales** (`lit`, `sym`, `apply`, `bind`, `lambda`, `relation`) encodées dans `src/core/expr.zig::Primitive`. Tout le reste — `let_in`, `hole`, `quote`, `perform`, `handle`, types dépendants, listes — est du **sucre syntaxique** qui se traduit mécaniquement en ces 6 primitives via `Store.lower()` avant d'atteindre l'évaluateur.

## Les 6 primitives

| # | Primitive | Rôle | Encodage |
|---|-----------|------|----------|
| 1 | `lit` | Valeurs immédiates (int, float, str, bool, unit, runtime) | `aux` → index dans `lits` |
| 2 | `sym` | Variables, symboles, noms de constructeurs | `payload` → index interner |
| 3 | `apply` | Application *n-aire* | `payload` → fonction, `span_a` → arguments |
| 4 | `bind` | Définition globale | `payload` → nom, `aux` → valeur |
| 5 | `lambda` | Abstraction | `payload` → paramètre, `span_a` → corps |
| 6 | `relation` | Règles de réécriture / théorèmes | `payload` → tête, `span_a` → LHS, `span_b` → RHS |

**Extensions** (sucre syntaxique, lowered avant évaluation) :
- `let x = v in b` → `apply(lambda(x, b), v)`
- `_n` (hole) → `sym("_")`
- `'e` (quote) → `apply(quote, e)`
- `~e` (unquote) → `apply(unquote, e)`
- `perform(op, args)` → `apply(perform, op, args...)`
- `handle(body, h)` → `apply(handle, body, h)`
- `[]` (list_nil) → `sym("Nil")`
- `h::t` (list_cons) → `apply(Cons, h, t)`
- `Type_i` (universe) → `sym("Type_i")`

L'évaluateur (`src/core/engine_expr.zig`) ne dispatch que sur ces 6 primitives. Si une extension non-lowered atteint l'évaluateur, elle déclenche `error.ExtensionNotLowered`.

## Installation

```bash
# Natif (Linux)
zig build

# WebAssembly
zig build wasm
cp zig-out/bin/heaven.wasm src/vessel/public/
```

## Utilisation

**REPL natif :**
```bash
rlwrap ./zig-out/bin/heaven 8080
```

**REPL web :**
Ouvrir `src/vessel/public/index.html` dans un navigateur.

## Commandes disponibles

| Commande | Description |
|----------|-------------|
| `help` | Affiche l'aide |
| `stats` | Statistiques du moteur |
| `theorems` | Liste les théorèmes et axiomes |
| `let` | Définit une variable ou une fonction (syntaxe Lisp pour la récursion) |
| `simplify` | Simplifie une expression |
| `derive` | Dérivation symbolique |
| `integrate` | Intégration symbolique |
| `solve` | Résolution d'équations |
| `expand` | Développement d'expressions |
| `plot` | Tracé de courbes (ASCII) |
| `latex` | Rendu LaTeX |
| `explain` | Trace les étapes de simplification |
| `theorem` | Déclare un théorème |
| `prove` | Prouve un théorème (`simplify`, `induction`) |
| `skill` | Applique une tactique de preuve |
| `mir` | Compile et exécute du code MIR |
| `transform` | Système de transformation unifié avec certificat |
| `ask` | Agent IA (suggère des théorèmes et des réécritures) |
| `js` | Transpile une expression vers JavaScript |

## Exemples

### Définition récursive (syntaxe Lisp)

```heaven
heaven> let fac(n) = (if (== n 0) 1 (* n (fac (- n 1))))
→ fac clause (1 patterns) registered

heaven> fac(5)
→ 120

heaven> fac(0)
→ 1
```

### Simplification et preuves

```heaven
heaven> simplify x + 0
→ x

heaven> theorem add_zero : a + 0 = a
✓ theorem add_zero stated

heaven> prove add_zero by simplify
✓ [add_zero] proved (simplify)
```

### Système de transformation unifié

```heaven
heaven> theorem add_zero : a + 0 = a
✓ theorem add_zero stated

heaven> transform x + 0 = x
Success:
 Result: Refl
 Certificate: 4 steps
```

### Compilation MIR

```heaven
heaven> mir (+ 2 3)
→ 5

heaven> mir (if 1 10 20)
→ 10

heaven> mir (while (< 5 1) 42)
→ 0
```

### Agent IA

```heaven
heaven> ask Prouve la commutativité de l'addition
→ Suggestion : theorem comm_test : a + b = b + a
→ ✓ theorem comm_test stated

heaven> ask factorielle
→ Suggestion : let fac(n) = (if (== n 0) 1 (* n (fac (- n 1))))
→ fac clause (1 patterns) registered
```

### Transpilation JavaScript

```heaven
heaven> js 2 + 3 * 4
→ (2 + (3 * 4))

heaven> js (if 1 10 20)
→ (1 ? 10 : 20)
```

## Équivalence Inter-Langages Certifiée (MLCPD)

Ce système prouve formellement l'équivalence sémantique de programmes écrits dans différents langages.

**Exemple :**
- **Python** : `def is_adult(age): return age >= 18`
- **Java** : `boolean isAdult(int age) { return age >= 18; }`
- **Résultat** : `equivalent: true`

Voir [docs/GUIDE_MLCPD_INTEGRATION.md](docs/GUIDE_MLCPD_INTEGRATION.md) pour le guide complet et [examples/EQUIVALENCE_EXAMPLES.md](examples/EQUIVALENCE_EXAMPLES.md) pour plus d'exemples.

## Architecture

| Module | Rôle |
|--------|------|
| `src/core/expr.zig` | Noyau : 6 primitives + extensions + lowering |
| `src/core/engine_expr.zig` | Évaluateur (dispatch sur 6 primitives uniquement) |
| `src/core/canon.zig` | Canonicalisation AC (ordre total sur les 6 primitives) |
| `src/core/pattern.zig` | Pattern matching structural (sur les 6 primitives) |
| `src/core/types.zig` | Inférence Hindley-Milner (rejette les extensions) |
| `src/core/proof.zig` | Système de preuve (normalisation Peano sur primitives) |
| `src/platform/` | Abstraction Native / WASM |
| `core/` | Suite de tests et programmes Heaven (`.hvn`) |
| `src/vessel/` | Interface web (REPL WASM) |

Pour les détails techniques, voir [docs/ARCHITECTURE.txt](docs/ARCHITECTURE.txt).

## Documentation

- [docs/transform.md](docs/transform.md) — Interface de transformation
- [docs/ARCHITECTURE.txt](docs/ARCHITECTURE.txt) — Architecture technique
- [docs/TUTORIAL.txt](docs/TUTORIAL.txt) — Tutoriel pas-à-pas
- [docs/HEAVEN_LANGUAGE.md](docs/HEAVEN_LANGUAGE.md) — Syntaxe du langage

## Tests

```bash
zig build test
```

39 tests unitaires passent (sur 39).

Vous pouvez également exécuter la suite fonctionnelle :
```bash
zig build run -- --run-test core/test_suite.hvn
```

## Feuille de route (Maturité 12/12)

| Score | Fonctionnalité | Statut |
|-------|---------------|--------|
| 1-3 | Noyau logique, arithmétique de Peano, E-Graphs | |
| 4-6 | Pipeline MLCPD, macros hygiéniques (`quote`/`unquote`) | |
| 7-9 | Acteurs typés synchrones (`spawn`, `send`, `state`) | |
| 10 | Effets algébriques (`perform`, `handle`) | |
| 11 | Inférence de type Hindley-Milner | |
| 12 | Green Profiling (énergie via effets algébriques) | |

## Limitations actuelles

- **MIR** : la commande `mir` ne compile que les primitives arithmétiques et les structures de contrôle (`if`, `while`, `break`). Les fonctions utilisateur définies avec `let` ne sont pas encore compilables en MIR. Utilisez l'évaluation directe (`fac(5)`) pour exécuter vos fonctions.
- **Syntaxe native** : la définition de fonctions avec des virgules (`let fac(n) = if(n == 0, 1, n * fac(n - 1))`) est en cours de stabilisation. La syntaxe Lisp est recommandée pour l'instant.

## Licence

Propriétaire
