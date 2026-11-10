# Bug : heaven check / parse (tree-sitter) faux positifs (2026-11-09)

**Statut** : identifie, non corrige.
**Impact** : NON bloquant pour l'execution (voir plus bas).
**Contournement** : utiliser `--run-test`, pas `check`.

## Symptome

`heaven check` et `heaven parse` rapportent des erreurs de syntaxe sur
des fichiers qui compilent et s'executent parfaitement via
`--run-test`. Exemples :

- `tool_registry.hvn` : `check` sort 2 erreurs (7:22 et 21:100),
  `--run-test` enregistre les 13 clauses sans erreur.
- `os/scheduler.hvn` : `check` sort 2 erreurs (7:24 et 22:20),
  `--run-test` enregistre les 8 clauses sans erreur.
- h8 (import + blank + data + data) : `check` sort
  `[7:21-8:23] Str Int Int / data ToolList ... MISSING ; at 8:44`,
  `--run-test` passe les 3 declarations.

## Cause racine

`heaven check` (et `heaven parse`) utilisent tree-sitter avec une
recuperation d'erreur instable. Les positions rapportees sont fausses
(elles pointent a la fin d'une ligne alors que l'erreur pretendue est
au debut), et dependent du contexte (meme fichier minimal OK, fichier
complet KO). Ce n'est PAS le meme chemin que `--run-test`
(`nativeToSExpr` + `parseSExpr` + `engine.eval`), qui fonctionne.

Le message du commit `b93060f` ("parser ne gere pas = dans
commentaires") etait faux : le fichier `tool_registry.hvn` ne contient
aucun `=` dans un commentaire (hexdump ASCII propre), et passe
entierement via `--run-test`.

## Contournement

Pour valider un fichier `.hvn` :

    ./zig-out/bin/heaven --run-test <file.hvn>   # reel
    # au lieu de
    ./zig-out/bin/heaven check <file.hvn>        # faux positifs

## Effet sur le walker unbound (Session 45, fix 2026-11-10)

Le walker `checkUnboundV2` (`src/core/scope_check.zig`) travaille sur
l'AST produit par tree-sitter. Quand tree-sitter échoue (`data X = A | B`
non parsé), le Bridge ne produit pas de `bind` pour les clauses
suivantes, et le walker les voit comme unbound. Ce n'est pas un bug
du walker — c'est une conséquence directe de ce bug.

Fix du 2026-11-10 (`3dba5e5`) : filtre `ERROR` et les payloads
multi-lignes. Mesure : `lib/` 349 → 269 diagnostics (le résidu 269
est la cascade tree-sitter).

Cf. `_unbound_walker_gaps.md` pour les chiffres et le plan.

## Priorite

Basse. Un fix necessiterait de remplacer ou de patcher tree-sitter
(ou d'aligner `check` sur `nativeToSExpr`). Non bloquant pour le
registre, MCP, UTCP, ni l'execution.
