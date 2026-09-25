# Changelog du langage

Historique des fonctionnalités du langage. Les entrées sont en ordre
antéchronologique.

## 2026-09-25

### Type-dep v2e — fix bug silencieux v2d + `holesToEvars`
- **Bug découvert** : `_` est parsé en `Tag.hole`, et
  `unify_proof.unify` ne lie que les `Tag.evar`. Résultat :
  `subst_v2d` restait **toujours vide** entre v2d et v2e
  (`body_used == body`, no-op silencieux non détecté par les
  tests v2d car le pattern matching engine liait les variables
  de pattern indépendamment).
- **Fix** : `Heaven.holesToEvars` remplace les holes par des
  evars frais avant `unify`. Message de succès expose
  `(subst: N)` quand N > 0.
- **Portée honnête** : le mécanisme tourne, mais aucun body
  réaliste n'est affecté aujourd'hui (le body est parsé
  depuis une string utilisateur, jamais d'evar dedans). v2e est
  préparatoire à **v2f** (unification vraie `Vec (n + m)`
  modulo arithmétique).
- 2 tests : `subst:` présent sur type paramétré, absent sur
  type non paramétré.
- **Intégré dans** : `03-syntax-in-functions.md`, STATUS.

### Architecture — RFC-0001 5/5 (complet)
- Extraction de `import.zig` : `ImportState`, `resolveImportPath`,
  `evalImport` (~270 lignes retirées de `heaven_expr.zig`).
- Cycle `HeavenError` brisé : `ImportError = error{OutOfMemory}`
  local, wrapper dans `heaven_expr.zig`.
- Pattern `heaven: anytype` (déjà utilisé pour `std_loader`).
- `heaven_expr.zig` : 4367 → 4101 lignes.
- Découpage RFC-0001 terminé : `io_handler`, `expr_parser`,
  `hole_runtime`, `unify_proof`, `std_loader`, `import`.
- **Intégré dans** : `10-under-the-hood.md` (enrichi),
  STATUS.md.

## 2026-09-24

### Type-dep v2d — unification d'indexes dépendants
- `Heaven.ctor_results` : ctor → forme canonique du résultat
  (`Nil → "Vec zero"`, `Cons → "Vec (succ _)"`), peuplé dans
  `evalDataDecl`.
- `evalEquation` : unification best-effort via `unify_proof.unify`
  entre `ctor_results[ctor]` et le domaine déclaré ; instanciation
  du RHS sous la substitution avant `registerClause`.
- Tests : `ctor_results` peuplé, acceptation `Cons`, rejet v2c
  (`Nil` vs step), no-op types non paramétrés, end-to-end
  `head (Cons 42 Nil) → 42`.
- **Note** : infrastructure en place ; aucun test actuel ne prouve
  que la substitution **change** un résultat (à valider en v2e avec
  `Vec (n + m)`).
- **Intégré dans** : `03-syntax-in-functions.md`, STATUS.

### Architecture — RFC-0001 4/5
- Nouveaux modules extraits de `heaven_expr.zig` :
  `unify_proof.zig` (API proof/tactics : Ctx, Subst, unify,
  instantiate, rewriteIn), `std_loader.zig` (chargement boot-time
  io.hvn + std/*.hvn).
- Pattern : `heaven: anytype` pour éviter le cycle
  `heaven_expr ↔ std_loader`.
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

## 2026-09-23

### Types dépendants (surface) — chantier #type-dep
- `data Vec (n : Nat) = Nil | Cons a (Vec n)` : parsing + registre.
- `sig head : (n : Nat) -> Vec (succ n) -> a` : vérification qu'une
  signature Π est bien formée (règle CIC).
- Vérification structurelle des patterns : arité ctor, kind, et
  compatibilité base/step (`head _ Nil` rejeté, `head _ (Cons x _)` OK).
- **Intégré dans** : `03-syntax-in-functions.md`, `A-syntaxe.md`.

### Modules et imports — chantier #module
- `module M` ouvre un namespace.
- `import "path.hvn" [as Name]` charge un fichier et l'alias sous `Name.x`.
- `import Name` cherche `core/std/<nom>.hvn` puis `core/<nom>.hvn`.
- `export foo` : contrôle des alias sous `Name.x`.
- Détection de cycles, `HEAVEN_PATH`.
- `strict on/off` : mode opt-in qui n'enregistre les définitions que
  sous `M.x`.
- **Intégré dans** : `11-modules.md`, `A-syntaxe.md`.

### Tactics — chantier #tactics v1 → v4
- `prove t by { simplify; induction x; rewrite IH }` : bloc composable.
- Tactiques : `simplify`, `reflexivity`, `assumption`, `auto`,
  `cases x`, `induction x`, `rewrite H`, `apply H`, `exact h`,
  `seq`, `try`, `repeat`.
- REPL interactif : `prove t by {` ouvre un prompt `>` avec affichage
  `Goal N/N`.
- Unification simple via `Tag.evar` (métavariables internes).
- **Intégré dans** : `08-proofs.md`, `A-syntaxe.md`, `C-glossaire.md`.

### Stdlib
- Chargés au boot (`core/std/*.hvn`) : `Bool`, `List`, `Option`,
  `Pair`, `Result`.
- **Intégré dans** : STATUS, `01-starting-out.md` (indirectement,
  les exemples marchent).

### Noyau
- `Tag.evar` — métavariables internes (distinctes de `Tag.hole`).
- `Store.pi` — fix d'un bug historique (`payload` = Sym, pas Id).
- Pattern matching : `_` traité comme wildcard (tag `.hole`).
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

### Architecture
- Découpage RFC-0001 en cours : `io_handler.zig`, `expr_parser.zig`,
  `hole_runtime.zig` extraits de `heaven_expr.zig` (197 → 166 Ko).
- **Intégré dans** : `10-under-the-hood.md` (à enrichir).

### Documentation
- `docs/COMMANDS.md` : carte langage vs shell.
- `docs/capabilities.md` : design capabilities (WASI / Cap'n Proto).
- `docs/ROADMAP.md` : #units, #codegen-targets, #egraph-viz.

## 2026-09-22 et avant

Voir `git log` pour l'historique détaillé. Les features suivantes
sont déjà intégrées dans les chapitres :

- Holes v1 (`_`, `:hole`, `:refine`) — `08-proofs.md`.
- IO par effets (`print`, `readFile`, `writeFile`, `readLine`) —
  `06-effects.md`, `09-real-world.md`.
- QTT (`let linear/erased/many x = ... in ...`) — mention dans le
  book, à enrichir.
