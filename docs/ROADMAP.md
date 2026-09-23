# Heaven — Roadmap & specs

Ce document contient les specs des fonctionnalités **non implémentées**
mais conçues. Chaque section est autonome et prête à être implémentée.

Ordre recommandé :
1. `#type-dep` — types dépendants (v0 ✅, v1 en cours)
2. `#module` — namespaces et imports (v0/v0.5/v1 ✅, v2 à venir)
3. `#stdlib` — compléter les corps de `core/std/*.hvn`
4. `#skills-v2` — fait (voir section)
5. `#io` / `#holes` / `#runner` / `#tactics` — faits (voir STATUS.md)

---

## #io — Entrées/Sorties par effets algébriques  ✅ *fait*

### Objectif

`readFile "x.txt"` **émet un effet** `ReadFile`. Un handler par défaut
l'intercepte et exécute la lecture. En mode test, le handler est
remplaçable par un mock.

### Design

**Nouveau module `core/io.hvn`** :

    readFile path = perform "ReadFile" path
    writeFile path content = perform "WriteFile" (Pair path content)
    print x = perform "Print" x
    readLine unit = perform "ReadLine" unit
    readLines path = iterate readLine unit

**Handler par défaut (`heaven_expr.zig`)** :

    fn defaultIOHandler(self: *Heaven, op: []const u8, arg: Id) ?Id {
        if (std.mem.eql(u8, op, "ReadFile")) {
            const path = resolveString(self, arg);
            const content = platform.fs.cwd().readFileAlloc(
                self.allocator, path, 1024 * 1024) catch return null;
            return self.store.lit(.{ .str = self.store.interner.intern(content) });
        }
        if (std.mem.eql(u8, op, "WriteFile")) {
            const path = resolveString(self, Pair.fst(arg));
            const content = resolveString(self, Pair.snd(arg));
            platform.fs.cwd().writeFile(path, content) catch return null;
            return self.store.unitLit();
        }
        if (std.mem.eql(u8, op, "Print")) {
            platform.debug.print("{s}\n", .{resolveString(self, arg)});
            return self.store.unitLit();
        }
        return null;
    }

**Activation** : REPL natif = handler réel. Mode `--run-test` = handler
mock qui accumule dans une liste.

**Commandes impactées** : `:io on/off`, `:io mock`.

**Effort** : 3 jours. **Prérequis** : aucun.

---


### v2 — à faire

- **Handler WASM** : sur la cible WASM, `defaultIOHandler` retourne
  actuellement `null` (stub). À brancher sur les APIs JS via `jsImports`.
- **`readLine` interactif** : fonctionne en natif, mais pas testé.
  Vérifier le comportement en REPL avec une entrée pipée.
