# Bootstrap — Différentiel E (HP vs Zig)

> Généré par le différentiel du 2026-10-13 (session soir 7).
> Fichier MANUEL — aucun générateur ne le touche (ni docgen.py, ni status_gen.py).
> Source de vérité du DIFFÉRENTIEL : ce fichier. Source de vérité du STATUT : docs/STATUS.md (généré).

## Premier passage : 31/81 fichiers (38%)

HP (`lib/heaven_parse.hvn`) parse chaque fichier du repo (tests + core + core/std + lib).
Le count est comparé à la vérité Zig (règle d'indentation du std_loader — **approximative** :
9 fichiers à splits, GT < vérité Zig). Le count rendu désigne la forme fautive
(`parse_file` tronque au premier PErr).

### Census des manques (par fréquence d'impact)

| # | Famille | Fichiers | Exemple bloquant | Fix |
|---|---------|----------|------------------|-----|
| 1 | `data` paramétré | 7 | `data Stream a = Cons a (Stream a) | End` | data_scan : consommer après `=` jusqu'au prochain top-level minuscule/`|` |
| 2 | `test` corps non-parenthésé | 6 | `test "n": a == b`, `<<4:4,5:4>>`, hex | test_body : wrapper le corps en S-expr |
| 3 | Splits (HP > GT) | 9 | `string.hvn` GT=10 HP=13 | **PAS bugs HP** — GT approximative + paren en fin d'argument de def |
| 4 | Autres | 24 | assert_eq nu, `x + 0 => x`, guards `|`, `fn`, theorem/prove/axiom, module, sig | Sucre top-level, cibles individuelles |
| 5 | CRASH | 1 | `core/std/list.hvn` | À isoler (seul crash réel en RF) |

### Fichiers passants (31)

tests : array, base, bigint, continuations, effects_rec, effects_rec_nested, eq, eval, free,
hashmap, io_stream, laws, lens, lexer, list, memory, option, ord, pair, parser, prompt_depth,
recursion, scheduler, stream_lazy, string — + core : book_suite, hello, test_factorial —
+ lib : heaven_eval (**41 formes — l'évaluateur métacirculaire est parsable par HP**), heaven_parse (130).

### Notes de méthode

- **Count-based** : un fichier « passant » est bien *découpé*, pas forcément *correct*
  (guards et `fn` parsent sans erreur mais sémantiquement faux).
- Le différentiel sémantique (comparaison des formes) viendra après le census.
- Re-diff après chaque extension HP : le count désigne la forme fautive directement.
