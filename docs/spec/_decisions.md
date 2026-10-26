# Décisions architecturales actées (2026-10-20 → 2026-10-26)

Ce document grave les décisions prises pendant les sessions de
conception. Chaque décision a un identifiant, un statut, un
déclencheur, et un lien vers la doc détaillée.

Règle : une décision actée ne se rediscute pas sans raison nouvelle.
Une décision reportée a un déclencheur explicite.

## Décisions actées

### D0 — Cubical HoTT comme fondation (CCHM 2018)

**Décision** : Heaven vise Cubical HoTT (style Cubical Agda), pas
HOTT (Altenkirch-Kaposi-Shulman). Référence : Cohen-Coquand-Huber-
Mörtberg, "Cubical Type Theory: a constructive interpretation of
the univalence axiom" (2018).

**Conséquence** : refonte complète du noyau (~12+ mois). Intervalle
I, hcomp, transp, Glue types. Tension QTT/Cubical = problème de
recherche ouvert, traité comme axe séparé.

**Correction livre** : ch22 remplace "HOTT" par "Cubical HoTT
(CCHM 2018)".

**Statut** : actée. Chantier après P5.

### D1 — Noyau cubical : Zig d'abord, Heaven ensuite

**Décision** : le noyau cubical est prototypé en Zig, porté en
Heaven après E1-E3 + bootstrap.

**Raison** : cercle vicieux sinon (noyau cubical en Heaven
impossible avant que le noyau existe).

**Statut** : actée. Chantier après P5.

### D2 — Concurrence : isolation totale V1

**Décision** : acteurs mémoire séparée (Erlang-like). Messages
copiés. Pas de partage implicite. Partage explicite via
Cap<Shared> après V1.

**Raison** : cohérent avec Cubical, QTT, sécurité niveau 0.

**Statut** : actée. Avant P5.

### D3 — QTT : façade jusqu'au noyau cubical

**Décision** : LinearChecker existe (types.zig:145) mais n'est
pas enforced. Façade lib/qtt/linear.hvn. Le livre dit "cible,
pas garantie". Décision enforced/différé APRÈS le noyau cubical.

**Statut** : actée. Voir D12-bis pour l'enforcement.

### D4 — Backend C après P5, avant Cubical

**Décision** : build.zig utilise TCC (FFI). Pas de backend C pour
compiler Heaven → C natif. Nécessaire pour FFI (llama.cpp,
OpenSSL) et bootstrap. Après P5, avant le noyau cubical.

**Statut** : actée. Après P5.

### D5 — Parseurs : fusionner dans NativeParser

**Décision** : NativeParser devient la seule source de vérité pour
les expressions. elab.zig devient adaptateur tree-sitter qui
produit du NativeParser (pour data, class, instance, theorem).
Un seul AST de référence.

**Statut** : actée. Migration en P4.

### D6 — Système de modules : minimal

**Décision** : tout public. Pas de cycles. Ordre topologique
(dépendances avant module). Imports cycliques → erreur explicite.
Visibilités sélectives viendront après V1.

**Statut** : actée. Avant P3.

### D7 — Mode erreurs : Result explicite

**Décision** : APIs publiques retournent Result/Option. @panic
interdit hors bugs internes (asserts, invariants cassés). Cohérent
avec sécurité niveau 1.5 (pas de OOM → RCE style CVE PHP).

**Statut** : actée. P5.

### D8 — ID model : Option C (double niveau)

**Décision** : Id runtime u32 (rapide) + PersistentId hash-128
(stable, partageable). Mapping bidirectionnel dans Store. Hash
structurel Merkle. Sérialisation canonique (tri déterministe).

**Bénéfice clé** : hash-consing persistant (pas juste stabilité).

**Détail** : voir `_store_persistence.md` (à créer en P5).

**Statut** : actée. P5.

### D9 — Heaven DB : Option A (interne) pour 2 ans

**Décision** : composant interne, utilisable par Heaven
(connaissances, corpus, LLM orchestration). Pas de produit
externe avant 2028. Réévaluer après 2 ans si la DB marche pour
Heaven.

**Statut** : actée. Vision 2026-2028.

### D10 — LLM : orchestration en Heaven, inférence FFI

**Décision** : orchestration (prompts, tool-call, vérification,
provenance) en Heaven. Inférence via llama.cpp/candle (FFI C).
"LLM écrit en Heaven" = 10 ans (SIMD, GPU, bande passante,
distribué). Le livre ne promet pas l'inférence native.

**Statut** : actée. Après P5.

### D11 — Comptime / normalisation

**Décision** : Heaven n'a PAS de comptime user-facing. Pas de
#eval, #reduce, phase separation. Le mécanisme d'éval existe
(heaven_eval.hvn) mais n'est PAS branché sur elab.zig.

Pour Cubical : normalisateur interne pendant le type-checking
(réduit transp/hcomp/refl/trans), accessible depuis elab.zig.

**Statut** : actée. Chantier avant le noyau cubical.

### D12 — Heaven-first + performance targets

**Décision** : tout ce qui peut s'écrire en Heaven doit l'être.
Zig autorisé là où Heaven ne peut pas encore aller (allocateur,
runtime bas niveau, FFI). La ligne bouge.

**Objectifs mesurables (benchmarks A/B obligatoires)** :
- Allocation (stream map/filter/sum) : Heaven gagne (QTT + FBIP)
- Startup : Heaven gagne (érasure preuves)
- Taille binaire : Heaven gagne (érasure)
- Boucle numérique : Zig gagne (LLVM 5-50x)
- Protocolaire : Heaven gagne (pas de comparaison Zig)

