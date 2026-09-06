# 🎯 Heaven-Core : Stratégie de Pilotage PM

## 🚀 Vision Technique
Heaven-Core est un langage système fonctionnel. 
- **Gestion Mémoire :** Zéro-GC. Utilisation de la QTT (linéarité/unicité) et des Capabilities.
- **Runtime :** Écrit en Zig (0.15.2), conçu pour la distribution massive (modèle d'acteurs).
- **Bootstrap :** Stratégie de développement en miroir Zig -> Heaven.

## 🏗️ État d'avancement (Trackers)
| Composant | État | Focus Actuel |
| :--- | :--- | :--- |
| **Parser** | 🏗️ Dev (Zig) | Gestion des expressions complexes & AST |
| **Typechecker** | 🧠 Concept/Dev | Implémentation des règles QTT & Unification |
| **Runtime** | ⚙️ Dev (Zig) | Scheduler d'acteurs & Message passing |
| **Heaven-in-Heaven**| ⏳ Initialisation | Réécriture des modules de base en Heaven |

## 🛠️ User Stories - Sprint "Foundation & Logic"

### 1. [Parser] Support des expressions QTT
**En tant que** développeur Heaven, 
**Je veux** que le parser reconnaisse les annotations de multiplicité (0, 1, many) sur les types,
**Afin que** le typechecker puisse analyser la linéarité des ressources.

### 2. [Typechecker] Vérification de l'usage unique
**En tant que** moteur de sécurité,
**Je veux** lever une erreur si une variable marquée comme 'unique' est utilisée deux fois,
**Afin de** garantir l'absence de fuites sans GC.

### 3. [Bootstrap] Module System minimal en Heaven
**En tant qu'** architecte,
**Je veux** écrire la logique de gestion des imports directement en Heaven,
**Afin de** tester le compilateur sur sa propre logique.

## ⚠️ Contraintes PM (Dogmes)
1. **Interdiction du GC :** Toute proposition de gestion mémoire automatique par scan est rejetée.
2. **Zig 0.15.2 :** Aucune dépendance ne doit casser la compatibilité avec cette version.
3. **Parallélisme :** Chaque feature doit être pensée pour être "Thread-safe" via les capabilities.
