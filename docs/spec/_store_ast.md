# Store = AST (Modele A)

> Statut : decision figee. Ce document precise la decision
> architecturale prise le 2026-10-04 : le Store est l'AST de
> Heaven. Il n'y a pas de deuxieme representation.
>
> Reference : docs/spec/_store_mop.md (MOP v0).

## Decision

Il n'y a pas de type `Expr` separe ni de type `Value` separe.

    Id = Expr = Value

Une expression, sa representation dans le Store, et sa valeur
evaluee sont le meme objet. Un `Id` ne "contient" pas une
expression ; il **est** l'expression.

## Consequence sur eval

Une fonction d'evaluation met en relation un environnement et un
terme, et retourne un terme :

    eval : Id -> Id -> Id
           (env) (terme) (valeur)

Aucun `Value` intermediaire, aucune conversion `Expr -> Value`,
aucune phase de quotation.

## Env n'est pas une List

`Env` est une chaine specialisee de bindings :

    Env = env_nil
        | env_bind(sym, value, parent)

Ce n'est **pas** un `List (Sym, Id)`. C'est une structure dediee,
avec sa propre semantique de lookup et d'extension.

Pourquoi : un `List` generique prendrait deux noeuds cons par
binding. Un `env_bind` en prend un seul. Et surtout, `Env` n'a pas
la meme semantique d'iteration qu'un `List` : on ne le parcourt
jamais en entier, on fait un lookup.

Un `env_bind` peut etre physiqueement un `.bind` du Store
(meme tag, meme forme). C'est un usage legitime, distinct du Pi-
binder (voir section suivante).

## List utilisateur != Apply.args

Deux notions de liste coexistent, et elles ne doivent pas etre
confondues.

**Apply.args** : representation interne des arguments d'une
application. Native dans le Store (span contigu). Jamais exposee a
HVN sous forme de liste. Le MOP fournit `@store_child(apply, i)`
et `@store_arity(apply)`.

**List utilisateur** : ADT HVN normal.

    data List a = Nil | Cons a (List a)

Implementee dans `core/std/list.hvn`. N'a aucun rapport avec les
arguments d'un `apply`. Peut etre utilisee partout ailleurs.

## Span jamais expose

Un `Span` est une plage dans `pool`. C'est un detail de
representation.

HVN n'y a jamais acces directement. Il utilise :
- `@store_child(id, i)` pour la navigation logique
- `@store_map_children(id, f)` pour la transformation

`pool.items`, `span_a`, `span_b`, `payload`, `aux` restent dans
Zig.

## bind a deux usages

`.bind` est un tag unique du Store. Il sert a deux choses
distinctes :

1. **Env-binding** : chaine pour `Env` (voir plus haut).
   Le corps (`child(1)`) est le parent de l'environnement.

2. **Pi-binder** : couple (nom, type) dans un Pi.
   Le corps (`child(1)`) est vide (usage structurel).
   Exemple : `Pi(x : A). B => apply(sym("Pi"), [bind(x, A, _), B])`.

Les deux ont la meme forme physique. Le MOP ne les distingue pas :
`@store_child(bind, 0)` et `@store_child(bind, 1)` restent
coherents dans les deux cas.

C'est la **semantique** du contenu qui differe, pas la structure.

## Ce qui reste ouvert

- Faut-il un tag `.env_bind` dedie, distinct de `.bind`, pour
  separer les deux usages ? (Chantier a decider quand un cas
  concret le demandera. Aujourd'hui, un seul tag suffit.)

- L'evaluation d'un Pi-binder en mode HVN : le corps vide signifie
  "pas de valeur", ce qui est correct pour un type. A documenter
  dans `core/runtime/eval.hvn` quand il sera ecrit.

## Contraintes

1. Pas de type `Expr` separe.
2. Pas de type `Value` separe.
3. Pas de conversion entre representations.
4. Env n'est pas un `List`.
5. Les args d'apply ne sont pas un `List`.
6. Les `Span` ne sont jamais exposes a HVN.
7. Un `Id` designe toujours le meme terme (hash-consing).

