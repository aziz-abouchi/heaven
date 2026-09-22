# Heaven Core IR

## Statut

Ce document définit le contrat structurel du Core IR de Heaven.

Le Core IR constitue la représentation minimale sur laquelle peuvent
opérer les mécanismes de :

- réécriture ;
- E-graph ;
- égalité-saturation ;
- recherche logique ;
- extraction ;
- reconstruction de preuves ;
- optimisation ;
- génération de code.

Le Core IR n'est pas une représentation de surface du langage.

Les constructions de haut niveau doivent être abaissées vers ce noyau
avant d'être traitées par les mécanismes qui exigent une représentation
canonique.

Statut du document :

- Core à six primitives : implémenté
- Lowering : implémenté, en durcissement
- Identité structurelle : en durcissement
- Hash structurel : en durcissement
- EGraph : expérimental
- Congruence closure : à implémenter
- Reconstruction de preuves : à implémenter
- Trusted kernel : à renforcer

---

## 1. Les six primitives

Le Core de Heaven contient exactement six primitives :

    lit
    sym
    apply
    bind
    lambda
    relation

Dans `expr.zig`, elles sont représentées par :

    pub const Primitive = enum(u8) {
        lit,
        sym,
        apply,
        bind,
        lambda,
        relation,
    };

Le type `Tag` contient également des constructions frontend et
legacy. Ces tags ne font pas partie du Core.

    pub fn isPrimitive(self: Tag) bool {
        return switch (self) {
            .lit, .sym, .apply, .bind, .lambda, .relation => true,
            else => false,
        };
    }

Une expression Core est donc une expression dont le tag appartient
strictement à cet ensemble.

Aucune extension frontend ne doit être considérée comme une expression
Core.

---

## 2. Représentation physique

Un nœud Core est représenté par :

    pub const Node = struct {
        tag: Tag,
        payload: u32,
        aux: u32,
        span_a: Span,
        span_b: Span,
    };

Les identifiants de nœuds sont des `u32`.

    pub const Id = u32;

La valeur `NULL` est réservée comme identifiant invalide :

    pub const NULL: Id = std.math.maxInt(Id);

Les spans référencent le pool global de nœuds enfants :

    pub const Span = struct {
        start: u32,
        len: u16,
    };

Le `Node` ne contient donc pas directement ses enfants.

---

## 3. Encodage des primitives

### 3.1 lit

`lit` représente une valeur littérale.

Le champ `aux` référence une entrée dans `Store.lits`.

    lit.aux -> Store.lits[index]

Le champ `payload` n'a pas de signification sémantique pour `lit`.

L'identité d'un littéral est déterminée par sa valeur et non par son
identifiant de nœud.

---

### 3.2 sym

`sym` représente un symbole interné.

    sym.payload -> StringInterner.list[index]

Deux symboles ayant le même identifiant d'interneur représentent le même
symbole.

L'identité structurelle d'un `sym` ne dépend pas :

- de l'identifiant du nœud ;
- de son emplacement dans `Store.nodes` ;
- de ses spans ;
- de sa position source.

---

### 3.3 apply

`apply` représente l'application d'une expression à une liste
d'arguments.

Dans la représentation actuelle de Heaven :

    apply.payload -> fonction

et `span_a` contient également la fonction en première position :

    span_a[0] = payload

puis :

    span_a[1..] = arguments

Cette duplication est actuellement conservée pour compatibilité avec
le code existant.

Elle constitue une invariant structurel :

    apply.span_a[0] == apply.payload

Toute expression Core violant cette invariant doit être considérée
comme malformée.

---

### 3.4 bind

`bind` représente actuellement une liaison nommée.

> **Note** : `Store.bind()` initialise `span_a[1]` à `unit` (corps
> par défaut). `Store.bindSymWithBody()` place explicitement le corps
> à `span_a[1]`. Les deux constructions produisent un nœud `.bind`
> valide ; la seule différence est la valeur du corps.

Dans la représentation actuellement utilisée par `Store.bind()` :

    bind.payload -> symbole du nom

    bind.span_a[0] -> valeur liée

    bind.span_a[1] -> corps

La construction historique actuelle initialise le corps avec `unit`.

Le champ `aux` n'est pas la source sémantique de la valeur dans cette
représentation.

Il ne faut donc pas interpréter `bind.aux` comme le nœud enfant principal
tant que cette représentation n'a pas été explicitement migrée.

Une future révision du Core pourra normaliser `bind` vers une
représentation plus compacte, mais cette migration doit être atomique :

    représentation
    + constructeurs
    + lowering
    + evaluator
    + extraction
    + tests
    + sérialisation

ne doivent pas être modifiés indépendamment.

---

### 3.5 lambda

`lambda` représente une abstraction.

    lambda.payload -> symbole du paramètre

    lambda.span_a[0] -> corps

Pour une lambda avec paramètre :

    lambda(x, body)

la structure est :

    tag      = lambda
    payload  = symbol("x")
    span_a   = [body]

La construction actuelle de lambda sans paramètre utilise `payload = 0`
comme valeur spéciale.

