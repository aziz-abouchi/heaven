# Audit des 16 outils MCP exposés (2026-11-09)

**Contexte** : audit post-fusion registre v2 (`5875e83`).
Motivation : `heaven_prove` et `heaven_integrate` étaient documentés
comme défaillants. L'audit couvre les 14 autres.

**Méthode** : `heaven mcp` + `tools/call` sur chaque outil avec un
argument minimal, via stdio JSON-RPC. Un `head -1` pour capturer la
première ligne de réponse (ou le panic).

**Verdict global** : sur 16 outils déclarés au registre, **6 sont
fiables et exposés**, 3 produisent un résultat faux, 1 crash, 1
suspect, 5 invisibles via `heaven mcp`, 1 non testé.

## Table complète

| Outil | Réponse observée | Verdict |
|---|---|---|
| `heaven_eval` | `4` | **stable** |
| `heaven_derive` | `(* 2 x)` | **stable** |
| `heaven_simplify` | `x` | **stable** |
| `heaven_prove` | `{"proved":true/false,"method":"kernel"}` ou `{"method":"semantic"}` | **stable** (kernel réactivé `805cdbe`, 2026-11-10 : `prove NAME by { tactics }` + fallback `a == b`. Cf. `_heaven_prove_kernel_bug.md`) |
| `mlcpd_parse` | `{"nodes":0,"language":"unknown"}` | **stable** (mais `language:unknown` sur `{}` à investiguer) |
| `heaven_theorems` | `"theorems"` (littéral) | **suspect** (retourne le mot-clé, pas la liste des axiomes) |
| `heaven_integrate` | `x^2 → (* x^2 x) + C` | **faux** (cf. `_integrate_bug.md`) |
| `heaven_solve` | `x+1=0 → "tout x (identite)"` | **faux** (non documenté avant cet audit) |
| `heaven_expand` | debug `simplifyMath: …` sur stdout, pas de JSON-RPC | **cassé** (fuite de debug + protocole rompu) |
| `egraph_query` | `thread … panic: Invalid free` | **crash** (tue le serveur MCP) |
| `mlcpd_equiv` | non testé | **?** |
| `echo` | `error: unknown tool 'echo'` | **invisible** via `heaven mcp` |
| `fs_read` | `error: unknown tool 'fs_read'` | **invisible** |
| `count_chars` | `error: unknown tool 'count_chars'` | **invisible** |
| `time_now` | `error: unknown tool 'time_now'` | **invisible** |
| `time_ms` | (assumé idem `time_now`) | **invisible** |

## Découvertes majeures

### 1. `egraph_query` panic

    thread 4958 panic: Invalid free

Tuer un serveur MCP sur un tool call est **inacceptable**. Cause
probable : `heaven.eval` (ou la conversion en JSON) libère une
chaîne partagée. À tracer avec `gpa` + stack traces (binaire strippé :
`Unable to open debug info`).

### 2. `heaven_expand` rompt le protocole JSON-RPC

Sortie observée : `simplifyMath: left_is_zero=false, right_is_zero=false, …`

Deux hypothèses :
- debug print non retiré (`@import("std").debug.print` ou équivalent)
  qui écrit sur stdout au lieu de stderr, cassant le protocole.
- `heaven.eval` sur `(x+1)^2` retourne une chaîne non gérée.

À isoler : `echo '(x+1)^2' | ./zig-out/bin/heaven mcp` (test direct)
vs `heaven run` sur `(x+1)^2`.

### 3. 5 tools Heaven invisibles via `heaven mcp`

`heaven mcp` utilise **uniquement** `src/runtime/mcp_server.zig`. Les
5 tools déclarés dans `lib/mcp/handlers.hvn` + `lib/mcp/tools.hvn` ne
sont **pas** dans `mcp_server.zig` → `unknown tool`.

Conséquence : le registre v2 déclare 16 tools, mais `heaven mcp` n'en
expose que 11 (les 11 natifs Zig). Les 5 Heaven sont dans un serveur
qui n'est pas lancé par cette commande.

Trois options (à décider) :
1. Brancher les 5 Heaven dans `mcp_server.zig` (via `heaven.eval` de
   code Heaven appelant `lib/mcp/tools.hvn`).
2. Lancer `lib/mcp/server.hvn` via une nouvelle commande `heaven mcp2`
   (deux serveurs distincts).
3. Retirer les 5 du registre (ils ne sont accessibles par aucune
   commande).

## Actions immédiates

1. **Retirer `egraph_query` et `heaven_expand` de `mcp_tools`** dans
   `mcp_server.zig` — un serveur ne doit pas exposer un tool qui
   panic ou rompt le protocole.
2. **Marquer `heaven_solve` et `heaven_integrate` comme expérimental**
   (déjà fait pour integrate, à faire pour solve).
3. **Décider** des 5 tools invisibles.

## Actions différées

- Fix `egraph_query` : tracer la libération de chaîne (session dédiée).
- Fix `heaven_expand` : retirer le debug + vérifier la sortie.
- Fix `heaven_solve` : algèbre d'équations (session dédiée).
- Fix `heaven_theorems` : retourne `"theorems"` — vérifier si c'est
  un eval littéral ou un vrai listing.
- Investiguer `mlcpd_parse language:unknown` sur `{}`.

## Non testé dans cet audit

- `mlcpd_equiv` : nécessite deux JSON MLCPD valides. À tester dans un
  audit complémentaire.
- Comportement sous charge / concurrence : hors périmètre.

## Voir aussi

- `_integrate_bug.md`
- `_heaven_prove_kernel_bug.md`
- `_check_validator_bug.md` (tree-sitter faux positifs)
- `lib/tool_registry.hvn` (registre v2)
