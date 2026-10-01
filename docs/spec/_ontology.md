# Ontologie Heaven — périmètre et frontière

> Statut : **à décider**. Ce document ne code rien, il pose cinq
> questions. Tant qu'elles ne sont pas tranchées, `src/core/ontology.zig`
> reste **gelé en l'état** (bugs corrigés, tests ajoutés, aucune
> extension).

## Contexte

`src/core/ontology.zig` existe (~330 lignes). Importé par `main.zig`
via le module `ontology`. Dépendance déclarée : `expr` (retirée au
dernier nettoyage, car non utilisée).

Ce que le fichier **est** aujourd'hui : un catalogue d'algorithmes
avec métadonnées de complexité (temps, espace, parallélisme,
tail-recursion, contrainte de domaine), une relation de subsomption
is-a, des classes d'équivalence textuelles, et un scoring qui choisit
un algorithme selon un contexte (`expected_n`, `has_gpu`, etc.).

Ce que le fichier **n'est pas** :

- pas une ontologie OWL/DL (pas de propriétés peuplées, pas de
  description logic, pas de raisonneur)
- pas connecté au Core IR (la dépendance `expr` était déclarée mais
  morte ; le fichier travaille sur des strings)
- pas une source de vérité (pas de trust level, pas de provenance)
- pas une interface avec des sources externes (aucun import OWL,
  SMT-LIB, DBpedia, Lean, MLCPD)

## Les cinq questions

### 1. Nom et périmètre

Le fichier s'appelle `ontology` mais fait un **catalogue d'algorithmes**.

Option A : garder le nom. Le fichier est l'ontologie au sens large
(connaissance structurée sur les concepts computationnels), et son
périmètre s'étendra plus tard.

Option B : renommer (`algo_catalog.zig` ou `complexity.zig`) et
réserver le nom `ontology` à un futur niveau sémantique plus large,
au-dessus du Core.

**À décider.** Si B, le renommage est trivial mais ouvre la question
de ce qu'est le futur `ontology.zig` — qui n'a pas encore de spec.

### 2. Frontière avec le Core

Actuellement : strings. `declareEquivalent`, `defineConcept`,
`registerAlgo` prennent des `[]const u8`. La dépendance `expr` était
déclarée et jamais utilisée.

Option A : l'ontologie reste **à côté** du Core. Elle manipule des
noms, sert d'aide à la décision (choix d'algo, description), sans
toucher au noyau. Aucune dépendance `expr` nécessaire.

Option B : l'ontologie vit **au-dessus** du Core. Elle manipule des
`Id`, s'insère dans le niveau `High-Level Semantic IR` de
`docs/core/core-ir.md` (§18), et devient le pivot entre syntaxes de
surface et Core. C'est un chantier de plusieurs sessions.

**À décider.** Si B, `ontology.zig` devra être réécrit, pas étendu.

### 3. Sources externes

Aujourd'hui : aucune. `declareEquivalent` prend des strings libres,
sans provenance ni format d'échange.

Sources envisagées, par difficulté croissante :

| Source | Nature | Complexité d'intégration |
|---|---|---|
| SMT-LIB | format standard + oracle | faible |
| OWL / RDF / SPARQL | graphe + raisonneur | moyenne |
| Lean / Rocq | oracles (LSP) | élevée (pas d'import sémantique) |
| MLCPD | dataset (tooling) | faible mais hors runtime |

**À décider.** Introduit-on une source externe maintenant (et
laquelle), ou reste-t-on sur du local tant qu'aucun cas d'usage
concret ne l'exige ?

Note : `docs/DECISIONS.md` dit explicitement que les rapports LLM
sur les ontologies « doivent être vérifiés ligne par ligne avant
d'être planifiés ». Ne pas construire de pont externe sans cas
d'usage.

### 4. Trust et provenance

Aujourd'hui : absents.

Trois niveaux proposés (alignés sur la discussion architecturale) :

- **Certified** : prouvé par `proof_core.zig`
- **Derived** : dérivation interne valide
- **Asserted** : vient d'une source externe non vérifiée

Ajouter ces niveaux maintenant serait spéculatif : aucune source
externe n'existe, aucune preuve n'est attachée aux algos enregistrés.
La doctrine du repo (pas de feature sans cas d'usage) suggère
d'attendre.

**À décider.** Ajouter `trust_level` + `provenance` maintenant, ou
quand la première source externe arrive ?

### 5. Relation avec MPST

`src/core/mpst.zig` existe, importé par `elab`. `docs/capabilities.md`
mentionne : « les caps sont des labels de session ». Si l'ontologie
alimente les labels MPST (concepts → rôles), elle doit s'intégrer à
`elab`. Si elle reste orthogonale, elle n'a rien à voir avec MPST.

**À décider.** L'ontologie alimente-t-elle les labels MPST ? Ou
reste-t-elle séparée ?

## Décision à prendre

Cinq questions. Deux façons de les traiter :

- **Maintenant** : une session de 30 minutes, on tranche chaque point
  par oui/non, et on écrit la réponse ici.
- **Plus tard** : on attend qu'un cas d'usage concret les pose, on
  ne spécule pas.

Tant qu'aucune réponse n'est donnée, `ontology.zig` reste **gelé en
l'état corrigé** : bugs fixés, tests ajoutés, aucune extension. Le
fichier ne prétend pas être ce qu'il n'est pas, et il ne bloque rien.

## Ce que ce document n'est pas

Ce n'est pas une spec d'ontologie formelle. Ce n'est pas un plan
d'intégration de sources externes. Ce n'est pas une réponse aux
questions — c'est la liste des questions auxquelles il faudra
répondre *avant* d'écrire la moindre ligne de code supplémentaire.