Cette représentation doit être considérée comme un cas legacy tant
qu'un véritable encodage du paramètre absent n'a pas été défini.

En particulier, `payload = 0` ne doit pas être validé comme un symbole
réel sans vérifier l'intention du constructeur.

---

### 3.6 relation

`relation` représente une relation entre deux séquences d'expressions.

    relation.payload -> symbole de tête

    relation.span_a -> côté gauche

    relation.span_b -> côté droit

L'identité d'une relation doit donc prendre en compte les quatre
composants :

    tag
    payload
    span_a
    span_b

Ignorer `span_b` constitue une erreur sémantique.

Ignorer `payload` constitue également une erreur sémantique.

---

## 4. Identité structurelle

L'identité structurelle est définie par la fonction :

    structuralEql(store, a, b)

Elle doit comparer la structure sémantique complète des deux expressions.

Elle ne doit pas comparer :

- l'Id du nœud ;
- les offsets physiques dans `pool` ;
- les spans en tant qu'adresses ou positions ;
- la position source.

Elle doit comparer le contenu référencé par ces structures.

---

## 5. Définition de l'égalité structurelle

### lit

Deux `lit` sont égaux si leurs valeurs sont égales :

    Lit.eql(a, b)

### sym

Deux `sym` sont égaux si leur identité d'interneur est identique.

### apply

Deux `apply` sont égaux si :

    payload(a) == payload(b)

et :

    span_a(a) == span_a(b)

récursivement.

### bind

Deux `bind` sont égaux si :

    payload(a) == payload(b)

et que leurs enfants sont structurellement égaux.

### lambda

Deux `lambda` sont égaux si :

    payload(a) == payload(b)

et que leurs corps sont structurellement égaux.

### relation

Deux `relation` sont égales si :

    payload(a) == payload(b)

    span_a(a) == span_a(b)

    span_b(a) == span_b(b)

récursivement.

---

## 6. Hash structurel

`nodeHash()` est un mécanisme de préfiltrage.

Il ne constitue jamais une preuve d'égalité.

La règle fondamentale est :

    structuralEql(a, b) => nodeHash(a) == nodeHash(b)

La réciproque n'est pas requise :

    nodeHash(a) == nodeHash(b)

n'implique pas :

    structuralEql(a, b)

Une collision de hash doit donc être possible sans provoquer une fusion
incorrecte dans l'EGraph.

Le hash doit couvrir toutes les données utilisées par
`structuralEql`.

En particulier :

    bind.payload
    bind.children
    lambda.payload
    lambda.body
    relation.payload
    relation.span_a
    relation.span_b
    apply.payload
    apply.span_a

doivent participer à l'identité.

---

## 7. Hash-consing

Le hash-consing du Core utilise le hash comme filtre de candidats.

Le schéma correct est :

    hash
      |
      v
    candidats
      |
      v
    structuralEql
      |
      +---- égalité ----> même classe
      |
      +---- différence -> nouveau candidat

Le hash ne doit jamais être utilisé comme preuve :

    hash == hash => même expression

est interdit.

La structure de données du hash-consing peut donc être :

    AutoHashMap(u64, ArrayListUnmanaged(ClassId))

plutôt que :

    AutoHashMap(u64, ClassId)

lorsqu'une collision ou plusieurs expressions distinctes produisent le
même hash.

---

## 8. Indépendance des identifiants

Les identifiants de nœuds sont des références physiques.

Ils ne font pas partie de l'identité sémantique d'une expression.

Ainsi, si deux stores contiennent :

    sym("x")

à des positions différentes, leurs expressions doivent être
structurellement égales si les symboles internés représentent le même
nom.

De même :

    apply(f, [x])

doit être structurellement égal à une construction équivalente située
à un autre emplacement du store.

---

## 9. Indépendance des spans physiques

Un `Span` est une référence physique dans `Store.pool`.

Par conséquent :

    Span.start

n'est pas une donnée sémantique.

Seuls les éléments référencés par le span sont sémantiques.

Ainsi deux structures :

    span_a = { start = 10, len = 2 }

et :

    span_a = { start = 500, len = 2 }

peuvent être structurellement égales si les deux spans contiennent les
mêmes expressions.

---

## 10. Core closure

Une expression Core doit contenir uniquement des expressions Core.

Pour tout enfant référencé par :

    payload
    aux
    span_a
    span_b

le nœud référencé doit lui-même satisfaire :

    tag.isPrimitive() == true

Une extension frontend ne doit jamais pénétrer dans l'EGraph.

Le passage frontend -> Core est réalisé par `Store.lower()`.

---

## 11. Lowering

Le lowering transforme les extensions frontend vers les six primitives.

La propriété fondamentale recherchée est :

    lower(lower(x)) == lower(x)

au niveau structurel.

Une expression déjà Core ne doit pas être transformée :

    lower(core) == core

au sens de l'identité structurelle et de la sémantique.

Le lowering peut créer de nouveaux nœuds physiques dans le store.
Cela ne constitue pas une violation de l'identité Core.

---

## 12. Frontend versus Core

Les tags frontend sont des constructions pratiques.

Exemples :

    int
    float
    string
    let
    fun
    eq
    add
    sub
    mul
    div
    aggregate
    vector

