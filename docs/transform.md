SYSTÈME TRANSFORM - DOCUMENTATION
==================================

VUE D'ENSEMBLE
--------------
Le système transform vérifie l'égalité de deux expressions en appliquant 
des transformations basées sur les règles de la base de connaissances (KB).

SYNTAXE
-------
transform <expression1> = <expression2>

ARCHITECTURE
------------
Pipeline de transformation :
1. buildPlan : Détermine la stratégie selon le type de but
2. executeStep : Exécute chaque étape du plan
3. extractProof : Génère le certificat de preuve

Stratégies :
- Arithmétique : EGraph saturation → CAS normalize → Proof refl
- Ontologique : Ontology lookup → subsume → iso

Moteurs :
- EGraph : Saturation par equality saturation (natif uniquement)
- CAS : Normalisation par pattern matching
- Proof : Vérification réflexive structurelle

COMPORTEMENT PAR PLATEFORME
----------------------------
Natif :
- EGraph saturation activée
- Toutes les étapes exécutées

WASM :
- EGraph saturation désactivée (limitations plateforme)
- CAS normalize + Proof refl exécutés

EXEMPLES
--------
Déclarer une règle :
  theorem add_zero : a + 0 = a

Vérifier une égalité :
  transform x + 0 = x
  → Success: Refl, 3 steps

  transform x + 0 = y
  → Failure: StepFailed

CERTIFICATS
-----------
Chaque transformation réussie produit un certificat contenant :
- Le résultat (Refl, Sym, Trans, etc.)
- Le nombre d'étapes exécutées
- La trace des règles appliquées

LIMITATIONS
-----------
- L'induction automatique n'est pas encore implémentée
- L'EGraph a un budget de 1ms / 5 itérations max
- Le pattern matching ne supporte pas encore les variables liées

FICHIERS SOURCES
----------------
- src/core/transform.zig : Logique principale de transformation
- src/core/heaven_expr.zig : Dispatch de la commande transform
- src/inference/eqsat/egraph.zig : Implémentation EGraph
- src/core/pattern.zig : Pattern matching et substitution
