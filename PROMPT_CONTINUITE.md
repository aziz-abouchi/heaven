# 📋 Prompt de continuité — Projet Heaven
# Session du 2026-09-28 — SUITE 77/77, soundness verrouillée

## 🎯 Contexte
Heaven : langage expérimental en Zig. Dépôt : github.com/aziz-abouchi/heaven
Machines : Linux x86_64 (~/Desktop/Dev/langage/boot) + macOS ARM.
HEAD : dd8e61c — "fix(parse): infix parenthésé — nativeToSExpr avant tree-sitter"

## ✅ ÉTAT

### Suite : 77/77 + 15 neutral, memory clean — INTÉGRALEMENT VERTE
Tests unitaires : 170/171 + 1 skip.
Soundness : « theorem a = b » REFUSÉ. La trajectoire complète :
- a=b, a-b=b-a, a/b=b/a, a+b=b+c : ✗ refusés (6 couches traversées,
  commit d2849f7 — voir git log pour l'histoire)
- t_double_zero ✓, t_distrib ✓ (le fix parsing a refermé les deux :
  l'infix parenthésé (x+0)+0 était routé vers tree-sitter → arbre
  non-foldable. Fix : nativeToSExpr AVANT tree-sitter dans
  parse_ops.parseExpression — src/core/commands/parse.zig)
- Bonus : le codegen LaTeX produit enfin du LaTeX correct
  ({x + y}^{2})

### Architecture
- src/kernel/ : UNIFIÉ (kernel.zig façade + peano.zig [moteur prove,
  pool u32 iso-morphique Store] + CIC [quotients, Eq/refl])
- Pipeline compilation UNIQUE : tree-sitter → syntax/ast → RFC-0001
  lowering → core/expr (6 primitives) → backends MIR/C/WASM/JS/LaTeX
- Refactorisation D4 en cours : commands.zig découpé en modules
  (parse.zig, cas.zig, proofs.zig, format.zig — batch 5 fait).
  Voir docs/DECISIONS.md

## 📋 File priorisée

1. KERNEL-AUTHORITY — PRIORITÉ ABSOLUE. 9 writers de verified
   (8 proof_core + proofResult commands.zig). Kernel.check unique
   sur Term = seule architecture où le bug soundness ne renaît pas.
   Pont exprToTerm trivial côté peano (pools iso-morphiques).
2. AUDIT conversion.zig — +617 lignes sur le MAC
   (~/Desktop/Dev/heaven-conversion-audit.diff). À récupérer
   (committer depuis le Mac sur branche audit/conversion, puller).
   ORIGINE INCONNUE — à déterminer.
3. FALLBACKS importExpr — occurrences restantes (format.zig:14
   [latex], commands.zig l.267 [eval parenthésé], l.642, l.680,
   typeOf ~l.825, parse.zig:327 [lambda]). Chacun : fallback
   légitime (eval REPL best-effort) ou masque d'échec (→ expliciter) ?
4. PERF t_distrib : 1360ms (60% du temps suite). Détection point
   fixe par nodeHash au lieu de comparaison d'Id (b2 == current
   ne détecte jamais la convergence — nouveaux Ids à chaque passe).
5. format.zig:17 : commentaire orphelin « // ← ajouter » à retirer.
6. Revalidation web (bash build.sh + page /test) — pas refaite
   depuis les fixes core.

## 📌 Règles gravées (ne pas réapprendre)

1. La soundness ne se désactive pas pour faire passer des tests
   (le return error.UnboundVariable COMMENTÉ a coûté 6 couches)
2. Grep qui APPELLE un writer avant de le patcher
3. Non-buildé = non-existant (tout fichier traverse une step build)
4. Pas de fallback de parsing silencieux — échec explicite
5. Avant nettoyage : git log --oneline -- <path> (cache GitHub trompeur)
6. Convention span_a : .apply → span_a[0] = func_id, parcours [1..]
7. Double dispatch (eval + parseSExpr), double cible (natif + wasm)
8. Suite complète après TOUT changement ; amend --force-with-lease
   vérifie le contenu stagé (format.zig a été absorbé par surprise)

## Commandes
zig build && zig-out/bin/heaven --run-test core/test_suite.hvn
zig build test --summary all
zig-out/bin/heaven repl   # port 0 ; HTTP = port+2919
