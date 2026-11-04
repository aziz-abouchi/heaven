# Learn You Some Heaven — OUTLINE v2

> **Statut** : plan de refonte (2026-11-04). Version 1 publiée reste
> sur `aziz-abouchi.github.io/heaven` (`docs/book/src/`). Version 2
> en préparation (`docs/book/src-v2/`), publication à la fin.
>
> **Style** : conversationnel (LYAH/LYSE), exemples progressifs,
> anecdotes, exercices, figures.
>
> **Sources** :
> - LYAH : https://learnyouahaskell.github.io/chapters.html
> - LYSE : https://learnyousomeerlang.com/content
> - PLFA : https://plfa.github.io
> - Idris2 : https://idris2.readthedocs.io/en/latest/tutorial
>
> **Public** : littéraires, philosophes, mathématiciens, curieux.
> Pas un manuel de référence — un voyage.

## Structure cible : 6 parties, ~52 chapitres

### Partie I — Premier contact (LYAH ch.1-4)

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 1 | Pourquoi Heaven | LYAH 1 | 00-pourquoi-heaven | refonte légère |
| 2 | Démarrer — REPL et première fonction | LYAH 2, LYSE 1 | 00b-repl (stub, à réécrire) | **from scratch** (45-60 min, pas de copie possible) |
| 3 | Types et signatures | LYAH 2-3 | 02-believe-the-type | refonte LYAH |
| 4 | Syntaxe en fonctions | LYAH 4 | 03-syntax-in-functions | refonte LYAH |
| 5 | Récursion | LYAH 5 | 04-recursion | refonte LYAH strict |
| 6 | Ordre supérieur | LYAH 6 | 05-higher-order | refonte LYAH |
| 7 | Modules | LYAH 7 | 10-modules | refonte LYAH |

### Partie II — Types et structures (LYAH 7-9, PLFA 1-3)

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 8 | Définir ses types | LYAH 8 | (partiel dans 19) | **from scratch** (data, constructeurs, pattern matching sur constructeurs) |
| 9 | Typeclasses | LYAH 9 | 19-algebres | refonte (mapping corrigé 2026-11-04) |
| 10 | Structures récursives | LYAH 8, PLFA 3 | (partiel dans 14) | **from scratch** (List/Tree/Stream + fold simple) — mapping corrigé 2026-11-04 |
| 11 | Streams et paresse | LYAH 7, LYSE | 07-streams | garder |
| 12 | BigInt — un type de bout en bout | — | 12-bigint | garder |
| 13 | Free monads | — | 16-free-monads | garder |
| 14 | Schémas de récursion (cata/ana/hylo) | — | 14-recursion-schemes | refonte |
| 15 | Catégories et naturalité | — | 17-categories | garder |
| 16 | Optiques | — | 15-optiques | garder |

### Partie III — Effets, concurrence, OTP (LYSE 4-10)

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 16 | Effets — le modèle pur | LYSE 2, LYAH 13 | 06-effects | refonte |
| 17 | Handlers et composition | LYSE 3 | 06b-effects-network | refonte |
| 18 | Erreurs et validation | LYSE 3 | 23-validation, B-erreurs | fusion + refonte |
| 19 | Acteurs (actor model) | LYSE 6-7 | 09-real-world | refonte |
| 20 | OTP — supervisors | LYSE 8-9 | 28-otp | refonte LYSE |
| 21 | Preemption et fair scheduling | LYSE 10, BEAM | 13-concurrency | refonte |
| 22 | MPST — session types | (Heaven) | 29-mpst | garder + V2a |
| 23 | Réseau — TCP/HTTP | LYSE 10 | 24-reseau, 25-stdlib-net-http | fusion |
| 24 | Hab — UI réactive | (Heaven) | 27-hab + 31/32/36/37 | fusion |

### Partie IV — Preuves et logique (PLFA 1-12, Idris2)

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 25 | Curry-Howard — types = preuves | PLFA 11 | 08-proofs | refonte PLFA |
| 26 | Égalité et réécriture | PLFA 2, 5 | (absent) | **nouveau** |
| 27 | Inductifs et induction | PLFA 3-4 | (absent) | **nouveau** |
| 28 | Logique propositionnelle | PLFA 4-5 | (absent) | **nouveau** |
| 29 | Quantificateurs | PLFA 6, 10 | (absent) | **nouveau** |
| 30 | Décidabilité | PLFA 7 | (absent) | **nouveau** |
| 31 | Preuves en Heaven — tactics | PLFA 11, Idris2 10 | (absent) | **nouveau** |
| 32 | Knowledge et TripleStore | (Heaven) | 11-knowledge | garder |

