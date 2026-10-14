# HoTT, HITs, Univalence — conception

**Date** : 2026-10-14
**Statut** : analyse + décision. Aucune implémentation.
**But** : documenter honnêtement l'écart entre le noyau CIC de
Heaven V0 et la théorie des types homotopique (HoTT), tracer les
deux voies d'évolution possibles, et ce qu'on peut faire sans
refonte du noyau.

## 1. Ce que Heaven V0 a réellement

Le noyau de preuve de Heaven est un **CIC minimaliste** dans
`kernel/peano.zig` (853 lignes). Ses caractéristiques :

| Élément | État V0 |
|---|---|
| Termes | `TermPool` + indices `u32` |
| Types de base | `Nat`, `Eq` (égalité propositionnelle) |
| Règles | `eval`, `infer`, `check`, `verify`, `convertible` |
| Axiomes | `initNatAxioms` (Peano) |
| UIP (unicité des preuves d'égalité) | **vrai** (CIC standard) |
| Quotients | **absent** |
| Univalence | **absent** |
| Higher Inductive Types | **absent** |
| Cubical / chemins | **absent** |

Le pont `kernel_bridge.zig` (143 lignes) ne traduit que `lit(int)`,
`sym` et `apply` binop arithmétique. `bind`, `lambda` et `relation`
lèvent une erreur explicite. Conséquence : les théorèmes contenant
des lambdas ou des relations ne sont **pas vérifiés** par le kernel
CIC — ils passent par `verifyBySimplify` au niveau du Store.

## 2. Ce que HoTT demande

La théorie des types homotopique (HoTT) est un paradigme où les
**preuves d'égalité sont des chemins**, et où deux types équivalents
sont identifiables. Elle exige :

| Composant | Rôle | Coût |
|---|---|---|
| **Égalité = chemin** | `a = b` est un *type* (type des chemins) | 🔴 refonte sémantique |
| **UIP désactivé** | Deux preuves de `a = b` peuvent différer | 🔴 casse les tactiques actuelles |
| **Réflexivité = chemin constant** | `refl : a = a` | 🟢 compatible |
| **Transport** | Chemin `p : a = b` convertit `P a` en `P b` | 🔴 absent |
| **Univalence** | `A ≃ B` implique `A = B` | 🔴 axiome ou théorie |
| **HITs** | Inductifs avec constructeurs de *chemin* | 🔴 absents |
| **Réduction calculatoire de l'univalence** | `transport (ua e) x` se réduit | 🔴 requiert CCHM cubical |

## 3. Pourquoi Heaven V0 n'est PAS HoTT

Il faut être clair : **Heaven V0 n'est pas un système HoTT**. C'est
un **CIC standard** (comme Coq, sans les extensions). Trois raisons
principales :

1. **UIP est vrai par défaut** : dans CIC, deux preuves du même
   `a = b` sont identifiables. En HoTT, ce serait faux — et c'est
   exactement ce qui permet aux chemins non triviaux d'exister.

2. **Pas de types de chemins** : `relation` (la primitive 6) produit
   un booléen `Eq(a,b)`, pas un type de chemins. Pour HoTT, il
   faudrait que `a = b` soit un **type**, et que `refl` soit un
   **terme** de ce type.

3. **Pas de HITs** : un `data` en V0 produit un inductif simple.
   Les HITs demandent des constructeurs de **chemin** en plus des
   constructeurs de point — par exemple :

       data S¹ where
         base : S¹
         loop : base = base

   Sans HoTT, `loop` n'a pas de sens.

## 4. Deux voies pour aller vers HoTT

Si Heaven voulait un jour supporter HoTT, deux voies existent.

### Voie A — HoTT axiomatique

**Principe** : ajouter des **axiomes** au CIC standard.

    postulate univalence : (A ≃ B) → (A = B)
    postulate funext : (∀ x, f x = g x) → f = g
    postulate quotients : A / R   -- avec règles de calcul

**Avantages** :
- Changement minimal dans le noyau (axiomes, pas sémantique)
- Compatible avec les tactiques existantes
- On peut commencer par un seul axiome (funext, le plus simple)

**Inconvénients** :
- **Non computationnel** : `transport (ua e) x` ne se réduit pas.
  Résultat : les preuves ne calculent pas toujours.
- **Casse la normalisation forte** du CIC (par l'axiome d'univalence).
- **Cohérence** : HoTT axiomatique est consistant, mais uniquement
  avec des précautions (hiérarchie de univers).

### Voie B — Cubical Type Theory (CCHM/Cartesian)

**Principe** : **refonte complète** du noyau avec une sémantique
cubique. Les types sont des **fibrations**, les égalités des
**chemins**, et l'univalence est **prouvée** (pas axiomatisée).

**Avantages** :
- **Computationnel** : `transport (ua e) x` se réduit.
- Cohérence prouvée (Cohen-Coquand-Huber-Mörtberg 2015).
- Utilisé par Cubical Agda — référence moderne.

**Inconvénients** :
- **Chantier de plusieurs années** : il faut refondre `kernel/`,
  `elab.zig`, `proof_core.zig`, et probablement les tactiques.
- Nécessite une implémentation d'un **système de cubes**
  (dimensions, face lattice, systèmes de composition).
- Expertise rare : peu de personnes ont implémenté CCHM en dehors
  des équipes de recherche (Cubical Agda, cooltt).

## 5. Ce qu'on peut faire en V0.x sans refonte

Même sans HoTT, on peut préparer le terrain :

- **`Path A x y`** comme **notation** pour `x = y`. Pas de
  sémantique cubique, mais le nom apparaît dans le lexique.
- **`Equiv A B`** et **`Iso A B`** comme **prédicats** sur les types
  (`sig Equiv : (A : Type) -> (B : Type) -> Type`). Utiles en
  eux-mêmes (théorie des catégories, Ch17).
- **`transport`** comme primitive prenant `p : x = y` et une famille
  `P : A -> Type` — mais sans la sémantique de chemins, on se
  limiterait à `refl`.
- Documenter HoTT dans un chapitre book (décision séparée).

## 6. Quotients — cas à part

Les **quotients** sont un sujet CIC, **indépendant de HoTT**. En
CIC standard, deux approches :

- **Quotients par setoïdes** : `Setoid A` = `(A, R)` avec `R`
  relation d'équivalence explicite. Voie de Coq (bibliothèque
  `Setoid`). **Fonctionne en V0 aujourd'hui** (rien à ajouter au
  kernel — c'est de l'encodage dans la théorie existante).
