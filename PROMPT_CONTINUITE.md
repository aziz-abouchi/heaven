# Prompt de Continuité - Heaven

**Dernière mise à jour** : 2026-10-09

## Contexte
Heaven est un langage fonctionnel avec système de types avancé, implémenté en Zig.

## État Actuel (2026-10-09)

### ✅ Chantier D21 : Unification du Lowering (Tree-sitter → Expr.Store)
**Statut** : COMPLÉTÉ pour les primitives de base  
**Commit** : 440a002

**Fonctionnalités supportées** :
- ✅ identifier, int, binary, call, pattern, simple_expr, var_decl
- ✅ Tests x + 1 et let x = 1 in x validés

### 🚧 Prochaines étapes
1. **Étendre à lambda** : ajouter la gestion des nœuds lambda dans lowerExprToStore
2. **Migration Matrix/BobId** : déprécier progressivement les anciens chemins de parsing
3. **Tests d'intégration** : let x = 1 in x + 1, let f = fn x -> x * 2 in f(5)

## Commandes Utiles
zig build test              # Lancer tous les tests
zig build                   # Compiler le projet
git log --oneline -10       # Voir les derniers commits

## Architecture Clé
- **Pont** : src/syntax/lower.zig → lowerExprToStore(), lowerExprSource()
- **Store** : src/core/expr.zig → Store, bindSym(), bindSymWithBody()

## Notes Techniques
- **Quirk Tree-sitter** : 1 in peut être parsé comme app_expr → prendre le premier enfant nommé
- **Extraction val_id** : store.pool.items[bind_node.span_a.start]
