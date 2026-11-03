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

Conformément à `src/kernel/ast.zig:3-37` :

    UniverseLevel ::= concrete(n)          -- n ∈ ℕ
                    | max(UniverseLevel, UniverseLevel)

    Sort ::= prop                          -- Prop unique (non levelé dans le kernel actuel)
           | type_sort(UniverseLevel)      -- Type_i, i ∈ ℕ

    Type_i : Type_{i+1}                    -- hiérarchie via concrete(n+1)
    Prop : Type_0                           -- Prop au niveau 0 (imprédicatif à préciser)

**Ce que ça implique** : le kernel est un **CIC à univers hiérarchiques + Prop non-levelé**
— plus proche de Coq que de HoTT. `max(a, b)` est calculé explicitement
(`ast.zig:20`), ce qui permet les bornes supérieures de niveaux (règle Pi).

Vérification croisée runtime : `elab.zig:808` `getUniverse(level)`,
`elab.zig:815` `universeLevel(id)` — côté évaluateur, `Type n` est un
`apply(sym "Type", int n)`, `Prop` = `sym "Prop"` retournant 0.

**À vérifier (§41.3)** : `Prop` est-il imprédicatif dans `checkSortLeq`
(`typechecker.zig:57`) ?

### 1.2 Termes

Conformément à `src/kernel/ast.zig:39-...` :

    Term ::= sort(Sort)                          -- Type_i, Prop
           | variable(n : usize)                 -- De Bruijn (index)
           | pi(name, A : Term, B : Term)        -- Π (x : A) . B
           | lambda(name, A : Term, t : Term)    -- λ (x : A) . t
           | app(f : Term, u : Term)             -- t u

           -- Quotients (CIC, kernel.zig:8)
           | quot(A : Term, R : Term)            -- Quot(A, R)
           | class(Q : Term, x : Term)           -- [x] dans Quot(A, R)
           | lift(Q, B, f, proof)                -- éliminateur du quotient

           -- Égalité intensionnelle (CIC, pas HoTT)
           | eq(A : Term, a : Term, b : Term)    -- Eq A a b
           | refl(...)                            -- refl A a

    -- Peano (`peano.zig`, module séparé) :
    --   nat, zero, succ, eq_rect_nat, add, mul, ...
    --   encodés DANS peano.zig, pas dans ast.zig (Church/Scott ou natifs,
    --   à vérifier — cf. peano.zig:32, :155)

**Ce qui n'est PAS dans `ast.zig`** (contrairement au draft v0) :
- ❌ `Σ (Sigma)` — pas de paire dépendante visible dans les 40 premières
  lignes inspectées. À chercher dans le reste de `ast.zig` ou ailleurs
  (`test_pi.zig` suggère que seul Pi est testé).
- ❌ `J` / `eq_rect` — pas vu dans `ast.zig` ; le kernel a `refl` mais
  l'éliminateur Eq est peut-être `eq_rect_nat` (peano.zig:909) ou
  implicite.
- ❌ `nat`, `zero`, `succ` dans le Term — Peano vit dans `peano.zig`.

Vérification croisée : `src/kernel/typechecker.zig:166` (`refl` typé
`Eq A a a`), `src/kernel/peano.zig:32`, `:155`, `:909`.

**Action §41.3** : lister exhaustivement les variants de `Term`
via `grep -c '^    [a-z_]' src/kernel/ast.zig` — la présentation
ici est un sous-ensemble, pas l'inventaire complet.

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
