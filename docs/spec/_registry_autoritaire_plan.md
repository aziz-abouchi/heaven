# Registre autoritaire — plan et état (2026-11-10)

**Statut** : B1-B4 livrés. B5-B6 à venir.
**Fichier source** : `lib/tool_registry.hvn` (16 tools).
**Voir aussi** : `_tool_audit_2026-11-09.md`, `_if_qualified_bug.md`,
`_module_value_ref_bug.md`.

## Contexte

Avant le 2026-11-10, trois représentations des tools coexistaient :

| Représentation | Nb tools | Utilisée par |
|---|---|---|
| `lib/tool_registry.hvn` | 16 | rien (dead code) |
| `lib/mcp/` (`server.hvn` + `tools.hvn`) | 5 | `lib/mcp/server.hvn` (jamais lancé) |
| `src/runtime/mcp_server.zig` (`mcp_tools[]`) | 9 exposés (11 dispatchés) | `heaven mcp` |

Un seul des trois était actif. Les 5 tools Heaven étaient listés
nulle part, et les 11 natifs étaient hardcodés dans un array.

## Objectif

`lib/tool_registry.hvn` devient la source de vérité unique. Les
deux serveurs (Zig et Heaven) le consomment. Un tool déclaré est
listable et callable.

## Sous-chantiers

### B1 — Sérialisation JSON (livré, `a1dfcd3`)

Ajout à `lib/tool_registry.hvn` :

    tool_to_json (Tool n d p e k) = "{" + qstr "name" + ... "}"
    tool_list_json TLNil = ""
    tool_list_json (TLCons t rest) = ...
    registry_to_json _ = "{" + qstr "tools" + ":[" + ... + "]}"

Tests : `tests/mcp/registry_export.hvn` (12 assertions). Note
importante : pas de `{` ni `}` littéraux dans les assertions
(le splitter de `test_runner.zig` les absorbe).

### B2 — `tools/list` lit le registre (livré, `8113a49`)

`mcp_server.zig` :

- `ensureHeaven()` charge `import "lib/tool_registry.hvn" as TR`
  une fois.
- `formatToolsList` appelle `heaven.eval("(TR.registry_to_json 0)")`
  et cache la string (~700ms premier appel, 0ms ensuite).

Effet : `tools/list` retourne 16 tools (avant : 9).

### B3 — `tools/call` dispatch les 5 Heaven (livré, `8686629`)

`callTool` :

- 5 noms (`echo`, `time_now`, `time_ms`, `fs_read`,
  `count_chars`) → `callHeavenTool` → `TT.run_tool`.
- Body JSON construit en Zig, échappement des `"`, strip des
  quotes externes du résultat.
- `writeJsonValue` : sérialisation JSON minimale indépendante de
  `std.json.stringify` (API instable entre Zig 0.13/0.14/0.15).

Effet : les 16 tools sont callables (avant : 11 natifs + 5
`unknown tool`).

### B4 — Test différentiel MCP ≡ Heaven (livré, `321a65c`)

`scripts/mcp_diff_check.py` : 8 cas (5 tools Heaven, echo×2,
count_chars×2, time_now, time_ms, fs_read OK+KO). Compare
`heaven mcp` et `heaven run`. Intégré dans `ci-preflight.sh`.

Couvre `invoke_MCP ≡ invoke_Heaven`. UTCP (B6) ajoutera
`invoke_UTCP`.

Note : les 11 tools natifs (kind=1) ne sont pas couverts (pas
d'équivalent Heaven-side direct). B4b si pertinent.

### B5 — `inputSchema` enrichi (à venir)

Le registre v2 simplifie `inputSchema` à `{"type":"object"}`. Les
`properties`/`required` détaillés de `mcp_tools[]` (Zig) sont
perdus. À enrichir dans `Tool` :

- Ajouter un champ `schema: Str` (JSON brut) au `data Tool` ?
- Ou générer depuis `kind` (convention par type de tool) ?
- Décision à prendre.

### B6 — UTCP v1 (à venir, session dédiée)

Aucune ligne de code. Adaptateur basé sur `lib/tool_registry.hvn`.
Test d'équivalence `invoke_MCP ≡ invoke_UTCP ≡ invoke_Heaven`.

## Décisions architecturales prises

1. **Registre Heaven = source de vérité**. Pas de duplication
   côté Zig.
2. **`kind` (0=heaven, 1=native)** distingue les implémentations.
   Le dispatch utilise `kind` implicitement via les noms.
3. **Cache de la sérialisation** dans `McpServer` (mémoire).
4. **Fallback sur échec d'import** : `tools/list` retourne
   `{"tools":[]}` + warning, pas de crash.

## Limitations connues

- `inputSchema` simplifié (cf. B5).
- 2 tools restent désactivés (`egraph_query`, `heaven_expand`).
- 3 tools restent expérimental/suspect (`heaven_integrate`,
  `heaven_solve`, `heaven_theorems`).
- `lib/mcp/server.hvn` n'est toujours pas lancé par une commande
  (`heaven mcp2` à créer ? Ou déprécier ?).