### Partie V — Dépendance et HoTT (PLFA 13-20, Idris2)

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 33 | Types dépendants — intro | PLFA 13, Idris2 4 | (absent) | **nouveau** |
| 34 | Vec, Fin — taille indexée | PLFA 14, Idris2 5 | (absent) | **nouveau** |
| 35 | Lambda-calcul typé | PLFA 10-12 | (absent) | **nouveau** |
| 36 | HKT — types d'ordre supérieur | LYAH 8, PLFA | 20-hkt | refonte |
| 37 | HoTT — chemins et univalence | HoTT Book, PLFA | 22-hott | refonte |
| 38 | QTT — linéarité et multiplicités | Idris2, QTT papers | 26-qtt | refonte + vrai QTT |
| 39 | Sémantique formelle de Heaven | Pony, CompCert | 41-semantique-formelle | **promu** |

### Partie VI — Heaven spécifique et outils

| # | Titre v2 | Source | Chapitre v1 | Statut |
|---|---|---|---|---|
| 40 | CAS et raisonnement symbolique | (Heaven) | 21-cas | garder |
| 41 | Under the hood — le Core | (Heaven) | 18-under-the-hood | garder |
| 42 | Selfhosting — Heaven écrit en Heaven | (Heaven) | 39-selfhosting | garder |
| 43 | heaven eval — méta-circulaire | (Heaven) | 40-heaven-eval | garder |
| 44 | Build et backends (QBE, WASM) | (Heaven) | 33-heaven-build, 34-backend-qbe, 35-backend-wasm | fusion |
| 45 | Tooling — LSP, REPL, tests | (Heaven) | 38-tooling | garder |
| 46 | TDD en Heaven | (Heaven) | 30-tdd | refonte |
| 47 | Contribuer | (Heaven) | D-contribuer | garder |

### Annexes

| # | Titre | Chapitre v1 |
|---|---|---|
| A | Syntaxe complète | A-syntaxe |
| B | Erreurs courantes | B-erreurs |
| C | Glossaire | C-glossaire |
| D | Pièges (G.1-G.43+) | G-pieges |
| E | Références | F-references |
| F | Applications en ligne (showcase + iframe REPL) | 00c-apps |

## Bilan par source

| Source | Chapitres mappés | Nouveaux v2 |
|---|---|---|
| LYAH | 7 refonte + 1 nouveau | 1 |
| LYSE | 6 refonte + 2 fusion | 2 |
| PLFA | 2 refonte + **8 nouveaux** | 8 |
| Idris2 | 1 refonte + 2 nouveaux | 2 |
| Heaven | 11 garder + 4 fusion | 0 |

## Travail à faire

| Phase | Effort | Livrable |
|---|---|---|
| **Phase 1** (2-3 sessions) | Pilote + vérif OUTLINE | ch. 05-recursion réécrit en style LYAH strict |
| **Phase 2** (sessions suivantes) | Parties I-II (15 ch.) | 1 chapitre / session |
| **Phase 3** | Parties III-VI (31 ch.) | 1 chapitre / session |
| **Phase 4** | Nouveaux ch. PLFA/Idris2 (10 ch.) | 2 sessions / ch. (recherche) |
| **Total** | **~6-9 mois** | 52 chapitres + annexes |

## Priorité absolue

**Chapitre pilote = `05-recursion`** (ancien `04-recursion`). C'est le premier chapitre où Heaven diverge vraiment de LYAH (Heaven n'a pas `map`, `filter` builtin — il faut les définir). Bon test de style.

Une fois le pilote validé, il devient le **référentiel** pour les 51 autres.

## Décisions 2026-11-04 (soir)

- **`00c-apps` = annexe F**, pas chapitre 2. Contenu (tableau d'apps + iframe REPL) = showcase, pas pédagogie. Le chapitre 2 sera narratif pur (from scratch).
- **`00b-repl` (stub 24 l.)** absorbé dans le ch2 from-scratch. Pas de chapitre 0b séparé.

## Décisions 2026-11-04 (soir)

- **Concurrence scindée** : `13-concurrency.md` (v1) est mal titré « coopérative » mais contient déjà la préemption. v2 = 3 chapitres (`21a` coop, `21b` préemptif, `21c` parallélisme roadmap).
- **`00c-apps` = annexe F**, pas chapitre 2 (showcase, pas pédagogie).
- **`00b-repl`** (stub 24 l.) absorbé dans ch2 from-scratch.
- **`19-algebres` → ch9 typeclasses** (pas ch8). Ch8 `definir-types` from scratch.

## Décisions 2026-11-04 (soir, suite)

- **`14-recursion-schemes` = ch14** (pas ch10). Cata/ana/hylo/para = avancé, pas LYAH ch.8. Ch10 `10-structures-recursives` sera from-scratch (List/Tree/Stream + fold simple).
- **Concurrence scindée** (21a/21b/21c).

## Décisions ouvertes

- **v2 publiée sous `/v2/`** ou domaine séparé ? (recommandation : `/v2/`, avec bandeau "bêta")
- **Traduction anglaise** ? (le livre v1 est bilingue partiel — décision à prendre)
- **Exercices** : réponses en annexe, ou pas de réponses (style LYAH) ?
- **Compagnon code** : un repo `heaven-book/` séparé avec tous les exemples exécutables ?

