# Audit tooling — CLI, compilation, package manager

**Date** : 2026-09-25
**Statut** : audit descriptif. Cible : décider quel chemin est canonique.
**Source** : lecture de `src/commands/*`, `src/cli/*`, `src/pkg/*`,
`src/main.zig`, `build.zig`.

## TL;DR

**Le projet a DEUX CLIs concurrents** qui ne partagent rien :

| CLI | Source | Parser | Backend | Package mgr |
|---|---|---|---|---|
| `heaven` | `src/main.zig` | tree-sitter | C (stub) | — |
| `hvn` | `src/cli/main.zig` | frontend/parser.zig | WASM | Guppy |

Et un troisième chemin (le **REPL**), qui utilise le **parser natif**
(`nativeToSExpr`) et le **Core 6 primitives** — c'est le seul chemin
qui parle vraiment à `heaven_expr.zig`.

**Conséquence** : trois définitions de « Heaven » coexistent. C'est la
dette technique la plus lourde du projet, plus lourde que le merge
kernel (qui est un symptôme de la même maladie).

---

## 1. Les trois univers

### Univers A — REPL / Core (le chemin natif)

- **Source** : `src/main.zig` (commande `repl`), `src/core/heaven_expr.zig`
- **Parser** : `expr_parser.zig` + `nativeToSExpr` (`expr.zig`)
- **IR** : Core 6 primitives (`lit`, `sym`, `apply`, `bind`, `lambda`, `relation`)
- **Backend** : MIR (dormant), TCC (JIT, utilisé par le shell)
- **Tests** : `test_suite.hvn` (77), 184 tests Zig

**C'est ce chemin qui fait marcher le langage.** Tout le travail récent
(v2d/v2e, RFC-0001, tactiques, modules, `fact`/`query`) est ici.

### Univers B — CLI `hvn` (WASM-first)