**Sans mesure publiée, pas de claim "plus rapide que Zig".**

**Statut** : actée. Continu.

### D12-bis — QTT enforced après P5, avant Cubical

**Décision** : LinearChecker enforcement est le levier #1 pour
battre Zig sur la mémoire. Conditionne FBIP, drop immédiat,
érasure.

**À faire** : brancher LinearChecker sur elab.zig, propager dans
MIR, implémenter FBIP, érasure. Benchmarks A/B.

**Estimé** : 3-4 sessions après P5.

**Statut** : actée. Après P5.

### D13 — Backend strategy : QBE first, LLVM if needed

**Décision** : backend natif commence par QBE (existant). Si QBE
ne suffit pas pour D12, migration vers LLVM (ou Cranelift).

**Pourquoi QBE d'abord** : déjà implémenté, 10% du code LLVM,
itération rapide, pas de dépendance externe.

**Quand migrer** : écart > 2x sur charges non-numériques, besoin
SIMD, maintenance QBE > LLVM.

**Statut** : actée. Décision formelle après D12-bis et benchmarks.

### D14 — Backend natif Heaven pur (long terme)

**Décision** : Heaven vise un backend natif pur (assembleur
généré par Heaven, pas QBE/LLVM final). Objectif long terme
(après auto-hébergement E1-E3 + bootstrap).

**Séquence** : QBE (existant) → LLVM (si besoin) → Heaven natif.

**Pourquoi viable** : sur charges Heaven (allocation, protocoles,
fusion, QTT), optimisations haut niveau compensent. Sur boucles
numériques, Heaven perd (5-20x), accepté (FFI vers C).

**Critère succès** : benchmarks D12, Heaven natif ≥ QBE/LLVM sur
charges non-numériques.

**Statut** : actée (direction). Chantier après bootstrap.

### D15 — OTP : OTP-light après P5, OTP complet après auto-hébergement

**Décision** : modèle OTP par étapes.
1. OTP-light coopératif (après P5) : supervision + redémarrage
   sans préemption. S'appuie sur KernelQ étendu.
2. OTP complet préemptif (après auto-hébergement) : scheduler
   préemptif, threads natifs, distribution.
3. OTP vérifiable (recherche, 2-3 ans) : MPST + QTT +
   supervision. Chaque acteur suit un type de session.

**Ce que OTP-light n'est pas** : pas de distribution, pas de hot
upgrade, pas de préemption.

**Statut** : actée. OTP-light après P5.

### D16 — BEAM backend secondaire (option)

**Décision** : BEAM est un backend optionnel, ciblant
OTP/concurrence/distribution. PAS le backend principal (qui reste
QBE/LLVM/Heaven natif pour zéro-GC).

**Ce que BEAM apporte** : scheduler préemptif, isolation totale,
OTP complet, distribution native, écosystème Erlang.

**Ce que BEAM coûte** : performance numérique (5-20x), startup
(100-300ms), GC par processus (incompatible zéro-GC).

**Précédents** : Cure (types dépendants sur BEAM), Gleam, Caramel.

**Statut** : actée. Après P5 + D12-bis. 3-6 sessions.

### D17 — JVM backend tertiaire (option)

**Décision** : JVM est un backend optionnel, ciblant l'écosystème
Java et la performance numérique. PAS le backend principal (casse
zéro-GC, pas de TCO natif, type erasure).

**Ce que JVM apporte** : portabilité, écosystème Java, performance
numérique (GraalVM), profilage.

**Ce que JVM coûte** : GC obligatoire, pas de TCO natif,
type erasure (types dépendants effacés), concurrence threads lourds.

**Précédents** : Scala 3 (Dotty) pour pipeline effacement.

**Statut** : actée. Après P5 + D12-bis. 4-8 sessions.

### D18 — Stratégie backend viable

**Décision** : combiner trois backends avec rôles distincts :
1. **QBE** : backend principal P5-D12bis. Coût 0, 70% perf.
2. **Cranelift** : option si QBE insuffisant (TCO, GC roots).
   80% perf LLVM, 10-20x plus rapide à compiler. 1-2 sessions.
3. **LLVM** : release 1.0, quand benchmarks justifient.
4. **BEAM** : OTP/concurrence, secondaire.
5. **JVM** : écosystème Java, tertiaire.
6. **Heaven natif** : long terme, inspiré Caustic/Lamina.

**Statut** : actée.

## Décisions reportées (déclencheur explicite)

### Cubical noyau : quand exactement ?
Après P5, décision formelle avec spec dédiée (intervalle, Kan
operations, Glue, canonicité).

### C1 — Licence noyau
Réécrire from scratch (pas copier Agda MIT) — acté par défaut, à
confirmer avant d'écrire le noyau.

### C2 — Plateformes
Linux first, autres best-effort. À confirmer dans le livre
(retirer "multi-plateforme" absolu).

### C3 — LLM cible
Local (llama.cpp) pour reproductibilité, API pour itération.
À trancher au moment du prototype LLM-verify.

## Récapitulatif (19 décisions)

D0 Cubical HoTT | D1 noyau Zig d'abord | D2 isolation totale |
D3 QTT façade | D4 backend C après P5 | D5 parseurs fusionnés |
D6 modules minimaux | D7 Result explicite | D8 ID Option C |
D9 DB interne | D10 LLM orchestration | D11 normalisateur |
D12 Heaven-first | D12-bis QTT enforced | D13 QBE first |
D14 Heaven natif | D15 OTP | D16 BEAM | D17 JVM | D18 backends

**Décisions à prendre : 0** (toutes actées ou reportées avec
déclencheur explicite).
