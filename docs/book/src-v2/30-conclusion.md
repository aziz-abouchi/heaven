# Chapitre 30 — Conclusion : un langage qui tend

> **Piège d'entrée.** Vous avez lu 28 chapitres, vous avez vu Heaven écrire des
> preuves, compiler du natif, parler HTTP, superviser des acteurs, exécuter du
> QTT. Vous pourriez croire que le langage est **fini**. Il ne l'est pas.
> Ce chapitre est une **carte de l'état réel** : ce qui tourne, ce qui est
> cible, et pourquoi le langage **tend** vers quelque chose de précis.

## 1. Où en est Heaven aujourd'hui (2026-11-05)

Heaven est un langage expérimental, **pas** un langage de production. Ce qui
suit n'est pas un jugement, c'est un constat.

### Ce qui tourne vraiment

| Couche | État | Test |
|---|---|---|
| Noyau (6 primitives, CIC) | ✅ stable | 168 tests `.hvn` |
| Types dépendants de surface | ✅ stable | `Vec n`, `head` |
| Preuves + tactiques | ✅ stable | `simplify`, `induction` |
| Compilation native (QBE) | ✅ stable | `fib(25)` en 1,15 ms |
| Compilation WASM | ⚠️ environnement | wasmtime casse sur Guix |
| CI (`.hvn` + Zig) | ✅ PROJET SAIN | `check_all.sh` |
| Acteurs (`handle_rec`) | ✅ stable | 5 msgs = 15 |
| `heaven check` syntax + arity | ✅ stable | CI-verrouillé |
| Curryfication | ✅ stable | 5/6 cas réels |

### Ce qui est partiel

| Couche | Limitation | Chapitre |
|---|---|---|
| QTT (multiplicités) | enforced (parse + erasure runtime) | ch. 29 |
| LSP / MCP | briques testées, **intégration manuelle** | ch. 26 |
| Selfhost | 15 + 96 l. de preuves de concept, **pas un compilateur** | ch. 27 |
| Curryfication | edge case `(((f a) b) c)` | ch. 18 |

### Ce qui est cible (non commencé)

| Cible | Effort | Chapitre |
|---|---|---|
| Selfhost complet (full-file) | ~2 sessions | ch. 27 |
| QTT érasure runtime | ~2 sessions | ch. 29 |
| QTT drop-reuse | ~3 sessions | ch. 29 |
| HoTT / Cubical | RFC à faire | ch. 41 (squelette) |
| Essaim / distribution | pas commencé | — |
| DB / LLM natif | pas commencé | — |

## 2. Pourquoi ces cibles ? (le fil rouge)

Heaven n'est pas un langage généraliste. Il a **trois ambitions** qui
déterminent ses cibles :

### Ambition 1 — La preuve est un citoyen de première classe

Ch. 8 (types), ch. 9 (typeclasses), ch. 41 (sémantique formelle). L'objectif :
écrire `theorem f : ...` et `prove f by simplify` **dans le même fichier** que
le code. Pas de Coq séparé, pas de Lean séparé. Un seul outil.

