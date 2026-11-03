# Chapitre 41 — Sémantique formelle de Heaven

> **Statut** : squelette (2026-11-03). Corps formel à rédiger.
> Public prioritaire : rigueur mathématique. Encadrés narratifs pour
> littéraires et philosophes.
>
> Références structurantes : Pony (`fast-cheap-with-proof.pdf`),
> CompCert (Leroy), *HoTT Book* (Univalent Foundations Program),
> Pierce *Types and Programming Languages*.

---

## 41.1 Pourquoi formaliser

*Encadré narratif — à rédiger.*

Pourquoi un langage a besoin d'une preuve mathématique de sa correction.
Trois précédents industriels : CompCert (C, CompCert C), RustBelt (Rust),
Pony (types de capacités). Position de Heaven : CIC + Eq/refl, cible HoTT.

## 41.2 Syntaxe du noyau

Renvoi `docs/spec/_core_syntax.md` §1.2.

*À rédiger* : présentation des Term, conventions de nommage (HoTT Book),
BNF complète.

## 41.3 Système de typage

Renvoi `docs/spec/_core_typing.md` (à créer).

*À rédiger* : règles de formation, introduction, élimination ;
hiérarchie prédicative ; jugements `Γ ⊢ t : A`.

## 41.4 Sémantique opérationnelle

Renvoi `docs/spec/_core_opsem.md` (à créer).

*À rédiger* : valeurs, β/ι/δ/ζ, congruence, `whnf` (kernel/peano.zig:223).

## 41.5 Métathéorie

*À rédiger* :
- **Progress** : `⊢ t : A ⇒ t value ∨ ∃ t'. t → t'`
- **Preservation** : `⊢ t : A ∧ t → t' ⇒ ⊢ t' : A`
- **Canonicité** : `⊢ t : Nat ⇒ t ≡ zero ∨ ∃ u. t ≡ succ u`
- **Normalisation forte** (CIC) — énoncé, preuve esquissée (Tait/Girard)

## 41.6 HoTT cible — Layer 2

Renvoi `_core_syntax.md` §3.

*À rédiger* : Path, J, univalence, HIT. Ce qui manque au kernel pour
tenir la promesse HoTT. Roadmap technique.

## 41.7 Mécanisation Cubical Agda

*À rédiger* : correspondance Term Heaven ↔ Term Cubical Agda.
`Cubical.Foundations.Equiv`, `Cubical.HITs.*`. Repo `heaven-formal/`.

## 41.8 Ce que ça garantit — et ce que ça ne garantit pas

*Encadré narratif + liste formelle.*

Ce qu'on prouve : soundness du kernel, canonicité, normalisation.
Ce qu'on ne prouve pas : soundness du runtime (`expr.zig`), du bridge
C, des I/O. Ce qu'on spécifie mais non implémente : Path, univalence.

---

## Plan de travail

| Section | Dépend de | Effort |
|---|---|---|
| 41.1 | — | 1 session |
| 41.2 | `_core_syntax.md` | 1 session |
| 41.3 | `_core_typing.md` | 1–2 sessions |
| 41.4 | `_core_opsem.md` | 1 session |
| 41.5 | 41.2–41.4 | 2 sessions |
| 41.6 | `_core_syntax.md` §3 | 1 session |
| 41.7 | `heaven-formal/` init | 2 semaines |
| 41.8 | 41.5 | 1 session |

**Session A terminée** = squelette + `_core_syntax.md` draft v0.
**Session B** = retour au code : **Propagators V1**.
