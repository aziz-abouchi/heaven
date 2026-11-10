# Bug : parseSExpr fragmente les strings avec `\"` échappés (2026-11-10)

**Statut** : corrigé (commit à venir).
**Fichier** : `src/core/expr_parser.zig`, fonction `parseSExpr`.
**Découvert par** : test différentiel MCP ≡ Heaven (B4, `scripts/mcp_diff_check.py`).

## Symptôme

Un appel `TT.run_tool` avec un body JSON en argument direct (non
passé par une variable) échoue sur les valeurs contenant des
espaces :

    (TT.run_tool "{\"name\":\"echo\",\"arguments\":{\"text\":\"hello world\"}}")
    → [eval error] error.UnboundVariable

Mais le même body passé par une variable bindée marche :

    body = "{\"name\":\"echo\",\"arguments\":{\"text\":\"hello world\"}}"
    (TT.run_tool body)
    → "hello world"

Et sans espace dans la valeur, le littéral direct marche :

    (TT.run_tool "{\"name\":\"echo\",\"arguments\":{\"text\":\"hi\"}}")
    → "hi"

## Cause racine

Le tokenizer manuel de `parseSExpr` (utilisé pour décomposer les
S-expressions) gère `in_str` mais ignore les échappements :

    for (inner, 0..) |ch, idx| {
        if (in_str) {
            if (ch == '"') in_str = false;   // ← ignore '\'
            continue;
        }
        switch (ch) {
            '"' => { in_str = true; },
            ...
        }
    }

Sur `"{\"name\":..."`, le `\` est ignoré, puis le `"` suivant
**termine** la string prématurément. Le reste (`name\":\"echo...`)
est fragmenté en tokens parasites. Le premier token devient un nom
inconnu → `UnboundVariable`.

Avec une variable bindée, le path est différent (assignation →
`nativeToSExpr` → parser Pratt), qui gère `\"` correctement depuis
G.40 (`src/core/expr.zig` ligne ~84-99).

## Fix (commit à venir)

Ajouter `skip_next` dans la boucle `in_str` :

    var skip_next = false;
    for (inner, 0..) |ch, idx| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        if (in_str) {
            if (ch == '\\') {
                skip_next = true;
                continue;
            }
            if (ch == '"') in_str = false;
            continue;
        }
        ...
    }

Le `\` met `skip_next = true`, le `"` suivant est consommé sans
terminer `in_str`.

## Tests (pre-commit)

| Cas | Avant | Après |
|---|---|---|
| `TT.run_tool` avec body `hello world` (littéral direct) | `UnboundVariable` | `hello world` ✓ |
| `TT.run_tool` avec body `hi` | `hi` ✓ | `hi` ✓ |
| `(string_length "a\"b")` | 3 ✓ | 3 ✓ |
| `scripts/mcp_diff_check.py` (8 cas) | 7/8 | **8/8** ✓ |

## Impact

- **MCP tools Heaven** : `echo`, `count_chars`, `fs_read` acceptent
  maintenant les valeurs avec espaces via body JSON direct (cas
  d'usage réel pour un client MCP qui ne binde pas de variable).
- **`TT.run_tool`** : utilisable avec JSON inline, pas seulement
  via variable.
- **Pas de régression** sur les strings avec `\"` (test 3).

## Voir aussi

- `docs/spec/_registry_autoritaire_plan.md` (B1-B4)
- `scripts/mcp_diff_check.py` (test qui a révélé le bug)
- `src/core/expr.zig` lignes 84-99 : G.40 fix (même bug dans
  `nativeToSExpr`, corrigé antérieurement)