- **Quotients par HITs** : `A / R` est un HIT avec constructeur de
  chemin pour chaque paire dans `R`. Nécessite HoTT (voie 4).

**Recommandation** : commencer par les **setoïdes** (V0.x, peut se
faire sans toucher au kernel). Envisager les **HITs quotients**
seulement si HoTT est adopté plus tard.

## 7. Décision

**Aucune implémentation HoTT en V0.**
**Recommandation** : rester en CIC standard. Documenter
l'incompatibilité honnêtement dans le book (Ch08, Ch17, Ch18).

Si HoTT devient un objectif (post-V1), privilégier la **voie B
cubical** — non pour des raisons pratiques (elle est bien plus
coûteuse), mais parce que la voie A (axiomatique) rend le langage
moins computationnel, ce qui est incompatible avec la vision
Heaven de "prouver ET exécuter".

**Première étape possible** (V0.x, si priorité) :
- Ajouter un chapitre book sur HoTT (conceptuel, pédagogique).
- Ajouter `Equiv` / `Iso` comme prédicats sur les types (utile
  indépendamment de HoTT).
- Encoder les quotients via **setoïdes** au niveau tactique.

**Décision reportée** : V1+ minimum. Ne pas mettre HoTT dans le
scope V0.

## 8. Impact sur le book

- **Ch08 (Preuves)** : mentionner l'UIP et son absence de
  différenciation avec HoTT.
- **Ch17 (Catégories)** : section sur les quotients (setoïdes vs
  HITs).
- **Ch18 (Under the Hood)** : préciser les limites du kernel
  actuel (Peano + Eq propositionnelle), et ce qui manque pour
  être "CIC complet".
- **Chapitre HoTT** (éventuel) : conceptuel, sans code.
