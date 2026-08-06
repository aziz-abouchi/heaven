# Heaven Architecture 2026

## Vision

Heaven est un système de programmation, raisonnement, transformation et exécution distribué.

L'inventaire réalisé en 2026 montre qu'Heaven possède déjà un noyau relativement cohérent autour d'un IR unique (`Expr`) sur lequel viennent se greffer plusieurs couches :

* langage
* réécriture
* preuve
* élaboration
* génération de code
* exécution
* réseau
* expérimentation

---

# Architecture globale

```text
                Heaven

                   │
                   ▼

              Expr (792)

                   │

     ┌─────────────┼──────────────┐

     ▼             ▼              ▼

  Types        Pattern         Canon

     │             │             │

     └──────────► EGraph ◄───────┘

                     │

                     ▼

                Transform

                     │

             ┌───────┴───────┐

             ▼               ▼

          Proof            Elab

             │               │

             └──────► HeavenExpr

                          │

      ┌───────────────────┼──────────────────┐

      ▼                   ▼                  ▼

   Commands           Runtime             Forge

      │                   │                  │

      ▼                   ▼                  ▼

     LSP              Network         Universal

                          │

                          ▼

                        SCUT

                          │

                          ▼

                        Swarm
```

---

# Noyau du langage

Modules principaux :

| module          | LOC  |
| --------------- | ---- |
| expr.zig        | 792  |
| egraph.zig      | 392  |
| transform.zig   | 518  |
| proof.zig       | 415  |
| elab.zig        | 624  |
| heaven_expr.zig | 3473 |

## expr

IR universel d'Heaven.

Responsabilités :

* représentation des expressions
* Store
* Id
* substitution
* hashing
* comparaison structurelle
* pretty printing

Centralité :

36 imports

Expr constitue le cœur du système.

---

## pattern

Matching structurel.

Support des règles.

---

## canon

Canonicalisation.

Normalisation.

Support d'égalité.

---

## egraph

Réécriture équationnelle.

Probablement :

* EClass
* ENode
* UnionFind
* rebuild
* extraction

Imports :

9

Faible couplage.

---

## transform

Système de règles.

Application des transformations.

Réécriture.

Extraction.

---

## proof

Infrastructure logique.

Faible dépendance.

6 imports.

Composant optionnel.

---

## elab

Élaboration.

Transformation :

Tree-sitter

↓

AST

↓

Expr

↓

IR typé

↓

preuves

↓

HeavenExpr

---

# HeavenExpr

3473 lignes.

HeavenExpr n'est pas le noyau.

Seulement 5 imports.

Il s'agit principalement d'une façade.

Responsabilités supposées :

* pipeline
* compilation
* orchestration
* dispatch backend
* sessions
* runtime
* shell
* intégration

Découpage futur proposé :

```text
core/heaven_expr/

api.zig

pipeline.zig

session.zig

compile.zig

transform.zig

prove.zig

runtime.zig

backends.zig
```

---

# Backend

Modules actifs :

* expr_c
* expr_js
* expr_latex
* mir
* x86_64

État estimé :

| backend | maturité |
| ------- | -------- |
| C       | 70 %     |
| JS      | 60 %     |
| Latex   | 90 %     |
| MIR     | 40 %     |
| x86     | 25 %     |

---

# Frontend

Tree-sitter est utilisé dans :

* parse
* repl
* compile
* check
* doc
* fmt
* transpile
* lsp
* elab
* universal
* heaven_md

Il n'est pas utilisé dans :

* expr
* egraph
* proof
* transform

Le moteur logique est indépendant du parser.

---

# Runtime

Modules :

| module         | LOC |
| -------------- | --- |
| runtime/heaven | 275 |
| autofab        | 423 |
| task           | 38  |
| loop           | 67  |

runtime/heaven semble être principalement un bootstrap.

task constitue un composant minimal.

loop est une boucle d'événements légère.

---

# Réseau

Modules :

| module        | LOC |
| ------------- | --- |
| scut/network  | 609 |
| swarm/runtime | 188 |

SCUT semble devenir une couche réseau propre.

Responsabilités probables :

* identité
* transport
* routage
* protocole
* topologie

---

# Forge

Modules :

| module     | LOC |
| ---------- | --- |
| universal  | 680 |
| transpiler | 172 |

Universal est actuellement relativement massif.

Probable candidat à un découpage.

---

# Dépendances globales

Nombre d'importations :

Expr :

36

Platform :

53

EGraph :

9

Proof :

6

Platform apparaît aujourd'hui comme un module fortement centralisateur.

Découpage futur envisagé :

```text
platform/

mem.zig

io.zig

fs.zig

thread.zig

net.zig

crypto.zig

parser.zig

os.zig
```

---

# Classification des modules

## cœur stable

expr

pattern

canon

egraph

transform

proof

types

elab

---

## façade

heaven_expr

---

## compilation

codegen

lowering

mir

x86

---

## infrastructure

platform

runtime

commands

lsp

---

## réseau

scut

network

swarm

---

## recherche

forge

autofab

semantic

react

llm

knowledge

---

# Estimation de maturité

| domaine     | état |
| ----------- | ---- |
| AST         | 90 % |
| canon       | 80 % |
| egraph      | 75 % |
| transform   | 75 % |
| proof       | 65 % |
| elab        | 60 % |
| CLI         | 80 % |
| Tree-sitter | 90 % |
| backend C   | 70 % |
| backend JS  | 60 % |
| MIR         | 40 % |
| x86         | 25 % |
| réseau      | 35 % |
| swarm       | 20 % |
| forge       | 30 % |
| IA          | 15 % |

---

# Conclusion

Heaven n'apparaît plus comme une collection de prototypes.

L'inventaire révèle un noyau relativement cohérent autour d'un IR partagé (`Expr`) auquel se sont progressivement ajoutés :

* système de preuve
* moteur de réécriture
* élaboration
* compilation
* réseau
* recherche expérimentale

Le principal enjeu pour 2026 n'est probablement plus la conception des abstractions fondamentales, mais leur consolidation, leur découpage modulaire et la séparation explicite entre :

* noyau stable
* infrastructure
* expérimentation
* recherche

```
```

