# Chapitre 11 — Modules et imports

> *« Un programme qui tient dans un fichier est un programme qui
> ne grandit pas. »*

Depuis septembre 2026, Heaven a un système de modules minimal mais
utilisable.

## Ouvrir un namespace

    module M

Toutes les définitions qui suivent sont accessibles **aussi** sous
`M.x` en plus de `x` (comportement par défaut, dit « non-strict ») :

    heaven> module M
    ✓ module M ouvert
    heaven> foo x = x + 1
    ✓ clause enregistrée pour 'foo'
    heaven> M.foo 5
    6
    heaven> foo 5
    6

## Importer un fichier

    import "core/stream.hvn" as Stream

Charge le fichier, évalue chaque ligne, et alias sous `Stream.x`.
Le nom est déduit du basename si `as` est absent.

On peut aussi écrire `import Nom` (sans guillemets), qui cherche
dans `core/std/<nom>.hvn` puis `core/<nom>.hvn` :

    import Stream       -- cherche core/std/stream.hvn
                        -- puis core/stream.hvn

## `HEAVEN_PATH`

Si un import n'est pas trouvé dans le cwd, Heaven cherche dans les
dossiers listés par la variable d'environnement `HEAVEN_PATH`
(séparateur `:`) :

    export HEAVEN_PATH=/usr/local/heaven:/home/user/libs

## Cycles et idempotence

`import` détecte les cycles (A importe B importe A → erreur claire).
Un même fichier importé deux fois est **skippé** avec un message
« déjà importé ».

## Export contrôlé

Par défaut tout est exporté. Pour restreindre :

    -- util.hvn
    secret x = x + 1
    public x = x * 2
    export public

    heaven> import "util.hvn" as U
    heaven> U.public 5
    10
    heaven> U.secret 5
    ✗ UnknownSymbol (non exporté)

Les noms non-exportés restent accessibles **sans préfixe** (enforcement
faible). Seul `U.secret` est refusé.

## Mode strict (opt-in)

Pour n'exposer **que** les noms préfixés :

    heaven> strict on
    ✓ strict mode on

À partir de là, un fichier importé **doit** passer par ses alias.
Les noms nus sont refusés :

    heaven> import "util.hvn" as U
    heaven> U.public 5
    10
    heaven> public 5
    ✗ 'public' inaccessible (défini dans un module en mode strict;
       utilisez <module>.public)

Le mode non-strict est le défaut ; `strict off` le désactive.

## Limites connues

- Namespace plat : `A.B.foo` est une clé string, pas de hiérarchie
  sémantique.
- Pas de rechargement dynamique ni de sélection d'import
  (`{ foo, bar }`).
- `fn`/`let` ne sont pas encore aliasés sous `M.x` (seul les
  `theorem` le sont depuis la v0).
