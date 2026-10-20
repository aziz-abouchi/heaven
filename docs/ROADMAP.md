## Jalon Reseau (Oct 2026)
- [x] Primitives reseau (@net_*)
- [x] Serveur HTTP 1-shot
- [ ] Serveur multi-requetes
- [ ] Vrai EGraph

# Heaven — Roadmap & specs

Ce document contient les specs des fonctionnalites **non implementees**
mais concues. Chaque section est autonome et prete a etre implementee.

## Etat 2026-10-07 — decisions structurantes actees

Session fondatrice : D10-D15. Voir `DECISIONS.md` pour le detail.

### Ferme

- **D10** — syscalls + libc + freestanding (3 chemins A/B/C).
  Linux amd64. `raw_syscall`, `@nom`, `HEAVEN_NO_LIBC=1`.
- **D11** — perimetre multi-plateforme (ordre : arm64-linux, apple, windows, wasi).
- **D12** — laziness (`delay`/`force` + memoization).
- **D14** — IO en Heaven (5 magics fins). `core/io_stream.hvn` (Linux x86_64).
- **D15** — `let` magic symbol S-expr.
- **D8 3a-3** — continuations delimitees one-shot (`@prompt`/`@throw`,
  `handle_rec`, scheduler sur `pending_capture`). Livre 2026-10-12.
  Multi-shot reste ouvert.
- **P0 memoire** — `core/std/memory.hvn` (alloc/dealloc + Arena +
  memcpy64). Livre 2026-10-13. Vision : `docs/spec/_memory.md`.
- **Fixes transversaux** (13 oct) : `unit`/`Unit` retires des ctors
  0-arity, `let-in` parenthese dans les clauses, `@intCast` →
  `@bitCast` pour pointeurs 64-bit.

### Pistes actives (ordre conseille)

1. **D9 Vessel** — decouplage et absorption par la stack HTTP Heaven.
2. **QTT** — documenter dans le book (`_memory.md` point 4).
3. **Multi-shot continuations** — clonage env + store (1 session).
4. **C3 preemptif** — debloque conceptuellement par D8 3a-3.
5. **`test_selfparse.hvn`** (4/5) — bug parser Heaven-en-Heaven.
6. **Audit `Store.getInt`** (30 min).
7. **Panic DebugAllocator** (session a froid).

---

## Specs plus anciennes (v0/v1 fermes, v2+ ouvertes)


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

### v2c ✅ *fait* — convention base/step

Plutôt qu'une unification d'indexes complète (HMF), on utilise une
**convention** :
- Ctor arité 0 dans un type paramétré → **base** (`Nil : Vec zero`).
- Ctor arité > 0 → **step** (`Cons : Vec (succ _)`).
- Domaine `Vec zero` → base ; `Vec (succ n)` → step.

Rejet si **base ≠ step** (ex : `head _ Nil` où Nil base, domaine step).

- `Heaven.fn_domains_full` : domaines complets d'une `sig`, séparateur
  `\x1f`. Ex : `"Nat\x1fVec (succ n)\x1fa"`.
- `Heaven.ctorKind`, `domainKind`, `checkCtorDomainKind` : classification.
- `evalEquation` : pour chaque pattern ctor, rejeter si la
  classification du ctor est incompatible avec le domaine.
- Test Zig : `head _ Nil` rejeté, `head _ (Cons x _)` accepté.

### v2d ✅ *fait* (2026-09-24)

**Livré** : `Heaven.ctor_results` (ctor → forme résultat, convention
`Nil → "Vec zero"`, `Cons → "Vec (succ _)"`), peuplé par `evalDataDecl`.
Dans `evalEquation`, chaque pattern ctor dont le parent est paramétré
est unifié avec le domaine correspondant via `unify_proof.unify`
(best-effort : échec ≠ rejet). Le RHS est instancié sous la
substitution avant enregistrement (`body_used`).

**Commits** : `61ba9c3`, `cbd588c`, `a259ca8`.

