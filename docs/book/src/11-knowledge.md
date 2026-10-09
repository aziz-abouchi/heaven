# Chapitre 12 - Knowledge : raisonner sur le monde

Jusqu'ici, Heaven manipule principalement des programmes, des valeurs et
des preuves.

Mais un systeme distribue ou un outil de raisonnement doit aussi pouvoir
representer des connaissances provenant de sources differentes.

Heaven possede pour cela une couche **Knowledge**.

Elle est volontairement separee de `Expr`.

## Une connaissance n'est pas un programme

Le Core de Heaven utilise `Expr` comme IR compilable unique :

    source
      |
      v
    Expr
      |
      v
    MIR
      |
      v
    backend

Knowledge suit une autre voie :

    RDF / connaissances
          |
          v
    KnowledgeStore
          |
          v
       reasoner

Une connaissance ne devient pas automatiquement du code.

Si une connaissance doit finalement participer a un calcul, un lowering
explicite pourra la transformer en `Expr`.

Cette separation evite de transformer chaque domaine de raisonnement en
nouvel IR.

## Les ressources

Une ressource peut etre identifiee par une URI :

    http://example.org/A

ou etre un blank node.

Les valeurs textuelles ou numeriques sont representees comme des
literals.

Dans l'implementation actuelle, ces concepts sont representes par :

    Resource.uri
    Resource.blank
    Literal
    Node

dans `src/knowledge/resource.zig`.

## Les triples

La forme fondamentale de RDF est le triple :

    sujet  predicat  objet

Par exemple :

    A  subClassOf  B

Un triple est une donnee. Il ne modifie pas `Expr.Store`.

Le type correspondant est `Triple` dans
`src/knowledge/triple.zig`.

## Une assertion porte son histoire

Deux sources peuvent affirmer exactement le meme triple.

Heaven ne les fusionne pas automatiquement.

Une assertion contient notamment :

- le triple ;
- son `status` ;
- sa `provenance` ;
- une `confidence` optionnelle.

Les statuts actuels sont :

    asserted
    imported
    derived
    inferred
    certified

La provenance indique notamment la source et son identifiant.

Cela permet de distinguer :

    source A affirme X

de :

    le reasoner a infere X

ou :

    une preuve certifie X

Ces informations ne sont pas interchangeables.

## Le KnowledgeStore

Le `KnowledgeStore` conserve les assertions.

Il accepte plusieurs assertions portant sur le meme triple. Par exemple,
une assertion importee depuis une base externe et une assertion saisie
par l'utilisateur peuvent coexister.

Le Store ne deduplique donc pas silencieusement les connaissances.

C'est un choix important : perdre la provenance en dedupliquant serait
perdre une partie de la semantique de la connaissance.

## Premier reasoner : RDFS

Le premier POC implemente une seule regle RDFS :

    subClassOf est transitive.

Supposons :

    A subClassOf B
    B subClassOf C

Le reasoner peut produire :

    A subClassOf C

Cette nouvelle assertion est marquee :

    status = inferred

Le Store original n'est pas modifie.

La fermeture est donc conceptuellement :

    Store source
        |
        v
      Reasoner
        |
        v
    Assertions inferees

et non :

    Store source -> Store modifie

## Pas de reflexivite implicite

Si le Store contient :

    A subClassOf B

le reasoner ne produit pas automatiquement :

    A subClassOf A

La fermeture actuelle ne fabrique pas cette reflexivite.

Ce comportement est volontaire et teste.

## Pourquoi `KnowledgeId != Expr.Id` ?

Les deux systemes ont des identifiants numeriques, mais ils representent
des choses differentes.

    KnowledgeId
        -> ressource Knowledge

    Expr.Id
        -> noeud du Core Store

Ils restent donc incompatibles au niveau de l'API.

Cette contrainte empeche une conversion accidentelle entre connaissance
et programme.

## Et `sameAs` ?

Une relation `sameAs` signifie qu'une source affirme une equivalence.

Elle ne provoque pas une fusion destructive.

On conserve l'assertion originale avec sa provenance.

Une eventuelle operation de fusion sera une decision explicite distincte,
par exemple sous la forme conceptuelle :

    mergeAs(A, B)

Le reasoner pourra utiliser `sameAs` pour une requete sans effacer les
faits originaux.

## Charger du Turtle en pratique

Depuis octobre 2026, un parser Turtle (`src/knowledge/turtle_parser.zig`)
alimente un `TripleStore` global (`src/knowledge/triple_store.zig`).
Syntaxe supportee :

- `@prefix` : declaration de prefixes (`@prefix ex: <...> .`)
- `<iri>` et `prefix:local` : IRI completes ou prefixees
- `"litteral"`, `123`, `true`/`false` : litteraux types
- `_:label` : blank nodes nommes
- `;` : meme sujet, predicats multiples
- `,` : plusieurs objets pour un meme predicat
- `a` : raccourci pour `rdf:type`
- `( i1 i2 )` : collections RDF (sucrees en `rdf:first`/`rdf:rest`)

Commandes REPL :

    :load fichier.ttl                    -- charge un document Turtle
    :triple-count                        -- nombre de triplets charges
    :triples                             -- liste tous les triplets
    :triple-query <subject-iri>          -- tous les triplets d'un sujet

Exemple :

    @prefix foaf: <http://xmlns.com/foaf/0.1/> .
    @prefix ex: <http://example.org/> .

    ex:Alice a foaf:Person ;
        foaf:name "Alice Dupont" ;
        foaf:knows ex:Bob, ex:Charlie .

Charge avec `:load family.ttl` puis interroge avec
`:triple-query http://example.org/Alice`.

## Charger du Prolog en pratique

Un moteur Prolog (`src/runtime/prolog.zig`) est expose au REPL depuis
octobre 2026 :

    :p-fact parent(alice, bob)           -- ajoute un fait
    :p-rule grandparent(X, Z) :- parent(X, Y), parent(Y, Z)
                                         -- ajoute une regle Horn
    ?- grandparent(alice, charlie)       -- requete
    ?- parent(alice, X)                  -- requete avec variable

Les variables commencent par une majuscule. Le backtracking retourne
toutes les solutions (une par ligne).

Limites actuelles : pas de recursion, pas de chargement de fichiers
`.pl`. Le backend reste Matrix (D9 futur).

## Ce qui n'est pas encore la

Le POC ne fournit pas encore :

- de SPARQL ;
- OWL ;
- `rdfs:domain` ;
- `rdfs:range` ;
- `rdfs:subPropertyOf`.

Ces extensions seront ajoutees seulement apres specification de leur
contrat.

## Vers le langage Heaven

La couche Knowledge est actuellement une bibliotheque/runtime en Zig.

Il ne faut donc pas inventer une syntaxe Heaven pour RDF avant que cette
syntaxe soit implementee.

Le principe futur reste :

    connaissance
         |
         | lowering explicite
         v
        Expr
         |
         v
       calcul

Ainsi Knowledge enrichit Heaven sans introduire un deuxieme langage
interne de compilation.

## A retenir

- Knowledge represente des connaissances, pas des programmes.
- `Expr` reste l'IR compilable unique.
- `KnowledgeId` est distinct de `Expr.Id`.
- Les assertions conservent provenance, statut et confiance.
- Les reasoners produisent des resultats separes du Store.
- Le premier reasoner implemente `subClassOf` transitif.
- Une connaissance ne devient du code que par lowering explicite.
