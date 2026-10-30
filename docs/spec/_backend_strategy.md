# Stratégie backend (2026-10-26)

Synthèse des décisions D13, D14, D16, D17, D18. Chaque backend a un
rôle distinct. Ce ne sont pas des concurrents, ils sont
complémentaires.

## Tableau comparatif

| Backend | Perf vs C -O2 | Compilation | Adéquation invariants | Coût | Rôle |
|---|---|---|---|---|---|
| QBE | 70% | Très rapide | partiel | 0 (intégré) | Itération P5-D12bis |
| Cranelift | 60-70% | 10-20x plus rapide que LLVM | moyen | 1-2 sessions | Si QBE insuffisant |
| LLVM | 100% | Lent | bon (zéro-GC possible) | 2-3 sessions | Release 1.0 |
| BEAM | JIT proche C | Rapide | OTP ✅, zéro-GC ❌ | 3-6 sessions | OTP/concurrence |
| JVM | 105-115% (GraalVM) | Moyen | zéro-GC ❌, TCO ❌ | 4-8 sessions | Écosystème Java |
| Lamina | within 1.8x C/C++/Rust | Rapide | zéro dépendance externe | 2-4 sessions | Indépendance moyen terme |
| Heaven natif | à mesurer | n/a | total | 6-12 mois | Long terme |

## Ordre d'adoption

1. **QBE** (0 coût) : P5-D12bis. Valide QTT enforced, FBIP,
   benchmarks A/B.
2. **Cranelift** (1-2 sessions) : si QBE insuffisant (TCO, GC
   roots, perf). 80% LLVM, compilation rapide, production-ready.
3. **LLVM** (2-3 sessions) : release 1.0. Quand benchmarks
   justifient. 100% perf, comparaison équitable avec Zig.
4. **BEAM** (3-6 sessions) : OTP/concurrence/distribution.
   Backend secondaire, PAS principal (casse zéro-GC).
5. **JVM** (4-8 sessions) : écosystème Java, perf numérique.
   Backend tertiaire (casse zéro-GC et TCO).
6. **Heaven natif** (6-12 mois) : après bootstrap. Inspiré
   Caustic (39k LOC self-hosted) et Lamina (within 1.8x C).

## Compromis viable

Le compromis n'est pas un seul backend qui fait tout. C'est une
chaîne où chaque étape a un coût marginal décroissant :

- **QBE maintenant** : validation, itération
- **Cranelift demain** : perf/coût le plus viable
- **LLVM release** : performance maximale
- **BEAM/JVM** : options séparées, charges spécifiques
- **Heaven natif** : indépendance long terme

## Précédents à étudier

- **Cure** : types dépendants + FSM + OTP sur BEAM
- **Gleam** : statiquement typé sur BEAM
- **Scala 3 (Dotty)** : pipeline effacement pour JVM
- **Ballerina** : JVM surpasse son runtime natif (100x)
- **Caustic** : compilateur + assembleur + linker self-hosted
- **Lamina** : backend SSA-based multi-arch, zéro LLVM

## Ce que Heaven ne fera pas

- Reconstruire le calcul symbolique de Mathematica (SymPy/Sage
  via FFI)
- Reconstruire la base de connaissances (Wikidata/DBpedia)
- Battre Zig sur les boucles numériques (LLVM reste)
- Promettre "plus rapide que Zig" sans benchmarks publiés

## Critères de décision par étape

**P5-D12bis** : QBE. Critère : benchmarks allocation montrent
Heaven ≥ Zig (avec QTT enforced).

**Après P5** : si écart > 2x sur charges non-numériques, Cranelift.
Critère : compilation < 1s, perf ≥ QBE.

**Release 1.0** : si benchmarks release justifient LLVM. Critère :
100% perf vs C, mais compilation lente acceptée.

**Long terme** : Heaven natif après bootstrap. Critère : benchmarks
D12 ≥ QBE/LLVM sur charges non-numériques.

## Voir aussi

- `_decisions.md` : D13 (QBE first), D14 (Heaven natif),
  D16 (BEAM), D17 (JVM), D18 (stratégie)
- `_emancipation_roadmap.md` : E1-E10
- `docs/STATUS.md` : état actuel des backends

## Mises à jour 2026-10-30 (soir) — selfhost natif

Le selfhost natif **fonctionne** : `bin/heaven.hvn` → ELF x86_64
(QBE), avec support :

- `main = EXPR` compilé (avant : seulement expression nue)
- `const_str` (strings littérales, `data $str_N`)
- `@puts`, `@printf`, `@getenv`, `@strcmp` (extern_call glibc)
- `@argv N` (ABI SysV, wrapper `l $main(l argc, l argv)`)
- Wrapper `ret %r` (exit code = valeur de dispatch)

Dettes connues (voir annexe G) : G.25 (multi-clauses), G.33 (`@argv`
fn user), G.34 (`@strcmp "str"` fn user), G.31 (workaround skip
fn_defs avec str_pool).

Voir `docs/book/src/39-selfhosting.md`.
