# RFC — Heaven Tool Registry, MCP et UTCP

**Date** : 2026-11-09
**Statut** : proposition
**Auteur** : aziz-abouchi

## Contexte

Heaven expose un serveur MCP (`lib/mcp/`, 213 l.). Deux limites :

1. **Un seul protocole** — MCP cible les LLM, pas les transports natifs
   (REPL, CLI, LSP, RPC Heaven-à-Heaven, WASM).
2. **Pas de modèle commun** — chaque intégration déclare ses outils.

## Architecture à trois couches

| Couche | Rôle | Fichier cible |
|---|---|---|
| **Heaven Tool Registry** | Modèle commun : outils, schémas, types, capacités, permissions | `lib/tool_registry.hvn` |
| **MCP** | Adaptateur protocolaire vers les LLM | `lib/mcp/` |
| **UTCP** | Découverte et invocation via transports natifs | `lib/utcp/` |

Le registre est la **source de vérité**. MCP et UTCP sont des **vues**.
Ajouter un outil = 1 entrée registre + les deux adaptateurs le voient.

## Critère architectural (non négociable)

Pour un même outil `t` et une même entrée `x` :

    invoke_MCP(t, x) ≡ invoke_UTCP(t, x) ≡ invoke_Heaven(t, x)

- **Contrat sémantique** : mêmes entrées → mêmes sorties.
- **Permissions** : un outil interdit en Heaven est interdit en MCP et UTCP.
- **Erreurs** : mêmes codes, mêmes messages.

Un test différentiel (`tests/tool_registry/diff_mcp_utcp.hvn`) doit vérifier
l'équivalence sur chaque outil déclaré. Tant qu'un outil n'a pas ce test, il
n'est pas exposé.

## Cible du registre

    data Tool = Tool {
      name    : Str,
      schema  : Schema,         -- types params + retour
      perms   : [Permission],   -- lecture, écriture, exécution, réseau
      effect  : Effect,         -- Pure | IO | Async | Remote
      handler : Str -> Result,  -- nom du handler Heaven
    }

## Adaptateurs

**MCP** : mappe le registre vers `tools/list` et `tools/call`.

**UTCP** : API stable `utcp_list()`, `utcp_call(name, args)` +
transports stdio (LSP), socket Unix (REPL), HTTP (Web), Heaven-RPC (distribué).

## Roadmap

| Ordre | Chantier | Effort |
|---|---|---|
| 1 | Leak `fn` (session 39) | 30-45 min |
| 2 | **Pause, stabilisation** | — |
| 3 | **Heaven Tool Registry** (impl) | 2-3 sessions |
| 4 | Adaptateur MCP v1 | 1 session |
| 5 | Adaptateur UTCP v1 (stdio) | 1 session |
| 6 | Test différentiel MCP ≡ UTCP ≡ Heaven | 1 session |
| 7 | Multiplicités fn/params (QTT) | 1-2 sessions |
| 8 | `[Int]` array literal | 1 session |
| 9 | WASM `unreachable` | 1-2 sessions |
| 10 | Self-host complet | 6-9 sessions |
| 11 | HoTT / Cubical | RFC |

## Non-objectifs

- Modifier le runtime existant.
- Refactoriser `lib/mcp/` immédiatement.
- Ajouter des protocoles au-delà de MCP et UTCP.

## Décision demandée

1. Valider l'architecture à trois couches.
2. Valider le critère d'équivalence MCP ≡ UTCP ≡ Heaven.
3. Prioriser le Tool Registry après la pause (session 40+).
