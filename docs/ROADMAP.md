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

## #tactics — Tactiques composables à la Rocq/Lean  ← *en cours*

### État actuel

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

### État actuel

- `kernel.zig` implémente déjà le CIC (Π, univers, Eq, refl)
- `elab.zig::TypeChecker` fait du bidirectionnel
- Il manque : le **lien** entre les deux, et la **surface syntaxique**

### Design

**Syntaxe surface** :

    data Vector (n : Nat) : Type where
      Nil  : Vector zero
      Cons : a -> Vector n -> Vector (succ n)

**Elaboration** :

- `data` paramétré par des valeurs → `Node` avec `bind` sur le paramètre
- `TypeChecker.checkType` compare modulo β-réduction + CIC

**Effort** : 10 jours. **Prérequis** : `#tactics`.

---

## #module — Rendre `module` effectif

Tree-sitter reconnaît `module X`, l'évaluateur no-op. À implémenter :
- parser `module M` ouvre un namespace
- `import "M"` résout dans le namespace
- `M.x` accède au symbole qualifié

Effort : 2 jours.

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