- **Composition** : plusieurs IO séquentiels dans le même `handle`
  (aujourd'hui, le premier `perform` capté épuise le handle one-shot).

## #holes — v2 : affichage interactif  *(v1 ✅, v2 ouverte)*

### État v1 (déjà implémenté)

- `Tag.hole` + `HoleState` (`core/hole.zig`)
- `_` parsé en trou avec id unique
- `:hole` affiche les trous
- `:refine ?N <expr>` lie un trou

### v2 — manque

- `inferHoleType` ne regarde que le **parent direct**. Pour `f _ _`
  avec `f : a -> b -> c`, il faut de l'unification vraie.
- Affichage contextuel : le trou doit montrer **toutes** les variables
  en portée, pas seulement son parent.
- Mode "type-driven" : taper `f x = _` et raffiner sans quitter le REPL.
- Intégration avec `kanren_expr.Subst` pour la résolution par
  unification au lieu de l'heuristique.

**Effort** : 3 jours. **Prérequis** : v1 (fait).

---

## #runner — Tests multi-lignes & par fichier  ✅ *fait*

### État v1

- `runTestFile` découpe par `\n` à profondeur 0, hors chaîne.
  Parenthèses **et** accolades comptées, donc :
  - `theorem` / `prove` (2 commandes) fonctionnent
  - tout futur `prove t by { ... }` (roadmap #tactics) sera un seul statement
- `runTestDir` itère sur les `*.hvn` d'un dossier, agrège le statut.
- CLI : `--run-test <file>` (exit code) et `--run-tests <dir>`.
- `build.zig` : step `test-files` (`zig build test-files`).

### v2 — à faire

- Mode `--expect-fail` ou marqueur `#[xfail]` dans les blocs.
- Traitement des dossiers imbriqués (récursif).
- Sortie JSON pour CI.

**Effort v2** : 1 jour.

---

## #tactics — Tactiques composables à la Rocq/Lean

### v1 ✅ *fait*

- `core/proof_state.zig` : `Goal`, `Hypothesis`, `ProofState` + `pp`.
- `core/tactics.zig` : `Tactic` union, `applyTactic`, `parseTacticsBlock`.
- Tactiques v1 : `simplify`, `reflexivity`, `exact`, `induction`,
  `seq`, `try`, `repeat`.
- Routage `prove t by { ... }` dans `heaven_expr.zig::evalProve`.
- 3 tests : `t_tactics_simplify`, `t_tactics_seq`, `t_tactics_try`.

### v1.5 ✅ *fait*

- `rewrite H`, `apply H`.
- `isEqNode` / `rewriteIn` : garde-fous sur les bornes du Store.
- `tacticsEqCb` via `expr.structuralEql` (hash-consing insuffisant).

### v2 — REPL interactif et unification

- REPL interactif : `prove t by {` ouvre un mode `Goal 1/1` / `>` / `✓`.
- Backtracking sur `seq` quand un sous-but échoue.

### v2 — *roadmap*

- Unification vraie (au lieu de l'heuristique par parent direct).
- `cases`, `auto`, `assumption`.

### État v0 (avant #tactics)

`verifyBySimplify`, `verifyByInduction`, `verifyByRewrite` sont
**monolithiques**. Pas de composition. Pas d'état intermédiaire exposé.

### Design — `ProofState`

**Nouveau fichier `core/proof_state.zig`** :

    pub const Hypothesis = struct {
        name: []const u8,
        ty: Id,
    };

    pub const Goal = struct {
        hyps: []Hypothesis,
        target: Id,
    };

    pub const ProofState = struct {
        goals: std.ArrayListUnmanaged(Goal),
        subst: std.StringHashMapUnmanaged(Id),
        allocator: Allocator,

        pub fn init(allocator: Allocator) ProofState;
        pub fn deinit(self: *ProofState) void;
        pub fn solved(self: *const ProofState) bool;
        pub fn pp(self: *const ProofState, allocator: Allocator) ![]u8;
    };

**Nouveau fichier `core/tactics.zig`** :

    pub const Tactic = union(enum) {
        simplify,
        induction: []const u8,
        rewrite: []const u8,
        apply: []const u8,
        exact: Id,
        seq: struct { first: *Tactic, then: *Tactic },
        repeat: *Tactic,
        try_: *Tactic,
    };

    pub fn applyTactic(state: *ProofState, t: Tactic, ctx: anytype) !void;

**Syntaxe `.hvn` visée** :

    theorem add_assoc : add (add x y) z = add x (add y z)
    prove add_assoc by {
        induction x;
        simplify;
        rewrite IH
    }

**Refactor** : décomposer `verifyByInduction` en 3 tactiques atomiques
(`induction_base`, `induction_step`, `rewrite_ih`).

**Kernel** : accepter un `ProofState` partiel (goals non résolus) pour
le type-check incrémental.

**Affichage interactif** :

    heaven> theorem t : x + 0 = x
    heaven> prove t by simplify
    Goal 1/1
    ├─ x : Int
    └─ x + 0 = x
    > simplify
    ✓ Goal 1 solved
    ✓ Theorem t proved

**Effort** : 5 jours. **Prérequis** : `#holes` v1 (fait).

---

## #type-dep — Types dépendants

### v2a ✅ *fait* — vérification d'arité / forme des patterns

- `sig name : type` : déclare une signature (compte les `->` top-level
  pour l'arité).
- `Heaven.ctor_arities` / `fn_arities` peuplés par `evalDataDecl` et
  la route `sig`.
- `evalEquation` vérifie :
  1. nombre de patterns = arité attendue (si `sig` déclarée).
  2. chaque pattern `(Ctor args)` a le bon nombre d'args.

Attrape : `head Nil = 42`, `head (Cons x) _ = x` (Cons à 2 args
mais reçu 1).

### v2b ✅ *fait* — vérification par kind

- `Heaven.ctor_parents` : `ctor → type parent` (peuplé par `evalDataDecl`
  + built-ins `zero → Nat`, `cons → List`, etc.).
- `Heaven.fn_domains` : heads des domaines d'une `sig` (`"A B"` pour
  `A -> B -> C`), extraits par `extractHeadName` (strip binders et args).
- `evalEquation` : pour chaque pattern `pi`, si c'est un ctor `C`,
  comparer `ctor_parents[C]` avec `fn_domains[name][i]`.

Attrape : `nameOf apple` contre `Color -> String`,
`head (Cons x _) _` contre `(n : Nat) -> ...`.

### v2c — *roadmap*

- **Unification d'indexes dépendants** : `Vec (succ n)` vs `Vec (succ zero)`
  doit matcher avec `n := zero`. Nécessite unification + context propagation.
- Rejet de `head _ Nil` (Nil : Vec zero, pas Vec (succ n)).
- Signature avec type params implicites (`(a : Type) -> ...`).

**Effort v2c** : 2-3 sessions. Le bloc "vérification des définitions"
est fonctionnel, v2c affine sur les cas où le **ctor passe le kind**
mais pas l'**index**.

### v0 ✅ *fait*

### v0 ✅ *fait*

- `data Vec (n : Nat) = Nil | Cons a (Vec n)` parse et s'enregistre.
- Nouveau module `src/core/type_registry.zig` : `TypeRegistry`,
  `TypeInfo { name, params, ctors }`, `ParamInfo { name, ty? }`,
  `CtorInfo { name, arity, arg_types }`.
- `Heaven.type_registry` initialisé/deinit proprement.
- `evalDataDecl` étendu : parse `(n : Nat)`, `a`, et les ctor args
  (parenthésés ou non). Compat : les ctors restent enregistrés dans
  `engine.fns` (comportement historique préservé).
- 3 tests Zig : `data Vec (n : Nat)`, `data Color = ...`, compat engine.

**Limitation v0** : un seul param typé `(x : T)` supporté par data
(par manque de parsing multi-parenthèses). `data Pair a b = ...` et
`data Foo (x : T) (y : U) = ...` seront v1.

### v1 — à faire

- Multi-params typés : `(x : T) (y : U)`.
- Vérification type-dep : `head : Vec (succ n) -> a` — nécessite le
  branchement `elab.zig` → `kernel.zig` (TermPool CIC).
- Unification modulo β-réduction.
- Inférence de params implicites.

**Effort v1** : plusieurs sessions.

### v0 historique (pour mémoire)

- `kernel.zig` implémente déjà le CIC (Π, univers, Eq, refl).
- `elab.zig::TypeChecker` fait du bidirectionnel.
- Il manquait : le lien entre les deux, et la surface syntaxique.
- **v0 résout la surface syntaxique + le registre**, sans toucher au noyau.

---

## #module — Rendre `module` effectif

### v0 ✅ *fait*

- `module M` ouvre un namespace (`Heaven.current_module`).
- `theorem t : ...` aliasé sous `M.t` dans `proof_core.theorems`.
- `prove M.t by { ... }` fonctionne.
- `import "path"` : stub v0.

### v0.5 ✅ *fait* (import)

- `import "path" as Name` charge le fichier et l'évalue avec
  `current_module = Name`.
- Chaque `fn`/`let`/`theorem` top-level est aliasé sous `Name.x`
  (`engine.fns` pour fn/let, `proof_core.theorems` pour theorem).
- Nom déduit du basename si `as` absent.
- 2 tests Zig + 1 fichier de test (`tests/import_test.hvn`).
- `module.zig` (ModuleRegistry dormant) : non utilisé — son API ne
  stocke que des noms, pas d'Ids. On garde le champ string.

### v1 ✅ *fait*

- Import transitif (A → B → C).
- Détection de cycles via `Heaven.loading_modules`.
- `HEAVEN_PATH` : recherche dans une liste de dossiers (séparés par `:`).
- Propagation d'erreur : un sous-import qui échoue n'est pas avalé.

### v2 ✅ *fait*

- `export name1 name2` : contrôle des alias sous `M.x`.
- Pre-scan du fichier importé → ordre des `export` indifférent.
- Enforcement **faible** : les noms non-exportés restent accessibles
  sans qualification. Seul `M.secret` est refusé.
- Import idempotent : `Heaven.imported_files` (chemin → module).

### v3 — *roadmap*

- Enforcement **fort** : ne pas enregistrer les noms non-exportés
  du tout (nécessite de déférer l'enregistrement en fin d'import).
- Namespace hiérarchique (`A.B.foo` au lieu de flat `B.foo`).
- Rechargement dynamique (re-import avec `--reload`).
- Sélection de symboles (`import "x.hvn" as M { foo, bar }`).

**Effort v3** : 1-2 sessions.

---


## #units — Analyse dimensionnelle et incertitude

### Idée (héritée d'astra-core `lens/`, 2026-02)

Un type `Quantity(unit)` qui porte :

- **Dimensions** `(M, L, T, I)` sous forme d'entiers signés.
  Ex. : vitesse `M0 L1 T-1`, énergie `M1 L2 T-2`.
- **Incertitude** `σ : f64` propagée par les opérations :
  - `a + b → √(σa² + σb²)`
  - `a × b → |res| · √((σa/a)² + (σb/b)²)`

### Intérêt

- Vérifier des formules physiques **au niveau type** : `v = d / t`
  ne compile que si `unit(v) = unit(d) / unit(t)`.
- Budgets énergétiques vérifiables statiquement (aligné avec la
  vision « sonde Von Neumann »).
- Rendu des incertitudes : toute valeur mesurée traîne sa barre
  d'erreur.

### Design pressenti

- Wrapper les littéraux `f64` dans le Store avec une **dimension**
  optionnelle (`Tag.lit` + un `dim` associé).
- Étendre l'unification d'`egraph.zig` pour **unifier les dimensions**
  (comme il unifie les formes).
- Ou : type `Quantity(u)` avec un paramètre d'unité polymorphe, pour
  rester dans le système HM existant.

Décision à prendre quand le premier cas d'usage arrive (simulation
physique ou énergétique).

### Code source d'inspiration (non portable tel quel)

- `astra-core/src/saturation/egraph.zig` (393 l.) — modèle de nœud
  avec `unit`, `uncertainty`, `Scalar`.
- `astra-core/src/saturation/uncertainty.zig` — formules de
  propagation.
- `astra-core/src/lens/math.zig` (174 l.) — parser ; **à ne pas
  réutiliser** (fixed-size arrays, hacks « pour ton test »).

### Effort

2–3 sessions, une fois le cas d'usage clarifié.

---


## #codegen-targets — Multi-cibles de transpilation

### Idée (astra-core, 2026-02)

astra-core avait 25+ exporters (`src/forge/`) :
C, WAT, JS, Python, Rust, Zig, LaTeX, Forth, Fortran, Nim,
PHP, Racket, Lean, Idris, Koka, Odin, Carp, Julia, Lys, QBE,
Pony, LLVM-IR, R, QASM, Robotic-C.

### État

Heaven a aujourd'hui :
- `codegen_expr_c.zig` (C)
- `codegen_expr_js.zig` (JS)
- `codegen_expr_latex.zig` (LaTeX)
- `mir.zig` + `x86_64.zig` (MIR/ASM)

**Pas** de Rust, Python, Zig, WAT, LLVM-IR.

### Ce qu'on garde de l'idée

La **liste des cibles** et l'idée d'un dispatch `emitForTarget(target, expr)`.

Ce qu'on ne garde pas : le code astra (`src/forge/*.zig`) — il
émet depuis un EGraph à 5 nœuds, pas depuis le Store à 6 primitives.
Les emitters Heaven partent de zéro en réutilisant le pattern
`codegen_expr_c.zig`.

### Ordre de portage suggéré

1. `Rust` — triviale depuis C (types différents, même structure).
2. `Python` — triviale.
3. `WAT` — utile pour WASM natif (déjà target).
4. `LLVM-IR` — plus lourd, mérite sa session.

**Effort** : ½ session par cible.

---

## #egraph-viz — Visualisation D3.js du Store

### Idée (astra-core `forge/web_server.zig`)

Serveur HTTP qui rend le graphe d'e-graph en D3.js — visualisation
des e-classes, des nœuds, des relations.

### État Heaven

Heaven a `vessel/public/` (REPL web WASM) sans visualisation. Le
REPL natif affiche du texte.

### Intérêt

- Démo graphique de la saturation EGraph (déjà utilisée dans
  `simplify` et `assert_eq`).
- Voir le `Store` « respirer » : nœuds qui apparaissent, e-classes
  qui fusionnent.
- Pédagogie : montrer les tactiques en action sur une preuve.

### Effort

1 session (endpoint HTTP + page HTML avec fetch + D3).

---

## #stdlib — Compléter `core/std/`

Les fichiers `std/*.hvn` ont des signatures sans corps :

    -- actuel
    true : Bool

    -- cible
    true : Bool = true
    nil  : List = Empty

Effort : 1 jour.

---

## #fix-arrow — Fix `typeStr`

`typeStr` imprime `-> -> _t0` au lieu de `_t0 -> _t0`. Bug dans
`types.zig::typeStr` branche `"->"` (children.len == 2 vs 3).

Effort : 30 min.

---

## #sync-tests — Sync auto `test_suite.hvn`

`build.zig` doit copier `core/test_suite.hvn` vers
`src/vessel/public/test_suite.hvn` automatiquement à chaque build WASM.

Effort : 30 min.

---

## #skills-v2 — Réunification avec tactics

### v1 ✅ *fait* (refactor léger)

- `Skill.body: ?[]const u8` en **complément** de `tactics: []const Tactic` (legacy).
- `BUILTIN_SKILLS` = `body` **et** `tactics` (compat tests).
- `evalSkill` branché sur `ProofSession`.

### v2 ✅ *fait* (refactor complet)

- Enum `skill.Tactic` **supprimée** (recouvrait `tactics.Tactic`).
- `Skill` = `{ name, body: []const u8 }`.
- `register(name, body)` au lieu de `register(name, []Tactic)`.
- `apply()` passe par `ProofSession` (startProof + applyLine + finish).
- `heaven_md.zig`, `commands.zig`, tests migrés.
- Substitution `{var}` conservée.

### v3 — *roadmap*

- Skills paramétrées : `skill induction on {var}`.
- Skills récursives (`repeat try (simplify; reflexivity)`).
- Skills déclarées en `.hvn` (`skill mon_algo = ...`).

**Effort v3** : 1 session.

---

## #extern-c — ABI C

    extern fn puts(s: String) -> Int

Effort : 3 jours. **Prérequis** : `#io`.

---

## Notes

Chaque section peut être extraite en RFC séparée. Les numéros
d'effort sont des estimations à un développeur familier avec le code.
