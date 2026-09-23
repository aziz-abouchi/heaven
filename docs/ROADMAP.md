# Heaven — Roadmap & specs

Ce document contient les specs des fonctionnalités **non implémentées**
mais conçues. Chaque section est autonome et prête à être implémentée.

Ordre recommandé :
1. `#io` — débloque l'utilisabilité
2. `#holes` — v1 implémentée (voir STATUS.md), v2 = affichage interactif
3. `#tactics` — débloque la puissance de preuve
4. `#type-dep` — débloque les mathématiques avancées

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

### v1 — à faire

- `fn`/`let` namespacés (evalEquation).
- `import "path"` réel (chargement + inclusion dans le namespace).
- Brancher `ModuleRegistry` (module.zig) au lieu du champ string.
- Résolution `M.x` côté élaboration (`elabMember` produit déjà
  `sym("M.x")`, il manque le lookup au runtime).

Effort v1 : 1-2 jours.

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

## #extern-c — ABI C

    extern fn puts(s: String) -> Int

Effort : 3 jours. **Prérequis** : `#io`.

---

## Notes

Chaque section peut être extraite en RFC séparée. Les numéros
d'effort sont des estimations à un développeur familier avec le code.
