# Check v2 — détection des variables non définies (plan)

**Statut** : fondation en place (commit `7430b15`), walker à implémenter.
**Priorité** : moyenne (silence sur `x = y + 1` avec `y` non défini).
**Tentative v0.1** : reverted (walk store naïf produit 20+ faux positifs).

## Problème

`heaven check` ne détecte aucune variable non liée. Cas silencieux :

    x = y + 1       -- y unbound
    f n = m + 1     -- m unbound (non signalé)
    f x = y + 1     -- y unbound (non signalé)

## Fondation en place (commit `7430b15`)

Préparation du walker réalisée :

- `ast_bridge.zig` : champ `roots: ArrayListUnmanaged(Id)` accumulé
  dans `buildFile`, `deinitRoots()`, fallback `buildTopLevel` retourne
  `NULL` au lieu de `sym(ntype)` (fin des faux positifs `import_decl`,
  `eq_decl`).
- `check.zig` : `defer bridge.deinitRoots()` **avant** `try buildFile`
  (ordre correct, pas de fuite sur error path).
- `lsp/handler.zig` : `deinitRoots` aux 2 callers (Bridge.init × 2).

Non-régression : `scheduler.hvn` — 0 leak (avant : 20+). Registry
24/24. Le comportement de `check` reste inchangé sur les 6 cas unbound
— le walker lui-même reste à écrire.

## Reste à faire (Session 43)

1. **Valider `roots.len()`** par fichier de test (avant tout code) :
   si `roots.len() == 0` sur `x = y + 1`, Bridge.buildFile ne
   remplit pas comme prévu → stop.
2. **Walker `unbound_check.zig`** : input `roots`, `store`, `file_path`.
   Walk récursif par tag. Distinction `.sym` référence vs définition
   via position dans l'arbre.
3. **Non-régression bloquante** : les 5 fichiers qui produisaient des
   faux positifs (`os/scheduler`, `std/result`, `test_data`,
   `test_stream`, `features_smoke`) doivent rester à `unbound=0`.

## Tentative v0.1 (reverted)

`scope_check.checkUnbound` walk le store, collecte les noms définis
(.bind / .lambda / .letrec), vérifie chaque .sym non filtré.

**Échec** : le store contient les noms de règles tree-sitter
(`import_decl`, `eq_decl`, etc.) comme `.sym`. Un fichier réel comme
`lib/os/scheduler.hvn` produit 20+ faux positifs. Impossible à
distinguer des vraies variables sans contexte AST.

## Design v2 (à implémenter)

Ne PAS scanner le store. Utiliser :

1. **Bridge** (`src/compiler/ast_bridge.zig`) : exposer les `roots`
   (Ids de définitions top-level) + le `Scope` déjà rempli.
2. **Walker AST récursif** qui, à chaque nœud :
   - `.bind` / `.lambda` / `.letrec` : ajoute le nom au `Scope`
   - `.sym` en position **expression** (pas en tant que payload de
     `.apply`, `.bind`, `.lambda`) : `scope.lookup(name)` ; si
     absent → diag.
3. Distinction clé : `.sym` **référence** vs `.sym` **définition**
   (payload de `.bind` / `.lambda`) — le walker connaît la
   position, le scan naïf ne la connaît pas.

## Effort estimé

1 session. Bloqué par : `Bridge` doit exposer `roots` + `Scope`
(cf. `_module_value_ref_bug.md`, `_check_validator_bug.md`).

## Tests à écrire (pré-commit)

- 6 cas unitaires (x = 1+1 ✓, x = y+1 ✗, etc.)
- Non-régression : `lib/os/scheduler.hvn`, `tests/test_data.hvn`,
  `tests/test_stream.hvn`, `lib/std/result.hvn` (unbound=0 partout).
- Non-régression : `add x y = x + y` (0 erreur).

La non-régression sur les fichiers existants est **bloquante**.
Sans elle, on ne commit pas.