- **Source** : `src/cli/main.zig`
- **Parser** : `src/frontend/parser.zig` (tree-sitter)
- **IR** : `src/kernel/ast.zig` (l'autre kernel, non fusionné)
- **Backend** : `src/backend/wasm.zig`
- **Package mgr** : `src/pkg/guppy.zig`
- **Commandes** : `hvn build <file>`, `hvn run <file>`, `hvn pkg ...`
- **Ce que ça fait** : `build` → parse → EGraph opt → WASM → `zig-out/main.wasm`
- **Pour lancer** : `node -e "...WebAssembly.instantiate..."` (extrait `main.zig:83`)

**Indépendant d'Univers A.** Ne partage aucun type, aucune expression,
aucun test.

### Univers C — CLI `heaven` (tree-sitter + commands/)

- **Source** : `src/main.zig` (toutes les commandes sauf `repl`)
- **Parser** : tree-sitter (`platform.ts`, `shell_parser_types`)
- **Commandes** : `parse`, `check`, `compile`, `transpile`, `fmt`, `doc`,
  `lsp`, `run`, `test`
- **Backend** : aucun sérieux. `compile` génère du C mais à partir d'un
  AST hardcodé. `run`/`test` spawn un process externe.

**C'est un troisième chemin qui coexiste avec B sans le savoir.**

---

## 2. État réel des commandes (Univers C)

| Commande | Fichier | Lignes | État | Notes |
|---|---|---|---|---|
| `parse` | `parse.zig` | 78 | ✅ réel | Tree-sitter → dump AST |
| `check` | `check.zig` | 53 | ⚠️ partiel | `compiler/typer.zig`, peu testé |
| `compile` | `compile.zig` | 113 | ❌ **stub** | AST hardcodé `add 10 32` (l.21-30), ignore le fichier |
| `transpile` | `transpile.zig` | 436 | ✅ réel | `--to c\|heaven\|latex` |
| `fmt` | `fmt.zig` | 196 | ⚠️ partiel | Tree-sitter, formate basique |
| `doc` | `doc.zig` | 258 | ⚠️ partiel | Tree-sitter, extraction de doc |
| `lsp` | `lsp_cmd.zig` | 6 | ✅ délègue | `lsp/server.zig` |
| `run` | `run.zig` | 11 | ⚠️ basique | `spawnProcess(args)` — pas de JIT |
| `test` | `test_cmd.zig` | 11 | ⚠️ basique | `spawnProcess(args)` — pas de runner |

**Verdict** : sur 9 commandes, **1 réelle et complète** (`transpile`),
3 réelles mais basiques (`parse`, `lsp`, `fmt`/`doc`), 1 stub
(`compile`), 2 juste des wrappers (`run`, `test`), 1 à vérifier
(`check`).

---

## 3. État réel de Guppy (package manager)

**Source** : `src/pkg/guppy.zig` (2182 octets, ~60 lignes)

**Commandes** :
- `hvn pkg init` → crée `guppy.toml` avec `[package]`
- `hvn pkg add <url>` → ajoute une ligne à `guppy.toml`
- `hvn pkg fetch` → `mkdir .guppy/deps`, génère `guppy.lock`

**Verdict** : **stub**. Aucun téléchargement réseau, aucune résolution
de versions, aucune compilation de dépendances. Écrit des fichiers
TOML et crée un dossier vide.

**Ce qui manque pour un vrai package manager** :
- Fetch HTTP (ou git) du dépôt
- Résolution de version (SemVer ? git rev ?)
- Cache local + lock
- Registre distant (URL scheme ?)
- Compilation/inclusion des deps dans un build

**Effort réaliste** : 3-5 sessions pour un MVP. **Ne pas attaquer
maintenant.**

---

## 4. Les 3 pipelines de compilation

### Pipeline 1 — `heaven compile` (stub)

    .hvn ──[?]──> AST hardcodé ──> output.c

**Aujourd'hui** : ne lit pas le fichier. Génère `add 10 32;`.
Utile comme placeholder, pas comme compilateur.

### Pipeline 2 — `heaven transpile`

    .hvn ──[tree-sitter]──> shell_parser_types.Matrix ──[emit*]──> C | Heaven | LaTeX

**Réel.** Mais transpile vers **du texte source**, pas vers un binaire.
C'est un traducteur, pas un compilateur.

### Pipeline 3 — `hvn build` (WASM)

    .hvn ──[frontend/parser]──> kernel/ast.Term ──[egraph.opt]──> wasm.emitFullModule → main.wasm

**Réel** (test `test_e2e_wasm.zig`). Utilise le **2ᵉ kernel**.

### Pipeline 4 — REPL natif (parallèle, non documenté comme "compilation")

    .hvn ──[expr_parser + nativeToSExpr]──> Core ──[MIR.compileExpr]──> registres virtuels

**Dormant.** MIR est appelé par le shell (`commands.zig:1598`), pas par
un CLI. C'est le seul pipeline qui parle à `heaven_expr.zig`.

### Pipeline 5 — JIT TCC

    expression runtime ──[codegen_expr_c]──> C ──[TCC]──> exécution immédiate

**Réel** (`runtime/tcc.zig`, `runtime/autofab.zig`). Utilisé par le
shell pour exécuter du code à la volée.

**Bilan** : **5 pipelines**, dont 3 réels (2, 3, 5) mais qui ne se
parlent pas, et 2 stubs/partiels (1, 4).

---

## 5. Incohérences

1. **Deux commandes `run`** :
   - `heaven run <file.hvn>` (src/main.zig) → `commands/run.zig` → `spawnProcess`
   - `hvn run <file.hvn>` (src/cli/main.zig) → build WASM + `node`

2. **Deux parsers** :
   - Tree-sitter (`shell_parser_types`) pour Univers B/C
   - Natif (`nativeToSExpr`) pour Univers A (REPL)
   - **Ne produisent pas le même AST.** Aucun pont.

3. **Deux kernels** :
   - `src/core/kernel.zig` (TermPool, Univers A) — utilisé par `proof_core`
   - `src/kernel/ast.zig` (arbre, Univers B) — utilisé par WASM

4. **Deux backends "C"** :
   - `codegen/expr_c.zig` — utilisé par TCC JIT et `compile` (Univers A/C)
   - `backend/codegen.zig` — utilisé par `compile` selon l'import
     (`compile.zig:5`)

5. **Deux binaires** :
   - `heaven` (src/main.zig) — construit par `build.zig:908`
   - `hvn` (src/cli/main.zig) — **n'est pas dans `build.zig`** (au vu du
     grep `addExecutable`, un seul exe est défini)

   → Conséquence : `hvn` **ne se compile pas** dans le build actuel.
   C'est du code mort de fait.

---

## 6. Recommandations

### Décision n°1 : choisir UN univers

**Recommandation** : **Univers A** (REPL/Core) devient canonique.

