<!-- HEAVEN:hit-status -->
# HIT — Higher Inductive Types (état 2026-10-19)

## Définition

HIT = type inductif avec **constructeurs de chemins** en plus des
constructeurs de points. Exemple : le cercle `S¹` = `base : S¹` +
`loop : base = base`. Les HIT sont un **sous-ensemble** de HoTT
(pas besoin de Cubical complet pour les HIT simples, mais les
règles de composition `hcomp` en ont besoin).

## État Heaven actuel

- **Types inductifs simples** : ✅ (`data A = ...`, `data R = Ok A | Err`).
- **HIT comme types inductifs sans règles de composition** : ⚠️
  possible en V0.x (`_hott.md` §5). On peut déclarer `data S1 = Base
  | Loop` mais `Loop` n'est **pas** un chemin `Base = Base`, c'est un
  point. Pédagogique, pas HoTT.
- **HIT avec règles de composition (hcomp)** : ❌ absent. Nécessite
  Cubical (Kan operations).

## Décision

Voir `_hott_cubical_plan.md` (4 sous-chantiers S1-S4) :
- **S1 quotients** : 1-2 sessions, indépendant, **priorité haute**
  (débloque Set, multiset, ℤ = ℕ×ℕ/~).
- **S2 proof-irrelevance** : 1-2 sessions.
- **S3 univers structuré** : 2-3 sessions.
- **S4 Cubical** : multi-années, recherche.

## Ce qui est faisable en V0.x

- HIT pédagogiques (cercle, intervalle, suspension) comme `data`
  simples avec commentaires. Pas de HoTT, mais explicite dans le book.
- Quotients kernel (S1) : **déjà fonctionnel** (`ast.quot`,
  `typechecker`, `conversion.lift`, `test_quotient` 2/2) mais pas
  exposé en `.hvn` (2-3 sessions, `_quotients_expose_plan.md`).

## Priorité

HIT avec hcomp = hors-scope. S1 (quotients) = prochain chantier
noyau après H1-N2 et MPST-V1+.
