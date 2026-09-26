# 📋 Prompt de continuité — Projet Heaven
# Session du 2026-09-25 — reprise post soundness-fix

## 🎯 Contexte
Heaven : langage expérimental en Zig (macOS ARM64, Zig 0.15.2).
Dépôt : https://github.com/aziz-abouchi/heaven
HEAD au moment de la rédaction : [le SHA de ton dernier commit]

## ✅ ÉTAT — 2026-09-25 (fin de session)

### La victoire de la session : SOUNDNESS RESTAURÉE
« theorem a = b » était PROUVÉ (système inconsistant). Six couches
traversées, commit d2849f7 + wip :
1-2. commutativité textuelle indexOfAny("+-*") → supprimée avec
     toute la voie textuelle de verifyBySimplify
3.   canonEqStr (stub false) — éliminé du diagnostic
4.   verifyByEval — gardé : expressions closes uniquement
5.   RACINE : auto-évaluation inconditionnelle des symboles non
     liés (engine_expr, return id, error.UnboundVariable COMMENTÉ)
     → restaurée. Exceptions : majuscules (constructeurs) +
     allowlist zero/succ/quote
6.   verifyBySimplify réécrit : pipeline Id pur (lowerRec →
     simplifyBasic → EGRAPH → simplifyBasic, itéré, catch) +
     comparaison STRUCTURELLE (structuralEql)

VALIDÉ : a=b, a-b=b-a, a/b=b/a, a+b=b+c → ✗ REFUSÉS
         x+0=x, add_zero, t_identity, t_dz5 (S-expr) → ✓ légitimes
         tests unitaires verts ; suite 75/77

### Tests
- Suite fonctionnelle : 75/77 (2 échecs documentés ci-dessous)
- Unitaires : verts au dernier run (summary all)
- Web : non revalidé cette session (à refaire après tout changement core)

### Architecture (état réel, unifiée cette session)
- src/kernel/ : UNIFIÉ (façade kernel.zig + peano.zig [moteur de
  prove, pool u32, iso-morphique avec Store] + CIC ast/typechecker/
  conversion/transform). strategy.zig SUPPRIMÉ (template fantôme).
- Pipeline compilation : UNIQUE (tree-sitter → syntax/ast → RFC-0001
  lowering → core/expr 6 primitives → backends MIR/C/WASM/JS/LaTeX).
  Prototypes non buildés supprimés (cli/, frontend/, opt/, pkg/ —
  guppy simulait, egraph parallèle faisait f x → x).
- compile <file.hvn> : consomme le pipeline canonique (l'ancien
  hardcodait add(10,32)).

## 🔴 LE POINT OUVERT UNIQUE : t_double_zero (le reprendre ICI)

t_dz7 : (x + 0) + 0 = x  →  ✗ (échec propre, pas un crash)
MAIS :
- t_dz5 : (+ (+ x 0) 0) = x (S-expr) → ✓  → pipeline OK
- t_identity : x + 0 = x (infix nu) → ✓      → nativeToSExpr OK
- REPL « simplify (x + 0) + 0 » → x           → chemin REPL OK

→ parseExpression (commands.zig:1192) route l'infix parenthésé vers
tree-sitter (trimmed[0]=='(' saute la branche native), qui produit
un arbre non-foldable.

### Étapes de reprise (dans l'ordre) :
1. Print temporaire dans verifyBySimplify : toString de thm.lhs/
   thm.rhs/lhs_rw/rhs_rw → voir l'arbre fautif
2. Fix : dans parseExpression, tenter nativeToSExpr sur l'infix
   parenthésé AVANT tree-sitter
3. Valider : t_dz7 ✓ + f1 ✗ (soundness tient) + suite 76/77
4. Commit : fix(theorem): parsing canonique de l'infix parenthésé

## 📋 File priorisée (après le point ouvert)

1. KERNEL-AUTHORITY — PRIORITÉ ABSOLUE. 9 writers de verified
   identifiés (8 dans proof_core + proofResult commands.zig:2077).
   Kernel.check unique sur Term = seule architecture où le bug
   soundness ne peut pas renaître. Pont exprToTerm trivial côté
   peano (pools iso-morphiques).
2. conversion.zig — +617 lignes NON AUDITÉES. Diff isolé :
   ~/Desktop/Dev/heaven-conversion-audit.diff (à vérifier qu'il
   existe). ORIGINE INCONNUE (à déterminer — toi ou autre session
   IA ?). C'est du code kernel non revu : audit obligatoire avant
   toute adoption.
3. t_distrib : règle de factorisation manquante en saturation
   egraph (150ms, verdict propre — vrai théorème en attente).
4. Revalidation web (bash build.sh + page /test) après les
   changements core de la session.
5. type λ natif : _t0 -> _t0 apparu (inference en cours), à finir.

## 📌 Conventions & règles (dont celles gravées cette session)

- span_a d'un .apply : [func_id, arg1, ...] — parcours en [1..]
- Double dispatch : eval() + parseSExpr()
- Double cible : src/platform/ → zig build + wasm + copie
- ArrayListUnmanaged{}, tout vendored
- RÈGLES NOUVELLES (session soundness) :
  1. La soundness ne se désactive pas pour faire passer des tests
     (le return error.UnboundVariable COMMENTÉ a coûté 6 couches)
  2. Grep qui APPELLE un writer avant de le patcher (on a patché
     verifyByEval alors que "by simplify" appelle verifyBySimplify)
  3. Non-buildé = non-existant (strategy.zig, cli/, guppy...)
  4. Avant nettoyage : git log --oneline -- <path> (le GitHub
     affiché peut être un cache périmé)
  5. Pas de fallback de parsing silencieux (importExpr) — un
     statement imparsable est REFUSÉ
  6. Un code généré non instancié n'est pas un design, c'est une dette

## Ports & commandes
- zig-out/bin/heaven <port> : P2P sur <port>, HTTP sur <port>+2919
- zig-out/bin/heaven repl
- zig-out/bin/heaven --run-test core/test_suite.hvn
- zig build test --summary all
