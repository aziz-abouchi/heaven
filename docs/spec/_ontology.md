# Knowledge et ontologie Heaven - perimetre, frontiere, decisions

> Statut : **decide**.
>
> Depuis le 2026-10-01, la connaissance RDF/RDFS est une couche
> distincte du Core `Expr`. Elle n'est pas un second IR.
>
> `src/core/algo_catalog.zig` et `src/core/ontology.zig` sont
> conserves comme composants historiques/specifiques tant qu'une
> migration explicite n'est pas decidee.

## 1. Frontiere architecturale

Heaven possede un IR compilable unique :

    Source / Domain
          |
          | lowering explicite
          v
         Expr
          |
          v
         MIR
          |
          v
       backend

La couche Knowledge ne remplace pas `Expr` :

    RDF / RDFS / connaissances
              |
              v
        KnowledgeStore
              |
              v
          Reasoner
              |
              | lowering explicite, si necessaire
              v
             Expr

Une structure est consideree comme un IR concurrent seulement si elle
possede sa propre semantique generale d'execution, son propre pipeline
de compilation/backend et pretend representer arbitrairement les
programmes Heaven.

Le KnowledgeStore ne satisfait pas ce critere.

## 2. Identite

Les identifiants sont volontairement distincts :

    KnowledgeId != Expr.Id

`KnowledgeId` identifie une ressource ou un noeud de la couche
Knowledge. `Expr.Id` identifie un noeud du Core Store.

Le fait que les deux soient actuellement representes par des `u32`
ne cree aucune compatibilite implicite.

## 3. Ressources RDF

`src/knowledge/resource.zig` definit :

- `Resource.uri` pour les URI ;
- `Resource.blank` pour les blank nodes ;
- `Literal` pour les valeurs lexicales, datatype et langue ;
- `Node` comme union ressource/litteral.

L'egalite est structurelle dans chaque categorie.

## 4. Triples

`src/knowledge/triple.zig` definit :

    Triple {
        subject,
        predicate,
        object,
    }

Les triples ne sont pas des noeuds `Expr`.

## 5. Assertions et provenance

`src/knowledge/assertion.zig` separe trois notions :

### Provenance

Elle indique d'ou vient une assertion :

- source ;
- source_id optionnel ;
- timestamp ;
- revision optionnelle.

### Status

Le statut est ferme :

    asserted
    imported
    derived
    inferred
    certified

`trusted` n'est pas un statut.

### Confidence

La confiance est optionnelle :

    low
    medium
    high

Ces trois dimensions ne doivent pas etre fusionnees.

Une sortie d'un oracle statistique ou externe peut etre conservee comme
candidate avec sa provenance et son niveau de confiance, sans devenir
automatiquement `derived` ou `certified`.

## 6. KnowledgeStore

`src/knowledge/store.zig` conserve les assertions dans un espace
independant du Core Store.

Le Store :

- accepte plusieurs assertions portant le meme triple ;
- conserve leurs provenances distinctes ;
- ne deduplique pas automatiquement ;
- ne fusionne pas les ressources ;
- permet `add`, `get`, `count` et `find`.

Le choix de conserver plusieurs assertions est intentionnel :
l'origine d'une connaissance fait partie de son contexte.

## 7. Reasoners

Un reasoner est un moteur specialise de domaine.

Il peut posseder :

- ses propres structures temporaires ;
- ses propres algorithmes ;
- ses propres resultats de fermeture ou de resolution.

Il ne devient pas pour autant un nouvel IR de Heaven.

Le premier reasoner implemente dans `src/knowledge/rdfs.zig` est la
fermeture transitive de `rdfs:subClassOf`.

Exemple :

    A subClassOf B
    B subClassOf C

donne :

    A subClassOf C

La fermeture :

- ne modifie pas le Store source ;
- retourne les assertions inferees separement ;
- marque les nouvelles assertions `inferred` ;
- ne cree pas de reflexivite implicite ;
- ne remplace pas une assertion deja presente.

## 8. Perimetre RDFS du POC

Le POC couvre uniquement :

    rdfs:subClassOf

et sa transitivite.

Ne sont pas encore implementes :

- `rdf:type` ;
- `rdfs:domain` ;
- `rdfs:range` ;
- `rdfs:subPropertyOf` ;
- OWL ;
- SPARQL ;
- Turtle ;
- sameAs/mergeAs.

Ces extensions devront avoir leur propre contrat avant implementation.

## 9. sameAs et fusion

`sameAs` est une relation de connaissance, pas une commande de fusion.

Une assertion :

    sameAs(A, B)

reste conservee avec sa provenance.

Un eventuel `mergeAs(A, B)` sera une decision explicite produisant une
entite alignee. Le reasoner peut exploiter `sameAs` pour repondre a une
requete sans detruire les assertions originales.

## 10. Ancien systeme ontology

`src/core/algo_catalog.zig` est un catalogue d'algorithmes. Il ne doit
pas etre confondu avec RDF/RDFS.

`src/core/ontology.zig` est un ancien squelette semantique conserve
pour l'instant pour compatibilite et experimentation.

Il ne faut pas introduire une conversion implicite :

    ontology -> Knowledge
    Knowledge -> Expr

Une conversion future devra etre explicitement definie.

## 11. Prochaines etapes

Ordre prevu :

1. formaliser l'API `Closure` ;
2. ajouter un parseur Turtle minimal ;
3. ajouter des requetes simples sur le KnowledgeStore ;
4. etendre RDFS seulement apres validation du contrat ;
5. definir explicitement les lowerings `Knowledge -> Expr` lorsqu'un
   cas d'usage computationnel le justifiera.