**Raisons** :
- C'est le seul qui fait tourner le langage aujourd'hui (184 tests Zig,
  77 tests Heaven, REPL fonctionnel)
- C'est là que toute la sémantique riche est implémentée (v2d/v2e, RFC-0001,
  tactiques, modules, fact/query)
- Univers B (WASM) et C (tree-sitter) sont utiles comme **outils
  périphériques** (transpile, fmt, lsp) mais ne devraient pas dicter
  l'architecture

### Décision n°2 : clarifier le rôle de chaque commande

Cible proposée :

| Commande | Univers | Cible |
|---|---|---|
| `heaven repl` | A | ✅ inchangé |
| `heaven parse` | C | ⚠️ à migrer vers le parser natif (A) |
| `heaven check` | C | ⚠️ à migrer vers elab/kernel (A) |
| `heaven compile <file> -o out` | **A** | 🚧 **à construire** — parser natif → MIR → x86_64 |
| `heaven transpile --to c/heaven/latex` | C | ✅ garder (outil de texte) |
| `heaven fmt` | C | ✅ garder (tree-sitter utile) |
| `heaven doc` | C | ✅ garder |
| `heaven lsp` | C | ✅ garder |
| `heaven run <file>` | A | 🚧 à faire = compile + exécution |
| `heaven test <file>` | A | 🚧 à faire = runner natif |
| `hvn build/run/pkg` | B | ❌ **déprécier** (WASM-first non prioritaire) |
| Guppy (pkg) | B | ❌ déprécier ou déplacer hors scope |

### Décision n°3 : unifier les parsers à terme

Le parser natif (`nativeToSExpr`) est la **vraie grammaire** du langage.
Tree-sitter ne sert qu'à l'outillage (fmt, lsp, doc). Il faut :
- Documenter cette séparation (déjà fait dans `_audit.md`)
- À terme, faire pointer tree-sitter sur la **même grammaire** que le
  parser natif (via une spec EBNF → générateur, ou maintenance parallèle)

### Décision n°4 : Package manager — reporter

`Guppy` est un stub. Faire un vrai package manager est **3-5 sessions**.
À reporter après :
1. Un compilateur natif fonctionnel (`heaven compile` Univers A)
2. Une spec stable
3. Une décision sur le registre (hébergement, format)

**Ne pas prioriser maintenant.**

---

## 7. Chantiers actionnables

| Chantier | Effort | Priorité |
|---|---|---|
| Construire `heaven compile` Univers A (parser natif → MIR → x86_64) | 2-3 sessions | Haute |
| Construire `heaven run` / `test` natifs (sans spawnProcess) | 1 session | Haute |
| Décider du sort de `hvn` (WASM-first) : garder, déprécier, fusionner | 0 (décision) | Moyenne |
| Migrer `parse`/`check` vers parser natif | 1-2 sessions | Moyenne |
| Package manager Guppy MVP | 3-5 sessions | Basse |

---

## 8. Ce qu'il faudrait vérifier en complément

- **`build.zig` définit-il vraiment `hvn` ?** → au vu du grep, un seul
  `addExecutable`. `hvn` est probablement mort dans le build.
- **`src/backend/codegen.zig`** : c'est quoi par rapport à
  `src/codegen/expr_c.zig` ? Deux backends C concurrents ?
- **`src/compiler/`** : contient `scope.zig`, `diagnostics.zig`,
  `ast_bridge.zig`, `typer.zig`. C'est un 3ᵉ système de types ? Utilisé
  par `check`. À auditer.
- **`src/frontend/lowering.zig`** vs `src/syntax/lower.zig` vs
  `src/core/lowering.zig` : trois "lowering" différents. Confusion.

---

## Conclusion

Le projet a **5 pipelines de compilation** dont 3 fonctionnent
partiellement, **2 CLIs** dont 1 n'est pas dans le build, **2 parsers**
non compatibles, **2 kernels**. La multiplication des chemins
parallèles est la dette technique principale — au-delà du merge kernel
qui en est un symptôme.

**Recommandation court terme** : ne rien construire de nouveau avant
d'avoir **choisi Univers A comme canonique** et **déprécié B et C
partiellement**. Sinon on ajoute à la confusion.

**Recommandation long terme** : un seul pipeline `heaven compile`
(parser natif → MIR → x86_64 ou WASM), et des outils périphériques
(tree-sitter pour fmt/lsp/doc) qui ne redéfinissent pas la sémantique.
