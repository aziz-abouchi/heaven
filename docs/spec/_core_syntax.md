# Core syntax — noyau formel de Heaven

> Statut : **draft v0 (2026-11-03)**. Source de vérité pour le chapitre 41
> (`docs/book/src/41-semantique-formelle.md`) et la mécanisation Cubical Agda
> (repo `heaven-formal/`, à venir).
>
> **Trois couches**, à ne pas confondre :
> 1. Noyau de preuve (`src/kernel/`) — **objet de la formalisation**
> 2. Runtime (`src/core/expr.zig`) — hors formalisation (évaluateur non typé)
> 3. HoTT cible — **roadmap**, non implémenté (cf. `_claims_vs_reality.md`)

---

## 1. Noyau de preuve (`src/kernel/`)

### 1.1 Sortes et univers

    Sort ::= Type_i | Prop_i          -- i ∈ ℕ, prédicatif
    Type_i : Type_{i+1}                -- cumulatif
    Prop   : Type_0                     -- imprédicatif (à vérifier : actuellement 0 %, cf. _claims_vs_reality:18)

Vérification croisée : `elab.zig:808` `getUniverse(level: u32)`, `elab.zig:815` `universeLevel(id)`.

### 1.2 Termes

    Term ::= x                          -- variable
           | Type_i                     -- sorte
           | Π (x : A) . B              -- type dépendant (produit)
           | λ (x : A) . t              -- abstraction
           | t u                         -- application
           | Σ (x : A) . B              -- paire dépendante
           | (t, u)                      -- introduction Σ
           | π₁ t | π₂ t                 -- projections
           | Eq (A) (a) (b)              -- égalité (propositionnelle)
           | refl (A) (a)                -- réflexivité
           | J (A) (a) (C) (d) (b) (p)   -- éliminateur Eq (à vérifier : présentation)
           | nat | zero | succ t         -- Peano
           | Quot (A) (R)                -- quotient (kernel.zig:8)
           | [t] | quo t                 -- classes / représentants

Vérification croisée : `src/kernel/ast.zig` (à inspecter — cf. commande Bloc 3),
`src/kernel/peano.zig:32` (`refl : Eq(a,a)`), `src/kernel/typechecker.zig:166`.

### 1.3 Contextes et jugements

    Γ ::= · | Γ, x : A

    Γ ⊢ A : Type_i          -- A est un type au niveau i
    Γ ⊢ t : A                -- t habite A
    Γ ⊢ t ≡ u : A            -- conversion définitionnelle
    Γ ⊢ t → t'                -- réduction (β, ι, δ, ζ)

### 1.4 Équivalence et quotients

Le kernel expose `Eq (A) (a) (b)` et `refl`, mais **pas** de `Path`
(homotopique). Les quotients sont présents (`kernel.zig:8` : « quotients
complets ») — formalisation à rédiger.

### 1.5 Ce qui **n'est pas** dans le noyau

- ❌ `Path (A) (a) (b)` (type identité homotopique)
- ❌ `J` sous forme de transport / `hcomp` / `transp`
- ❌ Univalence (`ua : A ≃ B → A = B`)
- ❌ HIT (types inductifs supérieurs)
- ❌ `Prop` imprédicatif (partiel : 0 % selon `_claims_vs_reality:18`)

→ Ces éléments sont dans le noyau **HoTT cible** (§3), non implémenté.

---

## 2. Runtime (`src/core/expr.zig`)

**Non typé. Hors formalisation.** Documenté pour référence — c'est ce que
l'évaluateur (`engine_expr.zig`) manipule.

    Tag ::= lit | sym | apply | bind | lambda | relation
          | hole | evar | true | false
          | int | float | string | var_tag
          | let | letrec | fun | eq | add | sub | mul | div | mod
          | and_tag | or_tag | not
          | identifier | pi_tag | universe_tag | sigma
          -- ...

Le runtime n'a **pas** de type system. Toute la sûreté (soundness) est
portée par le noyau (§1), pas par le runtime. C'est une architecture
classique (c.f. CompCert : sémantique formelle du kernel, extraction C
pour le runtime).

---

## 3. HoTT cible (roadmap Layer 2, non implémenté)

Spécification **aspirationnelle**. À documenter en chapitre 41 §41.6–41.9,
avec la liste exacte de ce qu'il faudra ajouter au kernel pour tenir la
promesse HoTT.

    Term ::= ...                          -- tout §1.2
           | Path (A) (a) (b)              -- type identité
           | refl_path a                    -- refl : Path a a
           | J_path (A) (a) (C) (d) (b) (p) -- éliminateur
           | hcomp ... | transp ...        -- opérations cubiques
           | ua (e : A ≃ B)                -- univalence
           | HIT                             -- types inductifs supérieurs

Point de référence : *HoTT Book*, Cubical Agda (`Cubical.Foundations.*`,
`Cubical.HITs.*`).

---

## 4. Choix de conception

- **Kernel vs runtime séparés** : le noyau est typé, le runtime ne l'est pas.
  Le noyau est extrait/projeté dans le runtime via `elab.zig` (à documenter
  §41.4.3).
- **Univers hiérarchiques** dans `elab.zig`, pas dans `expr.zig` : la
  vérification de niveau est portée par le typechecker, le runtime peut
  rester plat.
- **`Eq`/`refl` Peano-style** dans le kernel, pas `Path` HoTT : c'est un
  choix conservateur (soundness CIC est plus simple que soundness HoTT).

---

## 5. Livrables de formalisation

| Étape | Livrable | Statut |
|---|---|---|
| 1 | `_core_syntax.md` (ce fichier) | ✅ draft v0 |
| 2 | `_core_typing.md` — règles de typage §1 | ⬜ |
| 3 | `_core_opsem.md` — sémantique petits-pas | ⬜ |
| 4 | `_core_soundness.md` — progress + preservation | ⬜ |
| 5 | `_core_hott_roadmap.md` — §3 détaillé | ⬜ |
| 6 | `heaven-formal/` — Cubical Agda | ⬜ |

---

## Marqueurs `[À VÉRIFIER]`

- `ast.zig` du kernel : syntaxe exacte des Term (Π, Σ, Eq, refl, quotients, Peano)
- `elab.zig:808` : univers cumulatifs ou non
- `typechecker.zig` : présentation de `J` (éliminateur Eq) — implicite ou explicite ?
- `kernel.zig:8` « quotients complets » : quelle forme ? `Quot (A) (R)` ?
- `peano.zig` : Peano est-il un type primitif ou défini via `Type_0` ?
