# Spec formelle du langage Heaven

Chantier en cours (STATUS item 8).

## Spec cœur

- `_audit.md` — inventaire descriptif du dispatch `eval` (Phase 1).
- `heaven.md` — la spec proprement dite (Phase 2, à venir).
- `grammar.ebnf` — EBNF pure (Phase 2, à venir).
- `errors.md` — catalogue des erreurs (Phase 2, à venir).

## Conventions et style

- `_style_infix.md` — politique infixe par défaut (opérateurs,
  branches d'`if`). Formes préfixes proscrites (`(== a b)`, etc.).
- `_h1_qualified_sym.md` — Sym qualifié (`module.Sym`), comparaison
  structurelle (N1 résolu, N2 ouvert).
- `_sicp_lineage.md` — table de correspondance SICP ch. 1-5 → modules
  Heaven (ce que Heaven ajoute / perd).

## Bugs actifs (documentés, non corrigés)

- `_if_qualified_bug.md` — noms qualifiés dans les branches d'un `if`
  (corrigé 2026-11-09, commit `55430bf` ; conservé pour référence).
- `_check_validator_bug.md` — `heaven check` / `parse` (tree-sitter)
  faux positifs sur fichiers valides. Contournement : `--run-test`.
- `_module_value_ref_bug.md` — référence qualifiée à une valeur de
  module (`TR.registry_builtin`) ne se résout pas cross-module.
  Contournement : exposer comme fonction zéro-arg.
- `_heaven_prove_kernel_bug.md` — `Heaven.evalProve` retourne
  `Ok("Usage: …")` sur input invalide, panic sur tactics block.
  Contournement : `heaven_prove` limité à `a == b`.
- `_integrate_bug.md` — `Heaven.integrate("x^2")` retourne
  `(* x^2 x) + C` au lieu de `x^3/3 + C`. Marqué EXPERIMENTAL.
- `_tool_audit_2026-11-09.md` — audit des 16 outils MCP : 6 stables,
  3 faux, 1 crash, 1 suspect, 5 invisibles via `heaven mcp`.
  `egraph_query` et `heaven_expand` désactivés (`3f878fc`).

## Plans et chantiers

- `_check_v2_plan.md` — détection des variables non définies.
  Fondation `Bridge.roots` en place (`7430b15`), walker à implémenter.

- `_sexpr_escape_bug.md` — `parseSExpr` fragmente les strings avec
  `\"` échappés (corrigé `66b8b25`).

Méthodologie : voir `_audit.md`, section « TODO Phase 2 ».

## Session 48 — nouveaux documents (2026-11-10)

- `_qtt_fn_design.md` — décision QTT fn : `linear` nu (4ccf1bf).
- `_qtt_bindings_bugs.md` — 3 bugs pipeline `let linear`.
- `_selfhosting_roadmap.md` — roadmap auto-hébergement (Phase A+B, Session 49).
- `_registry_autoritaire_plan.md` — plan B1-B5 MCP (B5 a38bfc6).
- `_unbound_walker_gaps.md` — limites walker unbound (269→266 sur lib/).