Ils ne doivent pas être consommés directement par les mécanismes
qui exigent le Core.

Le pipeline conceptuel est :

    Surface
        |
        v
    Frontend IR
        |
        v
    lowering
        |
        v
    Core IR
        |
        +---- EGraph
        |
        +---- Logic
        |
        +---- Analysis
        |
        +---- Extraction
        |
        v
    Optimized Core

---

## 13. EGraph et frontière de confiance

L'EGraph représente une relation d'équivalence calculée.

Le fait que :

    egraph.areEqual(a, b) == true

signifie actuellement :

    a et b appartiennent à la même e-class

Cela ne signifie pas encore :

    une preuve formelle vérifiée existe.

La chaîne de confiance cible est :

    EGraph
       |
       v
    explanation
       |
       v
    ProofTerm
       |
       v
    trusted kernel
       |
       v
    verified equality

Tant que cette chaîne n'est pas complète, une égalité EGraph doit être
qualifiée de relation calculée et non de théorème certifié.

---

## 14. Rebuild

L'opération `merge()` modifie l'équivalence des classes.

Elle doit à terme être suivie d'une opération de rebuild réalisant la
fermeture de congruence.

Exemple :

    f(a)

    f(b)

Si :

    a == b

alors la fermeture de congruence doit établir :

    f(a) == f(b)

Le simple Union-Find ne suffit pas à réaliser cette propriété.

Le rebuild est donc une étape distincte du hash-consing initial.

---

## 15. DAG du Core et graphe d'équivalence

Le `Store` contient des expressions.

Le Core doit rester acyclique.

L'EGraph est au contraire un graphe d'équivalence et peut représenter
des cycles logiques issus des fusions.

Il ne faut donc pas confondre :

    Store DAG

et :

    EGraph equivalence graph

Les algorithmes récursifs opérant directement sur le Store doivent
pouvoir supposer l'absence de cycles si cette propriété est garantie
par les constructeurs.

Les algorithmes opérant sur l'EGraph doivent en revanche utiliser les
e-classes et le Union-Find plutôt que supposer que le graphe est un DAG.

---

## 16. Invariants P0.1

P0.1 est considéré terminé lorsque les invariants suivants sont
respectés.

### I1. Six primitives

Le Core contient exactement :

    lit
    sym
    apply
    bind
    lambda
    relation

### I2. Core validation

Toute expression consommée par l'EGraph est Core.

### I3. Lowering idempotent

    lower(lower(x)) == lower(x)

### I4. Core stable

    lower(core) == core

### I5. Hash soundness

    structuralEql(a, b) => hash(a) == hash(b)

### I6. Collision safety

    hash(a) == hash(b)

ne suffit jamais à fusionner deux expressions.

### I7. Node-id independence

L'Id physique d'un nœud ne participe pas à son identité structurelle.

### I8. Span independence

Les offsets physiques des spans ne participent pas à l'identité
structurelle.

### I9. Relation completeness

`payload`, `span_a` et `span_b` participent tous à l'identité d'une
relation.

### I10. Lambda completeness

Le paramètre et le corps participent à l'identité d'une lambda.

### I11. Apply completeness

La fonction et les arguments participent à l'identité d'une application.

### I12. Bind completeness

Le nom et les composants sémantiques du bind participent à son identité.

### I13. EGraph trust boundary

Une égalité EGraph n'est pas présentée comme une preuve vérifiée tant
qu'elle n'a pas été reconstruite puis vérifiée par le kernel.

---

## 17. Ce que P0.1 ne fait pas

P0.1 ne doit pas implémenter :

    rebuild
    congruence closure complète
    e-matching complet
    saturation engine
    explanation DAG
    ProofTerm depuis l'EGraph
    trusted kernel complet
    Prolog
    miniKanren
    High-Level Semantic IR
    comprehension IR
    Core -> High-Level lifting
    Grand Pi

Ces éléments appartiennent aux étapes suivantes.

---

## 18. Architecture cible

L'architecture cible de Heaven est :

    High-Level Semantic IR
             |
             v
          lowering
             |
             v
          Core IR
             |
       +-----+-----+----------------+
       |           |                |
       v           v                v
     EGraph      Logic           Analysis
       |           |                |
       +-----------+----------------+
                   |
                   v
               Extraction
                   |
                   v
             Proof reconstruction
                   |
                   v
             Trusted kernel
                   |
                   v
              Optimized Core
                   |
                   v
             High-Level IR
                   |
                   v
                Codegen

Le Core reste donc le point de convergence entre :

    programmation
    logique
    optimisation
    synthèse
    preuves

---

## 19. Principe directeur

Le Core n'est pas simplement une AST plus petite.

Il constitue le contrat commun permettant à plusieurs moteurs
indépendants de manipuler la même représentation.

La règle fondamentale est :

    aucune optimisation ne doit inventer sa propre notion d'identité
    structurelle.

Toutes les couches qui manipulent le Core doivent converger vers :

    structural equality
    structural hashing
    Core validation
    explicit equivalence
    explicit proof

Ce contrat est la fondation de l'architecture Heaven.
