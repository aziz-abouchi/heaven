<!-- HEAVEN:hkt-v1-plan -->
# HKT V1 — classes de types (plan)

## État réel V0.5 (vérifié 2026-10-19)

`sig name : type` est **parsé et fonctionnel** (`heaven_expr.zig:914-1008`) :
- arité déclarée (`sig wrap : (f : Type) -> (a : Type) -> f a -> f a`).
- vérification de l'arité à l'appel (`heaven_expr.zig:2248`).
- `test_hkt.hvn` 15/15 : signatures et appels avec `f a` en tête.

**Ce que V0.5 NE fait PAS** (`_hkt.md` §6) :
1. `class Functor f where fmap : ...` — pas de classe.
2. `Functor f => ...` — pas de contrainte.
3. `forall a. a -> a` explicite — quantification implicite seulement.
4. Instances multiples (`Int` Monoid pour `+` ET `*`) — pas de résolution.

## V1 — parser `class` / `instance`

### V1a — déclaration seule (1 session, sucre)
Syntaxe :
    class C f where
      op : (a : Type) -> f a -> f a
    instance C List where
      op a xs = xs
Stockage : `engine.classes: HashMap(Sym, ClassDecl)`,
`engine.instances: HashMap((Sym, Sym), InstanceImpl)`.
**Ne résout PAS** `op f` — il faut nommer `op_list`. Sucre qui déclare,
ne dispatche pas. Utile pour la spec et les tests.

### V1b — résolution par type (2 sessions)
`op C f x` résout à l'instance `(C, f)`. Nécessite :
- un mécanisme d'inférence du type de `f` (aujourd'hui implicite).
- gestion des instances multiples (conflit `Int` Monoid+/Monoid*).
Ambition : 2 sessions minimum, risque de découvrir que le type
checker actuel ne suffit pas.

### V1c — contraintes (1 session, après V1b)
`Functor f => ...` propagé dans les signatures. Nécessite V1b.

## Effort total V1

**3-4 sessions** (V1a + V1b + V1c). Pas un bloc de fin de session.

## Ce qu'on peut faire en 30 min

**Rien de plus que tracer.** Le parser n'a pas `class`/`instance`,
V1a = 1 session. Ne pas promettre V1 sans V1a.

## Décision

V1a = prochaine session HKT. V1b/V1c = après. Ne pas activer
`sig`-with-classes tant que la résolution n'existe pas — ça
donnerait l'illusion sans le dispatch.

## Lien `_algebras.md`

`_algebras.md` (Setoid, Ord, Functor, Monad, Fantasy Land) dépend
de HKT. V1a débloque la **déclaration** de la hiérarchie, V1b le
**dispatch**. V0.5 permet d'écrire les lois de chaque instance
séparément (`fmap_list`, `fmap_maybe`), pas encore `fmap f`.
