# Résolution des imports dans heaven_eval (2026-10-26)

## Problème

`heaven_eval.hvn` évalue des fichiers `.hvn`, mais ne sait pas
résoudre `import "..."`. Le parser (`heaven_parse.hvn:108-111`)
produit bien `EImport Str Str`, mais `eval_top` n'avait aucun case
pour ce tag — il tombait dans le fallback `eval`, qui échouait
silencieusement.

## Ce qui a été fait (P3, 2026-10-26)

Patch `eval_top` case `EImport` : retourne
`VErr "EImport: resolution non supportee en .hvn"` au lieu du
silence. C'est un **message clair**, pas un fix.

Régression 18/18 verte. Chemin normal (`--eval-file` avec loader
Zig) intact.

## Pourquoi ce n'est PAS un fix .hvn

Résoudre un import demande :
1. Lire le fichier (`fs:read` — magic Zig)
2. Parser son contenu (`.hvn` peut le faire)
3. Évaluer récursivement (`.hvn` peut le faire)

Mais `fs:read` est un magic Zig, pas accessible depuis
`heaven_eval.hvn` sans créer une dépendance circulaire
(loader → évaluateur → loader).

## Le vrai fix (session dédiée, P3-bis)

**Pre-pass Zig** dans `runEvalFile` (`src/runtime/test_runner.zig`) :

1. Parser le fichier source
2. Extraire les `EImport` de premier niveau
3. Pour chaque import : lire + parser + évaluer récursivement,
   accumuler l'environnement
4. Évaluer le fichier principal dans cet environnement

~30-40 lignes Zig. Cutoff 3 blocs.

## Alternative long terme

Quand `heaven_eval.hvn` sera le seul évaluateur (après E1-E3),
exposer `fs:read` comme primitive `.hvn` (via `lib/syscall/`) et
résoudre les imports dans `eval_top` directement. C'est le chemin
propre, mais il demande que `heaven_eval` puisse appeler
`raw_syscall` — ce qui est possible (voir `lib/syscall/linux_x86_64.hvn`).

## Voir aussi

- `docs/spec/_decisions.md` : D6 (modules minimaux)
- `_emancipation_roadmap.md` : E1-E10
