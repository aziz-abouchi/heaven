# Vision stratégique (2026-10-26)

Ce document grave les orientations stratégiques discutées pendant
la session de conception. Il ne décrit pas des chantiers ouverts
(voir `_decisions.md`), il décrit **ce que Heaven cherche à être**
et **ce qu'il ne cherche pas à être**.

## Positionnement

**Créneau étroit et défendable** :

> Le seul langage où un protocole distribué peut être **prouvé**,
> **compilé** et **déployé** comme un seul objet.

**Ce que Heaven ne vise pas** :
- Reconstruire le calcul symbolique de Mathematica (utiliser SymPy,
  Sage, Lean via FFI)
- Reconstruire la base de connaissances de Wolfram (utiliser
  Wikidata, DBpedia)
- Reconstruire les notebooks et visualisations (utiliser Jupyter,
  Observable)
- Battre Zig sur les boucles numériques (LLVM reste la référence)

**Comparaison** :
- Wolfram : calcule, ne prouve pas (heuristiques)
- Lean/Coq : prouvent, ne compilent pas distribué
- TLA+/Alloy : prouvent des modèles, pas des programmes exécutables
- Rust : compile + distribue, ne prouve pas (kani/creusot limités)
- Heaven : vise les quatre (cible, pas état actuel)

## Premier utilisateur

**Question ouverte** : quel est le premier utilisateur de Heaven
qui n'est pas le mainteneur ?

Trois réponses possibles, très différentes :
- **Niche** : théoriciens des types distribués (~10 000 personnes
  dans le monde). Livre devient "pour spécialistes".
- **Large** : besoin concret grand public (smart contracts
  vérifiables ? protocoles blockchain ? systèmes embarqués
  critiques ?).
- **Interne** : Heaven pour Heaven (auto-hébergement, LLM-verify).
  Pas d'utilisateur externe avant 2028.

**Décision reportée**. À trancher avant d'ouvrir les chantiers
DB/LLM/P2P.

## Premier vertical slice

**Réaliste** (pas HoTT) : un protocole MPST client/serveur.
- Écrit avec `lib/os/ipc.hvn` (existe, 9/9 tests)
- Exécuté localement via `KernelQ` (existe, 6/6 tests)
- Vérifié par MPST trace (`stdlib/mpst.hvn` existe)
- Distribué via fork+execve (partiel : `wait4` cassé)

Ce slice prouve une **conformité de protocole réelle**, exécute
en local, pointe vers la distribution. Ce n'est pas HoTT. C'est
la première marche.

## Heaven DB (vision 2026-2028)

**Option A (actée D9)** : composant interne. 4 couches
(Store / DB / Knowledge / LLM-storage). 1 modèle logique,
N représentations physiques. Expr IR = représentation commune,
pas IR unique de stockage.

**Ce qu'on ne fait pas** : produit externe avec utilisateurs
avant 2028. Transactions ACID complètes, récupération après
crash, benchmarks vs SQLite ne sont pas prioritaires.

## LLM interne (vision 2026-2030)

**Orchestration en Heaven, inférence FFI** (acté D10).
- Prompts, tool-call, vérification, provenance → Heaven
- Inférence → llama.cpp / candle (FFI C)
- "LLM écrit en Heaven" = 10 ans (SIMD, GPU, bande passante)

**Le vrai joyau** : boucle "LLM propose, outils vérifient".
Faisable **maintenant** avec LLM externe + CLI Heaven existant.
1 session après P5. C'est la contribution différenciante.

## HoTT (acté D0)

**Cubical HoTT** (CCHM 2018), pas HOTT (Altenkirch-Kaposi-
Shulman). Refonte complète du noyau (~12+ mois). Tension
QTT/Cubical = problème de recherche ouvert.

**Décision reportée** : Cubical vs OTT vs CIC+facade après P5.
Pas avant (pas de noyau à remplacer aujourd'hui :
`DependentChecker` stub).

## Performance (acté D12)

**Promesse défendable** :
> Comparable à Zig sur les charges non-numériques. Plus rapide
> sur les charges allocation-heavy (QTT enforced). Plus lent sur
> les boucles numériques (LLVM reste). Sur les protocoles
> vérifiés, Zig n'offre pas la comparaison.

**Sans benchmarks publiés, pas de claim "plus rapide que Zig".**

## Sécurité (voir `_security_methodology.md`)

**Réponse structurelle** : capabilities (niveau 0) + mémoire
(niveau 1.5). Pas de "détection" de code malveillant — on
contrôle ce que le code **peut faire**, pas ce qu'il **fait**.

## Ce qu'on ne promet pas dans le livre

- LLM en Heaven natif (10 ans)
- Base de données avec utilisateurs externes (pas avant 2028)
- Kernel de preuves fonctionnel (stub aujourd'hui)
- QTT enforced (façade)
- Distribution P2P (pas d'implémentation)
- Cubical HoTT opérationnel (12+ mois)
- "Plus rapide que Zig" sans mesure

## Voir aussi

- `_decisions.md` : D0 (Cubical), D9 (DB), D10 (LLM), D12 (perf),
  D15-D18 (backends)
- `_security_methodology.md` : 6 niveaux
- `_backend_strategy.md` : QBE/Cranelift/LLVM/BEAM/JVM
- `_emancipation_roadmap.md` : E1-E10
- `_claims_vs_reality.md` : 14 entrées vérifiées
