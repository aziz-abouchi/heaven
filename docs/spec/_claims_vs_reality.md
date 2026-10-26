# Claims vs reality — registre d'affirmations vérifiables

## But
Chaque affirmation du README, du livre ou des specs est confrontée
au code réel. Pas de "ça marche" sans test pertinent. Pas de
"c'est faux" sans preuve.

## Règle des 5 statuts
1. Implémentée et testée — test pertinent vert
2. Partiellement implémentée — sous-ensemble fonctionne
3. Prototype — existe, sans garantie générale
4. Spécification — décrit, pas réalisé
5. Non vérifiée — éléments insuffisants

Distinguer "non implémenté" (absent) de "non vérifié" (pas examiné).

## Format
| Affirmation | Source | Implémentation | État réel | Preuve | Écart | Action |
|---|---|---|---|---|---|---|

| handle couvre catch/bracket/local | livre ch.6 | handle shallow/final + handle-rec (D8, one-shot) | 2 partiel | _concurrency.md D8 | livre présente handle comme complet | ch.6 : distinguer handle shallow vs handle-rec |
| Type 0 / >>> arité | grammar.js vs GRAMMAR.md | Type 0 -> ArityMismatch, >>> sucre astra-core | 3 prototype | test manuel | doc diverge de grammar.js | regénérer GRAMMAR.md depuis grammar.js |
| CIC quotients + proof irrelevance | livre ch.8 | kernel ~780 L, type-check limité | 5 absent | STATUS ❌, ❌ | corrigé 2026-10-26 | ch.8 : sections "État réel" ajoutées (commit suivant) |
| RFC-0001 modules extraits | STATUS.md | import.zig, etc. | 2 partiel | pas de test indépendant | livre décrit monolithique | ch.18 : mettre à jour |
| Acteurs séquentiels mono-thread | livre ch.13 | prototype, mailbox FIFO | 3 prototype | lib/os/scheduler.hvn coopératif | livre présente "plateforme uniforme" | ch.13 : dire "prototype séquentiel" |
| status.json source de vérité | STATUS.md généré | oui | 1 implémentée et testée | fichier généré | aucun | aucune |
| HoTT / Path rank-1 | livre ch.22 | MkPath Int Int Int | 3 prototype (sans règles) | test_hott_path 14/14 | corrigé 2026-10-24 | ch.22 : sections "Dans Heaven aujourd hui" |
| HIT path_constructor | livre ch.22 | grammar parse, elab.zig ignore from/to | 5 silent discard | grep from/to elab.zig | corrigé 2026-10-24 | ch.22 : "parse, pas éliminateur" |
| QTT enforced | livre ch.26 | LinearChecker branché sur cmdQTT shell seulement | 2 partiel (façade) | lib/qtt/linear.hvn 8/8 | corrigé 2026-10-26 | ch.26 : 4 patches (intro, exemples, peut vérifier, livré) |
| Holes (`_`) | livre ch.2 | tous les `_` partagent l id 0 | 5 absent | pas de test holes | livre présente comme feature | ch.2 : retirer ou marquer "spécification" |
| TCO mutuelle | livre ch.4 | limitations SCC | 4 spécification | pas de test TCO mutuel | livre présente comme acquis | ch.4 : "TCO simple OK, mutuelle à démontrer" |
| Table des versions | SUMMARY.md | 0.5 historique, 0.6 ACTUEL | 1 corrigé 2026-10-26 | grep ACTUEL = 1 ligne | résolu | commit 7f08c57 + SUMMARY fix |
| Inférence de types (inc -> Int -> Int) | livre ch.2 | TypeEnv.infer retourne "Int" toujours | 5 stub | types.zig:266 | ch.2 présente comme acquise | corrigé 2026-10-26 : sections "État réel" |
| Six primitives (lit/sym/apply/bind/lambda/relation) | livre ch.18 | tags réels : apply/sym/lit/bind/lambda/other | 2 partiel (5 câblées, relation spécifiée) | grep relation expr.zig = 0 | livre liste relation comme primitive | corrigé 2026-10-26 : encadré + légende + conclusion |