**Conséquence** : QTT est nécessaire (prouver sans coût runtime), HoTT est la
cible (prouver l'égalité), la sémantique formelle est la garantie (que `simplify`
fait ce qu'il dit).

### Ambition 2 — Le langage parle au monde

Ch. 19-24 (acteurs, OTP, MPST, HTTP, Hab). L'objectif : un langage fonctionnel
**utilisable** pour du Web, du réseau, des systèmes distribués. Pas un jouet
théorique.

**Conséquence** : LSP/MCP (ch. 26), stdlib réseau, acteurs préemptifs. Ce sont
des chantiers d'ingénierie, pas de théorie.

### Ambition 3 — Le langage s'écrit lui-même (un jour)

Ch. 26 (selfhost), ch. 28 (eval). L'objectif : que Heaven soit **auto-suffisant**
à terme. Pas urgent, mais structurant : chaque décision de design (6 primitives,
AST minimal, `handle_rec` one-shot) prépare ce jour.

**Conséquence** : les choix de conception sont **conservateurs** là où il faut
(minimalisme du noyau), **ambitieux** là où c'est possible (QTT, HoTT). Le
selfhost est la contrainte qui empêche le langage de dériver.

## 3. Où aller maintenant

Trois chemins, selon votre profil :

### Si vous êtes curieux (lecteur littéraire)

Vous avez fini le livre. **Utilisez Heaven** sur un petit projet : un serveur
HTTP statique (ch. 24), un composant Hab (ch. 25), un acteur supervisé
(ch. 19-20). Vous verrez ce qui marche et ce qui ne marche pas.

**Lisez** `docs/spec/_runtime_gaps.md` (940 l.) — c'est la carte honnête de
l'état du runtime. Plus utile que n'importe quel tutoriel.

### Si vous êtes développeur (contributeur potentiel)

**Choisissez un chantier** dans `PROMPT_CONTINUITE.md`. Les priorités actuelles :

1. **Selfhost complet** (~2 sessions) — débloquer full-file (bug `data_ctors`)
2. **QTT érasure + drop-reuse** (~5 sessions) — optimisation runtime
3. **Partie IV du livre** (`29-...`) — LSP/MCP, selfhost, QTT, HoTT

Chaque chantier a un diagnostic précis dans `_runtime_gaps.md`. Pas d'inconnu
majeur — juste du travail.

### Si vous êtes chercheur (théoricien)

**HoTT / Cubical** est le vrai sujet ouvert. `docs/book/src/41-semantique-formelle.md`
est un squelette (8 sections, `[À VÉRIFIER]`). La direction : HoTT pour
l'égalité, QTT pour la mémoire, CIC pour le noyau. C'est un projet de recherche,
pas d'ingénierie.

## 4. Capot : ce que le livre n'a pas montré

Ce livre est honnête, mais il ne peut pas tout couvrir. Ce qui manque :

- **La sémantique formelle complète** (ch. 41, squelette). Le CIC, HoTT, la
  normalisation forte : ce sont des sujets de recherche, pas des chapitres.
- **Les performances comparées** (ch. 12 pour bigint, ch. 30 pour QBE). Le
  langage est rapide, mais les benchmarks ne sont pas systématiques.
- **L'écosystème** : LSP, MCP, bibliothèques tierces. Voir `_cli.md` et le
  repo pour l'état réel.
- **Les pièges** : `G-pieges.md` (639 l.) est l'annexe indispensable. Lisez-la
  avant d'écrire du code de production.

**Rappel** : ce livre décrit Heaven **tel qu'il est testé**, pas tel qu'il est
rêvé. Les sections « cible » sont clairement marquées. Si vous lisez un chapitre
sans section « cible », c'est que le sujet est stable.

## Exercices

### Ex. 1 — Faire le tour du projet (guidé)

Clonez le repo, lancez `bash check_all.sh`. Combien de tests verts ? Combien
de WARN ? Lisez `PROMPT_CONTINUITE.md` (295 l.) — c'est l'état du projet en une
page.

**Question** : quel chantier vous intéresse le plus ? Pourquoi ?

### Ex. 2 — Écrire un petit programme (libre)

Choisissez un des chapitres récents (23 HTTP, 24 Hab, 19-20 acteurs) et
reproduisez l'exemple chez vous. Vous allez probablement heurter un mur.

**Question** : est-ce que ce mur est documenté dans `_runtime_gaps.md` ? Si oui,
vous avez lu la bonne doc. Si non, vous avez trouvé un nouveau bug — documentez-le.

### Ex. 3 — Lire un chapitre « cible » (libre)

Choisissez un chapitre qui a une section « cible » (17 curry, 26 selfhost,
28 QTT). Lisez le chapitre, puis lisez la section correspondante dans
`_runtime_gaps.md`.

**Question** : est-ce que le livre et la spec disent la même chose ? Si non,
laquelle est la plus honnête ?

---

## Au revoir

Vous avez lu 29 chapitres, environ 10 700 lignes. Vous savez maintenant :

- Heaven est un langage **expérimental** (pas de production).
- Le noyau est stable (6 primitives, CIC, preuves, compilation native).
- Les outils (LSP, MCP) sont en Heaven pur, testés par briques.
- Le selfhost est une **direction**, pas un acquis.
- La mémoire (QTT) est une **spécification**, pas un vérificateur.
- Les pièges sont documentés dans `G-pieges.md` — lisez-la.

Heaven n'est pas fini, et c'est le sujet du livre. Ce n'est pas un langage de
production, c'est un **laboratoire**. Chaque chapitre a montré quelque chose
qui marche, quelque chose qui est cible, et parfois quelque chose qui ne
marche pas encore.

**La vraie question** n'est pas « est-ce que Heaven est prêt ? », mais « est-ce
que Heaven **tend** vers quelque chose d'intéressant ? ». La réponse, après
29 chapitres, est oui : vers un langage où les preuves sont des citoyens de
première classe, où le runtime est prévisible, et où l'auto-hébergement est
possible.

Le reste, c'est du travail. Beaucoup de travail.

*— Fin du livre v2, 2026-11-05*
