# Store MOP v0

> Statut : spec figee. Aucune implementation. Ce document definit
> l'interface entre HVN et le Store. Il precede eval.hvn.
>
> Reference : docs/spec/_store_ast.md (decision Modele A).

## Contexte

Le Store hash-conse est la representation canonique des termes
Heaven. Il existe deja, en Zig (`src/core/expr.zig`). HVN n'a
aujourd'hui aucun moyen de l'appeler.

Le MOP (Meta-Object Protocol) du Store est la couche d'acces qui
permet a HVN de manipuler des termes sans jamais voir la
representation physique.

## Principe

HVN ne manipule jamais directement la representation memoire du
Store.

Il manipule des `Id` et demande au Store des operations
semantiques.

    HVN
     |
     | @store_*
     v
    Zig (Store)

Consequence : ni `payload`, ni `span_a`, ni `span_b`, ni
`pool.items` ne sont exposes a HVN. Toute la physique reste en
Zig.

## Decision Modele A

`Id` est l'unique representation d'un terme.

    Id = Expr = Value

Il n'y a pas de type `Value` separe, pas de type `Expr`
separe, pas de conversion.

`eval : Id -> Id -> Id` (env -> terme -> valeur).

Reference complete : docs/spec/_store_ast.md.


## Les 14 primitives

### Inspection

| Primitive | Retour | Role |
|---|---|---|
| @store_tag(id) | Tag | Renvoie le tag semantique |
| @store_child(id, i) | Id | Renvoie le i-eme enfant logique |
| @store_arity(id) | u32 | Renvoie le nombre d'enfants |

### Atomes

| Primitive | Retour | Role |
|---|---|---|
| @store_lit_int(n) | Id | Cree un litteral entier |
| @store_sym(name) | Id | Cree un symbole interned |

### Construction

| Primitive | Retour | Role |
|---|---|---|
| @store_apply(f, ...) | Id | Cree une application n-aire |
| @store_lambda(sym, body) | Id | Cree une abstraction |
| @store_bind(sym, val, body) | Id | Cree une liaison |
| @store_relation(head, lhs, rhs) | Id | Cree une relation |

### Transformation

| Primitive | Retour | Role |
|---|---|---|
| @store_map_children(id, f) | Id | Reconstruit avec enfants transformes |

### Identite

| Primitive | Retour | Role |
|---|---|---|
| @store_equal(a, b) | Bool | Egalite structurelle |

### Note

`@store_apply` est variadique. Il accepte 0 ou plusieurs arguments
apres la fonction.

Toutes les autres primitives ont une arite fixe.


## Table tag -> enfants

Cette table est le contrat de `@store_child(id, i)`. Elle definit
l'ordre canonique des enfants logiques pour chaque tag.

| Tag | child(0) | child(1) | child(2..n) |
|---|---|---|---|
| lit | (aucun) | (aucun) | (aucun) |
| sym | (aucun) | (aucun) | (aucun) |
| apply | fonction | arg 0 | arg 1, arg 2, ... |
| lambda | corps | (aucun) | (aucun) |
| bind | valeur | corps | (aucun) |
| relation | lhs | rhs | (aucun) |

`@store_arity(id)` retourne le nombre d'enfants effectifs selon
cette table :

| Tag | arity |
|---|---|
| lit | 0 |
| sym | 0 |
| apply | 1 + nb_args |
| lambda | 1 |
| bind | 2 |
| relation | 2 |

Note importante : pour `apply`, `child(0)` est la fonction, pas le
premier argument. `child(1)` est le premier argument. C'est
coherent avec la representation physique du Store
(`span_a[0] = fonction`, `span_a[1..] = args`), mais c'est le
MOP qui garantit cette coherence, pas la structure brute.

## Semantique de @store_map_children

`@store_map_children(id, f)` reconstruit un noeud de meme tag avec
chaque enfant remplace par `f(child)`.

    @store_map_children(id, f)
        = reconstruct(tag(id), [f(child(id, 0)), ..., f(child(id, n-1))])

Proprietes :

1. **Non destructif.** Ne modifie jamais `id`.
2. **Reconstruction hash-consee.** Si tous les `f(child)` sont egaux
   aux `child` originaux (meme Id), le resultat est le meme Id que
   `id`.
3. **Aucune semantique du tag.** `map_children` ne connait pas la
   difference entre `apply` et `lambda` au dela de la table ci-dessus.

Test de validation : `@store_map_children(x, identity) == x` (meme Id).


## Test minimal

Test 1 -- construction

    let f = @store_sym("+")
    let a = @store_lit_int(1)
    let b = @store_lit_int(2)
    let x = @store_apply(f, a, b)

    @store_tag(x) == apply

Test 2 -- inspection

    @store_arity(x)      == 3
    @store_child(x, 0)   == f
    @store_child(x, 1)   == a
    @store_child(x, 2)   == b

Test 3 -- reconstruction identite

    let x2 = @store_map_children(x, lambda i. i)
    @store_equal(x, x2) == true

Test 4 -- transformation

    let x3 = @store_map_children(x, lambda i. eval Nil i)
    -- ou eval n'existe pas encore : un f arbitraire qui renvoie
    -- le meme Id, pour valider le chemin.

## Point ouvert : .bind a deux usages

Un WIP recent (session parallele, non commite) modifie `Store.pi()`
pour que le binder d'un Pi soit un `.bind` ordinaire :

    Pi(x : A). B  =>  apply(sym("Pi"), [bind(x, A, _), B])

Donc `.bind` sert maintenant a deux choses :

1. **env-binding** : chaine pour `Env` (Modele A).
2. **Pi-binder** : couple (nom, type) avec corps vide.

Les deux ont la meme forme physique : `payload = nom`,
`span_a[0] = valeur`, `span_a[1] = corps`.

Pour le MOP, ce n'est pas un probleme : `@store_child(bind, 0)` et
`@store_child(bind, 1)` restent coherents. Mais la **semantique**
de ce qu'on met dans `child(1)` (le corps) differe selon l'usage.

A documenter dans `_store_ast.md`.

## Contraintes

1. Aucune primitive n'expose `payload`, `span_a`, `span_b`, `aux`,
   ni `pool.items`.
2. Les listes HVN ne sont pas des arguments d'`apply`. `apply` a
   ses propres enfants, geres par la table ci-dessus.
3. Env n'est pas une liste. C'est une chaine de `bind`.
4. `List` utilisateur est un ADT HVN normal, implemente dans
   `core/std/list.hvn` -- hors MOP.
5. Le MOP n'a aucune notion de `Value`. Tout est `Id`.

## Etat

| Element | Etat |
|---|---|
| Store | implemente (Zig) |
| @store_* primitives | non implementees |
| Table tag -> children | spec figee, ce document |
| Test minimal | non implemente |

