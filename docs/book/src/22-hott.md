# Chapitre 22 — HoTT, HITs, Univalence

> *« L'égalité n'est pas une proposition, c'est un type. »*
> — Martin-Löf, *Intuitionistic Type Theory* (1984)

Le chapitre 8 a présenté les preuves. Un théorème affirme `a = b`,
et on le prouve par réécriture, induction, ou simplification. Mais
*qu'est-ce que* `a = b` ? Une proposition vraie ou fausse ? Ou
quelque chose de plus riche ?

La **théorie des types homotopiques** (HoTT) propose une réponse
radicale : **l'égalité est un type**. Une preuve de `a = b` est
un habitant du type `a = b`. Et entre deux preuves du même `a = b`,
il peut y avoir *plusieurs* habitants — qui sont eux-mêmes des
chemins, des homotopies.

## 1. Ce que Heaven V0 est vraiment

Heaven V0 est un **CIC standard** — Calcul des Constructions
Inductives, comme Coq, Agda, Lean. Pas HoTT.

Trois propriétés distinguent CIC de HoTT :

- **UIP** (Uniqueness of Identity Proofs) : deux preuves du même
  `a = b` sont identifiables. En HoTT, c'est faux.
- **Pas de types de chemins** : `a = b` est une proposition. En
  HoTT, c'est un type.
- **HITs partiels** (2026-10-24) : la grammaire accepte les
  path constructors (`data S1 = Base | Loop : Base = Base`),
  mais `elab.zig` ignore encore les champs `from`/`to`. Parse
  seulement, pas encore d'éliminateur.

UIP et absence de types de chemins restent vrais, mais HIT n'est
plus totalement absent.

## 2. Pourquoi V0 n'est PAS HoTT

Ce n'est pas un oubli : c'est un **choix**. HoTT demande une
refonte profonde du noyau, pour deux raisons.

**Raison 1 — Le kernel devrait changer de sémantique.** En CIC,
`a = b` est une proposition qu'on peut habiter par `refl`. En
HoTT, `a = b` est un type dont les habitants sont des chemins, et
ces chemins ont eux-mêmes une structure. C'est une autre théorie.

**Raison 2 — La complexité explose.** HoTT demande de gérer :
- les types de chemins (`a = b`)
- les chemins entre chemins (`p = q` où `p q : a = b`)
- l'univalence (`a ≃ b` → `a = b`)
- les HITs (types inductifs supérieurs)

C'est un **chantier de plusieurs années**, avec une expertise rare.

![HoTT vs CIC](images/22-hott-vs-cic.svg)

## 3. Deux voies pour aller vers HoTT

### Voie A — HoTT axiomatique

On ajoute des **axiomes** (univalence, functional extensionality).
Simple à implémenter, mais :
- On perd la **normalisation forte** (les preuves ne calculent plus).
- La cohérence n'est plus garantie par construction.

### Voie B — Cubical Type Theory

On **refond** le noyau avec une sémantique cubique (CCHM, 2016).
- Computationnel : les preuves calculent.
- Cohérence prouvée.
- Chantier de plusieurs années.

**Décision pour V0** : rester en CIC standard. Documenter HoTT
séparément. Voir `docs/spec/_hott.md` pour l'analyse complète.

## 4. Les quotients — un cas à part

Un **quotient** `A / R` est un type où on identifie les éléments
de `A` selon une relation `R`. Exemple : `ℤ / 2ℤ` identifie les
entiers pairs entre eux.

En HoTT, on peut définir les quotients comme des **HITs** — c'est
leur cas d'usage canonique.

En CIC standard, deux options :

1. **Setoïdes** : `Setoid A = (A, R)` avec `R` relation
   d'équivalence explicite. On transporte `R` partout où on
   utilise `A`. Fonctionne **immédiatement** en V0.
2. **Quotients par HITs** : nécessite HoTT. Chantier séparé.

**Recommandation** : commencer par les setoïdes. Ça débloque 90 %
des cas pratiques sans toucher au noyau.

    Setoid Int modulo 2 :
      A = Int
      R(a, b) = (a mod 2) == (b mod 2)

## Ce qu'on a appris

- Heaven V0 est **CIC standard**, pas HoTT.
- UIP et absence de chemins typés restent vrais. HIT partiel
  (path_constructor parse depuis 2026-10-24, pas encore éliminé).
- HoTT demande une **refonte du noyau** (Voie A : axiomes ;
  Voie B : cubical).
- Les **quotients** se font par **setoïdes** en V0, sans toucher
  au noyau.
- HoTT est un **chantier de plusieurs années** — pas un oubli.

## Dans Heaven aujourd'hui (2026-10-24)

Le parser accepte les **path constructors** depuis le 24 octobre 2026 :

    data S1 = Base | Loop : Base = Base

La grammaire tree-sitter (`vendor/tree-sitter-heaven/grammar.js`)
produit un `data_constructor` avec champs `from` et `to`. L'AST est
correct, mais `elab.zig` **ignore encore** ces champs — le path est
parse, pas elaboré. C'est l'etape E1/E2 de la roadmap
emancipation (`docs/spec/_emancipation_roadmap.md`).

### Facade Path rank-1 (`lib/hott/path.hvn`)

En attendant l'eliminateur HoTT, une facade rank-1 existe :

    data Path = MkPath witness start end
    refl a                     -- MkPath 0 a a
    sym (MkPath w s e)         -- MkPath (-w) e s
    trans p q                  -- composition
    ap f p                     -- application
    transport P p x            -- P e

Le `witness` est un entier symbolique (0 = refl, -w = sym, w1+w2+1 =
trans). Pas de typechecking formel — `DependentChecker` est encore
stub dans `types.zig`. 14 tests dans `tests/test_hott_path.hvn`.

Voir aussi : `docs/spec/_hott_roadmap.md` (5-6 sessions pour HIT
complet, eliminateur, rank-2).

