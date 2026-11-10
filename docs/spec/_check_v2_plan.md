# Check v2 — détection des variables non définies (plan)

**Statut** : walker v2 implémenté (`46e1a70`, opt-in via
`HEAVEN_CHECK_STRICT=1`). 6 cas unitaires verts. Faux positifs
résiduels sur fichiers existants (Session 45).
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

## Session 44 — Implémentation v2 (opt-in)

`scope_check.checkUnboundV2` : walker AST sur `Bridge.roots`,
2 passes (collecte définitions, walk références), filtres
empiriques (builtins étendus, `*_decl`, nom qualifié, `comment`).

**Wiring opt-in** : `HEAVEN_CHECK_STRICT=1` active le walker. Par
défaut, `heaven check` garde le comportement tree-sitter + typer.

Tests unitaires (6 cas verts) : `x = 1 + 1` ✓, `x = y + 1` ✗,
`f n = n + 1` ✓, `f n = m + 1` ✗, `x = x + 1` ✓, `f x = y + 1` ✗.

Non-régression mode défaut : `scheduler.hvn` unbound=0 (le walker
n'est pas appelé), registry 24/24, build 0 erreur.

## Session 45 — Fix `buildEqDecl`

### Ce qui a été corrigé

`buildEqDecl` avait 3 bugs :

1. **Name perdu** sur les clauses composites : `map f (Cons x rest) = ...`
   retournait `bind 'f'` (fallback `identifier`) au lieu de `bind 'map'`.
2. **Body non parsé** : `pick_higher t1 t2 = t1` retournait `sym 'eq_decl'`
   parce que le body `t1` était de tag `identifier` et skippé AVANT la
   vérification `seen_eq`.
3. **Patterns textuels** : `(Cons x rest)` restait une string brute dans
   `param_names`, jamais décomposée en `x`, `rest`.

Fix : prise du body strictement après `=`, quel que soit le tag ;
descente récursive dans les `pattern` pour collecter les `identifier` ;
name via `getFieldText(node, "name")` (déjà OK).

### Effet mesuré

| Fichier | Avant | Après |
|---|---|---|
| `pick_higher t1 t2 = t1` isolé | `sym 'eq_decl'` | `bind 'pick_higher'` ✓ |
| `task_id (MkTask i _) = i` isolé | (probablement eq_decl) | `bind 'task_id'` ✓ |
| `scheduler.hvn` unbound | 16 | **12** |
| `test_stream.hvn` unbound | 2 | 2 |

### Limitation restante — tree-sitter, pas walker

Les 14 unbound résiduels (`scheduler.hvn` × 12, `test_stream.hvn` × 2)
ne viennent PAS du walker. Ils viennent de **tree-sitter qui ne parse
pas certains fichiers** :

- `scheduler.hvn` : `heaven parse` montre 3 zones ERROR
  ([7:23-10:22], [22:19-25:18], [27:14]). Les clauses dans ces zones
  (`pick_higher`, `member`, `task_id`, `run_n`) ne deviennent jamais
  des `bind` dans `Bridge.roots` → walker les voit unbound.
- `test_stream.hvn` : `data Stream a = ...` (paramètre de type) n'est
  pas parsé par la grammaire. Tout le fichier tombe en cascade ERROR.
  Cf. `_check_validator_bug.md` (les deux parseurs divergent).

**Le walker est correct sur l'AST qu'il reçoit.** L'AST reçu est
incomplet pour ces fichiers.

### Prochaine étape (Session 46+)

- **Option B** : patcher `vendor/tree-sitter-heaven/grammar.js` pour
  supporter `data X a = ...` et les clauses multi-lignes. ~1-2h,
  dépendance externe (vendor), risque moyen.
- **Option C** : fallback `nativeToSExpr` quand `ts_node_has_error(root)`
  → le bridge ne consomme que tree-sitter, gros refactor.
- **Statu quo** : `HEAVEN_CHECK_STRICT=1` activable manuellement sur
  fichiers qui parsent bien (`registry.hvn`, fichiers neufs).

Décision Session 45 : **statu quo + fix partiel commité**. Le walker
est prêt, la limitation est documentée et externe au walker.

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