**Note** : le mécanisme tourne et `body_used` est bien propagé, mais
aucun test actuel ne prouve que la substitution **change** un résultat
(les exemples ont `x` indépendant de l'index). À valider en v2e.

### v2e/v2f ✅ *fait* (2026-10-02) — unification vraie, index non-symbolique

✅ **Implémenté et testé** :
- `Vec (n + m)` modulo arithmétique (AC + identités + évaluation littérale)
- `Vec (succ (succ zero))` ≡ `Vec 2`
- Support du symbole `zero` et des noms canoniques `add`, `mul`, `succ`
- Commande REPL `:norm` pour visualiser les réductions

**Effort réel** : 2 sessions (2026-10-01 et 2026-10-02).

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

## #fix-arrow — Fix `typeStr` ✅ _fait_

Le bug d'affichage `-> -> _t0` a été corrigé en gérant correctement le cas `children.len == 2` dans `types.zig::typeStr`.

---

## #sync-tests — Sync auto `test_suite.hvn`

`build.zig` doit copier `core/test_suite.hvn` vers
`src/vessel/public/test_suite.hvn` automatiquement à chaque build WASM.

Effort : 30 min.

## Sucre syntaxique — compréhensions

**Statut** : 🚧 roadmap (non implémenté).
**Effort** : 1 session.
**Dépend de** : stabilité de `Stream<T>` (voir `_concurrency.md`).

### Cible

Deux formes équivalentes :

    [e | x <- xs, p]                  -- style Haskell
    (for (x <- xs) (when p) e)        -- style S-expr

Désucration vers le pipeline standard :

    xs
      │
      ├── yield x
      ├── filter p
      └── map e
           │
           ▼
        Stream<T>

Matérialisation explicite si nécessaire :

    Stream<T> --toList--> List<T>
    Stream<T> --toSet-->  Set<T>

### Séparation conceptuelle

| Concept     | Type          | Nature                    |
|-------------|---------------|---------------------------|
| Producteur  | `Generator<T>`| Mécanisme (sucre sur Yield)|
| Séquence    | `Stream<T>`   | Abstrait, pull, linear    |
| Collection  | `List<T>`     | Matérialisé, ordonné      |
| Collection  | `Set<T>`      | Matérialisé, dédupliqué   |

### Principe architectural

- `Generator<T>` **n'est pas un type distinct** de `Stream<T>` au
  niveau sémantique — c'est une manière de le construire.
- `yield` est un **effet algébrique** (`perform Yield v`), cohérent
  avec `perform`/`handle` existants.
- Une compréhension produit un `Stream<T>`, **pas** une `List<T>`
  immédiate.
- La matérialisation est explicite (`toList`, `toSet`, `collect`).

### Bénéfice

- Cohérence avec la philosophie "zéro GC" + QTT (Stream linear par
  défaut).
- Compatible avec le scheduler (un Stream peut être exécuté en
  parallèle sans changer la sémantique).
- Renommage nécessaire : les `Stream` kanren existants deviennent
  `SubstStream` ou `KanrenStream` pour libérer le nom.

### Décisions à trancher

1. Syntaxe : `[e | x <- xs, p]` ou S-expr ?
2. Séquentiel vs parallèle par défaut ?
3. `Stream<T>` : `linear` par défaut (Rust Iterator) ou `many`
   (Haskell lazy list) ?
4. Renommage des Stream kanren : `SubstStream` ou autre ?
5. `Set<T>` : basé sur `HashSet` ou `Ord` + tri ?
### Tranchages proposes (2026-10-01, session backends)

Reponses aux 5 points ci-dessus, a valider avant implementation :

1. Syntaxe : LES DEUX. `[e | x <- xs, p]` en sucre frontend,
   `(for (x <- xs) (when p) e)` comme forme S-expr de lowering
   (meme pattern que infixe natif -> S-expr via nativeToSExpr).
2. Sequentiel par defaut. La spec dit elle-meme qu'un Stream peut
   etre execute en parallele "sans changer la semantique" :
   le parallelisme est donc opt-in, jamais observable.
3. `linear` par defaut (Rust Iterator). Coherent zero-GC + QTT.
   Un consommateur many peut toujours collect() ; l'inverse
   (fork d'un stream linear) est le piege classique.
4. `SubstStream`. Descriptif, honnete sur l'origine, sans
   confusion possible avec le Stream<T> semantique.
5. `Set<T>` : quotient de `List<T>` par l'egalite structurelle.
   Heaven a deja les quotients CIC (class/lift, cf test_wasm.zig)
   et structuralEql. Un HashSet casserait la coherence
   preuve/eval ; le quotient rend les Sets prouvables.

Si valides : remplacer la liste ci-dessus par ces decisions et
basculer le statut de la section en implementation.


**À intégrer avec `_concurrency.md`** : les compréhensions doivent
produire des `Stream<T>` compatibles avec le noyau 5-primitives.

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

---

## #knowledge — KnowledgeStore RDF/RDFS

### POC v0 ✅ *fait* — 2026-10-01

La couche Knowledge est maintenant separee du Core `Expr`.

Modules :

- `src/knowledge/resource.zig`
- `src/knowledge/triple.zig`
- `src/knowledge/assertion.zig`
- `src/knowledge/store.zig`
- `src/knowledge/rdfs.zig`

Contrat :

- `KnowledgeId != Expr.Id` ;
- URI, blank node et literal ;
- triples structures ;
- assertions avec provenance, status et confidence ;
- plusieurs provenances possibles pour un meme triple ;
- fermeture transitive `rdfs:subClassOf` ;
- fermeture non destructive ;
- assertions inferees marquees `inferred`.

Le KnowledgeStore n'est pas un IR et ne possede pas de backend.
Toute utilisation computationnelle future passera par un lowering
explicite vers `Expr`.

### v1 — Turtle minimal

- parser Turtle minimal ;
- prefixes ;
- URI ;
- blank nodes ;
- literals ;
- insertion dans `KnowledgeStore`.

### v2 — Requetes Knowledge

- recherche par sujet/predicate/objet ;
- resultats portant leur provenance ;
- API de requete stable ;
- fermeture RDFS exploitable sans mutation du Store.

### v3 — RDFS et lowerings

Apres validation du POC :

- `rdf:type` ;
- `rdfs:subPropertyOf` ;
- `rdfs:domain` ;
- `rdfs:range` ;
- contrat `Knowledge -> Expr` pour les cas computationnels ;
- conservation des assertions originales lors des deductions.

### Hors perimetre initial

- OWL complet ;
- SPARQL ;
- fusion implicite via `sameAs` ;
- second IR specialise ;
- backend direct depuis Knowledge.


### Phase : Unification du Lowering (Q4 2026)
- [x] Pont expérimental `lowerExprToStore` pour `x + 1`.
- [x] Étendre `lowerExprToStore` à `call` (ex: `f(x)`) et `pattern` (VALIDÉ 2026-10-08).
- [x] Étendre `lowerExprToStore` à `let` (VALIDÉ 2026-10-09) et `lambda` (à faire).
- [ ] Déplacer `UniversalIngestor` et `SurvivalTranspiler` vers `src/legacy/`.
- [ ] Supprimer toute dépendance résiduelle à `Matrix/BobId` dans le pipeline principal.



### Pilote Kmett -- optiques, recursion schemes, free monads (2026-10-09)

**Objectif** : amener au langage une bibliothèque d'abstractions
inspirées de l'écosystème Haskell (`lens`, `recursion-schemes`,
`free`, `adjunctions` — Edward Kmett). Objectif pédagogique autant
que technique : montrer que Heaven peut accueillir les notions
avancées de la programmation fonctionnelle.

**Livré v0 (2026-10-09 soir)** :

- `core/std/recursion.hvn` : `cata`, `ana`, `hylo`, `para`. 22/22.
- `core/std/lens.hvn` : optiques minimales. 12/12.
- `core/std/free.hvn` : AST interprétable. 14/14.
- Chapitres 14, 15, 16, 17 du book.
- Fix first-class (`2810cc7`) : débloque les optiques.

**Non livré (chantiers futurs)** :

- **Composition générique de lens** : `lens_compose l1 l2` — nécessite
  des types higher-rank.
- **Vrai free monad** : `>>=` monadique, continuations valuées
  (`Int -> Free`). Nécessite un type de retour réifié.
- **Prisms et traversals** : accès 0-ou-1 et 0-ou-plusieurs.
- **HKT + classes de types** : condition pour exprimer les catégories
  réellement (foncteurs, monades, transformations naturelles).

**Estimation** :

| Chantier | Effort |
|---|---|
| Composition générique de lens | 1-2 sessions |
| Vrai free monad | 2-3 sessions |
| Prisms + traversals | 1-2 sessions |
| HKT + classes de types | 3-5 sessions |

**Note** : la stratégie « chapitre = code + doc » a été validée pour
recursion schemes et optiques. Pour free monads, on a produit une
version honnête mais partielle. Pour catégories, un chapitre
conceptuel a été préféré à un bricolage qui trahirait l'idée.


---

## V1 -- Fantasy Land pour Heaven

**Statut** : roadmap
**Spec** : `docs/spec/_algebras.md`
**Reference** : https://github.com/fantasyland/fantasy-land

**Objectif** : implementer les 24 algebres de Fantasy Land en
Heaven, avec leurs lois, pour rendre les abstractions de haut
niveau (foncteurs, monades, monoides) utilisables directement.

### Ce qui manque (prerequis)

Trois briques fondamentales :

1. **HKT** (Higher-Kinded Types). Un parametre de type qui est
   lui-meme un constructeur de type (`f a` ou `f` est une variable).
   V0.5 a les bases (types en position d'argument, auto-evaluation
   des constructeurs), mais pas l'unification bidirectionnelle.

2. **Type classes**. Un mecanisme pour definir des contrats que
   plusieurs types implementent :

       class Functor f where
         fmap : (a -> b) -> f a -> f b

       instance Functor List where
         fmap = map

3. **Quantification universelle** (`forall`). Pour les
   transformations naturelles et les signatures polymorphes :

       forall a. F a -> G a

### Phases d'implementation

| Phase | Contenu | Effort |
|---|---|---|
| **V1-a** | HKT : unification bidirectionnelle + occur-check | 3-5 sessions |
| **V1-b** | Type classes : syntaxe + resolution | 2-3 sessions |
| **V1-c** | Algebres de base : Setoid, Semigroup, Monoid, Ord | 2-3 sessions |
| **V1-d** | Functor, Apply, Applicative, Chain, Monad | 3-4 sessions |
| **V1-e** | Foldable, Traversable | 2-3 sessions |
| **V1-f** | Extend, Comonad, Bifunctor, Profunctor | 2-3 sessions |
| **V1-g** | Tests des lois (`tests/test_laws.hvn`) | 1 session |

**Total estime** : 15-22 sessions (30-45h).

### Modules cibles

Chaque algebre aura son module dans `core/std/` :

- `core/std/setoid.hvn` — `equals`
- `core/std/semigroup.hvn` — `concat`
- `core/std/monoid.hvn` — `mempty`, `mconcat`
- `core/std/ord.hvn` — `Ordering` (LT/EQ/GT), `compare`, `min`, `max`
- `core/std/functor.hvn` — `fmap`
- `core/std/applicative.hvn` — `pure`, `ap`
- `core/std/monad.hvn` — `chain`, `join`
- `core/std/foldable.hvn` — `fold`, `foldMap`
- `core/std/traversable.hvn` — `traverse`

Chaque fichier aura un en-tete citant Fantasy Land et
`docs/spec/_algebras.md`.

### Tests des lois

Un fichier dedie `tests/test_laws.hvn` verifie que chaque
instance respecte les lois de son algebre. Exemples :

    -- Functor : identite
    test "Functor List id": (fmap id (list 1 2 3)) == (list 1 2 3)

    -- Monoid : identite a gauche
    test "Monoid List left-id": (concat mempty (list 1 2 3)) == (list 1 2 3)

    -- Setoid : reflexivite
    test "Setoid Int refl": (equals 42 42) == true

Les lois doivent **toutes** passer. Une instance qui ne les
respecte pas n'est pas validee.

### Dependances externes

- **Fantasy Land** — https://github.com/fantasyland/fantasy-land
- **`maryamyriameliamurphies.js`** — structure des modules
  (https://github.com/sjsyrek/maryamyriameliamurphies.js)
- **`lens`** (Kmett) — profunctor optics
- **`free`** (Kmett) — free monads
- **`adjunctions`** (Kmett) — adjonctions

Voir `docs/book/src/F-references.md` pour la liste complete.

### Lien avec le book

Les algebres sont mentionnees dans :

- **Ch2 (types)** — la notion d'« algebre » au sens de
  Fantasy Land
- **Ch5 (higher-order)** — Functor, lois de `map`
- **Ch6 (effects)** — Monad, lois de `bind`
- **Ch14 (recursion schemes)** — endofoncteurs implicites
- **Ch15 (optiques)** — Profunctor
- **Ch16 (free monads)** — Monad
- **Ch17 (categories)** — cadre theorique complet

Une fois V1 en place, ces chapitres pourront etre enrichis avec
des exemples qui utilisent les type classes directement.

---

## #memory — Couche memoire Heaven

**Statut** : P0 ✅ (2026-10-13). Vision complète dans
`docs/spec/_memory.md`.

### v0 ✅ *fait* (P0)

- `core/std/memory.hvn` : wrappers `alloc`/`dealloc` sur
  `raw_alloc`/`raw_free`.
- `Arena` (bump pointer immutable) : `arena_new`, `arena_alloc`,
  `arena_reset`, `arena_deinit`, `arena_used`/`cap`/`remaining`.
- `memcpy64` naïf (element-par-element).
- Chargé au boot via `std_loader.zig` (avant `list.hvn`).
- Tests : `tests/test_memory.hvn` (14/14).

### v0.5 — à faire

- Migrer `http.hvn`, `fs.hvn`, `net.hvn`, `json.hvn` vers
  `memory.hvn` (remplacer les `raw_alloc`/`raw_free` directs).
- `@mem_stats` magic pour monitoring (mémoire allouée, pics).
- Optimiser `memcpy64` via un vrai magic bas-niveau.

### v1 — arène contrôlée par `Engine`

- Exposer `engine.memory` (arène Zig contrôlée par Heaven) pour
  que `raw_alloc` pointe dedans.
- `drop-reuse` (FBIP) : réutilisation in-place sur structures
  linéaires (map, filter).
- Un `Arena` par requête HTTP (Vessel premier consommateur).

### v2 — vision bootstrap

- `alloc`/`free` via `mmap`/`munmap` directs
  (`core/platform/mod.hvn`).
- QTT 0/1/ω : le compilateur injecte `drop` et `alloc`.
- Perceus : `drop-reuse` automatique.
- Bare-metal : bump pointer ou buddy allocator noyau.

<!-- HEAVEN:ROADMAP:C3:BEGIN -->
### Pistes actives (mise à jour 2026-10-14)

1. **D9 Vessel** — découplage + absorption stack HTTP.
2. **QTT** — documentation dans `_memory.md` §4.
3. **Multi-shot continuations** — clonage env + store (1 session).
4. **C3 préemptif** — infrastructure en place, tests 6/6 ✗.
   Dépend de 3a-3b. Effort : 2-3 sessions (3a-3b) + 1 (C3).
5. **`test_selfparse.hvn`** (4/5) — bug parser Heaven-en-Heaven.
6. **Audit `Store.getInt`** (30 min).
7. **Panic DebugAllocator** (session à froid).

### Jalons récents
- **2026-10-14** : spec `_preemptive.md` publiée, tests
  `test_preemptive.hvn` écrits (6/6 ✗), décision D31 actée.
- **2026-10-12** : D8 3a-3a (prompts branchés dans `engine_expr.zig`).
- **HKT V0.5** : 15/15 tests verts.
<!-- HEAVEN:ROADMAP:C3:END -->

### C3 — Préemption : jalons 2026-10-14

- **C3 V0** : safepoint + budget, fix livelock (D31).
- **@budget_left** : coopération budget-aware (3/3).
- **A-2** : hook capture conditionnel dans `evaluate`.
- **A-3a** : `TaskState.preempted` + reprise par redémarrage.
  `test_preemptive_split` 0/2 -> 3/3.

**Prochain** : A-3b (`captureCont` réel, reprise exacte). Effort
2-3 sessions. Voir `docs/spec/_capture_eval.md`.

**Dette séparée** : bug `(+ 1 2 3 4)` dans lambda.

---

## D9 Vessel — statut 2026-10-19

Objectif : découplage Vessel et absorption par la stack HTTP Heaven.

- **E1** ✅ `telemetry_store.zig` (JSON depuis `expr.Store`), CI-câblé. `e65dc66`.
- **E2** ✅ (implicite) — pattern `heavenIngestSource` inline dans E3b.
- **E3a** ✅ `serveTelemetry → telemetry_store.render`. `0bdc6e9`.
- **E3b** ✅ `didSave → Heaven.eval` (read + split + eval loop). `00e1475`.
- **E3c** ✅ dedup `heaven_expr`, retire `main_mod`. `584e5e2`.
- **E4** 🚧 À faire — 1-2 sessions de conception. `core/http_server.hvn`
  nécessite : (a) `http_serve` en `.hvn` (0 match `serve|listen|accept`
  aujourd'hui), (b) `encode_jsonrpc`/`decode_jsonrpc` en `.hvn`,
  (c) décision statiques Zig vs `.hvn` (`@embedFile` n'existe pas).
  Voir `_http_fullstack_plan.md` section « État 2026-10-19 ».
- **E5** ⚠️ Partiel (`0ece80f`, `301e602`). `bridge.zig` propre,
  `bob_loop` extrait en `src/runtime/bob_loop.zig`. **E5-ter
  n'est PAS mécanique** : `matrix`/`fab` sont threadés dans 10+
  sites de `main.zig` (`UniversalIngestor`, `AutoFab`,
  `heaven.Engine`, `ReactionEngine`, `Shell`, `bob_loop`).
  Migrer ces 6 consommateurs vers `expr.Store` = 2-3 sessions,
  décision d'architecture (D-XXX) à trancher avant. Pas un bloc.

**Baseline 2026-10-19** : Debug build = 0, `zig build test` = 0,
ReleaseFast `--run-tests` = 0 fail, wasm32-freestanding = 0,
wasm32-wasi = 0.

---

## HKT V1b — statut 2026-10-19

- **V1a** ✅ `class`/`instance` declaratifs, `engine.class_names`,
  `engine.instance_pairs`, magics `@class_count`/`@instance_count`.
  `bde8adc`.
- **V1b pas 1** ✅ `@resolve_instance C T op` -> `op_T` ou "".
  `62155ce`.
- **V1b pas 2** ✅ `@dispatch_instance C T op args...` ->
  `op_T(args...)`. Matching structurel explicite (type T passe en
  argument string). `1ba6aa4`. Tests `test_hkt_v1b_step1.hvn` (4),
  `test_hkt_v1b_step2.hvn` (4).
- **V1b pas 3** 🚧 dispatch sur sym `List` sans quotes (acces `.sym`
  name). 1 bloc. Non bloquant.
- **V1c** 🚧 contraintes `Functor f =>` verifiees. Apres pas 3.

Voir `_hkt_v1b_plan.md` (option A retenue, cf. D-HKT1).

---

## Session 2026-10-20 (matin) -- jalons

- **HKT V1b** ✅ dispatch explicite (`map "List" f xs`). 11 tests.
- **Fantasy Land** ✅ 10 classes (McKenna). 13 tests.
- **Optics** ✅ Lens/Prism/Iso (Kmett). 12 tests.
- **Free + MaybeT** ✅ (Lonsdorf, Wilson). 12 tests.
- **`http_server.hvn` v1** ✅ routing infixe, 4 routes statiques 200 OK.
- **REPL web** ✅ wasm + VFS chargés (0 fichier manquant).
- **Closure fix** ✅ (partiel, cas résiduel tracé).

## Chantiers restants (efforts réalistes)

- **`_closure_capture_bug.md` §2** : ctor pattern 2-arg + ctor body SIGSEGV. 1 session.
- **Actors à la Erlang + green threads** : 5-10 sessions (voir plan à venir).
- **Effects-consolidation** (continuations, handle_rec, resume public) : 2-3 sessions.
- **Scheduler préemptif complet** : 2-3 sessions.
- **Livre Pony + preuves formelles** : 10+ sessions.
- **Rank-2 vérifié** (`forall` explicite) : 5-7 sessions.

