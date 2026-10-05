# ContentId -- identite adressee par contenu

> Statut : design. Aucune decision finale sur la canonicalisation,
> le hash ou le format. Ce document pose les questions a trancher
> et fixe l'intention architecturale.
>
> Reference : docs/ARCHITECTURAL_DISCIPLINE.md (Fondation),
> docs/spec/_inspirations.md (Unison -- content addressing).

## Intention

Un terme Heaven doit avoir une identite stable, independante de
son nom, de sa position dans un fichier, ou du Store qui l'heberge.

    ContentId(terme) = hash(canonical form du terme)

Cette identite doit permettre :

- le cache (compilation, preuves, tests)
- la replication entre noeuds (Bobiverse)
- la verification d'integrite
- la distribution sans reconstruire tout le contexte

## Ce qui est deja en place

Le Store est hash-conse. Deux termes structurellement egaux
partagent le meme `Id` **dans un Store donne**. C'est necessaire
mais insuffisant : un `Id` n'a pas de sens en dehors de son Store,
et rien ne garantit qu'il soit stable entre deux executions.

Le hash-consing est une optimisation locale. ContentId est une
identite globale. Ce ne sont pas la meme chose.

## Le point dur : canonical form

ContentId = hash(canonical form). Sans forme canonique, pas de
ContentId stable.

Trois strategies, chacune avec un cout :

**A -- Hash de la forme normalisee.**
On normalise a fond (beta, iota, eta, delta si possible), puis
on hashe. Sur, mais couteux a chaque calcul.

**B -- Hash de la forme de surface.**
Moins cher, mais deux termes semantiquement egaux ont des hashs
differents. Le cache tombe. Une preuve sur `x + 0` ne matche pas
la meme preuve ecrite `0 + x`.

**C -- Hash modulo un fragment decidable de l'egalite.**
Compromis. On normalise ce qui est decidable (beta sur les
fragments simples, eta, iota), on laisse le reste. Complexe.

**Choix : A.** Coherent avec le noyau CIC (normalisation forte).
Le cout est acceptable dans un systeme ou les termes sont deja
hash-conses.

Question ouverte : *quel fragment exact de l'egalite est inclus
dans la normalisation ?* A trancher avant le premier prototype.

## Version du noyau dans le hash

Un fix de bug dans le noyau CIC peut invalider des preuves qui
exploitaient un comportement en fait incorrect. Deux politiques :

**A -- Versionner.** Le hash inclut la version du noyau. Chaque
changement vide le cache. Sur mais brutal.

**B -- Ne pas versionner.** Le hash est purement structurel. Une
preuve en cache peut etre fausse apres un changement de noyau.

**C -- Separer noyau stable / extensions.** Le noyau (CIC pur) est
gele ; seules les extensions evoluent. Seul le premier entre dans
le hash. Si le noyau change (rare), on invalide explicitement.

**Choix : C.** Le noyau CIC est concu pour etre stable. Les
extensions (elaboration, tactics, backends) peuvent bouger sans
invalider les preuves elles-memes.

A valider : *quand est-ce qu'on declare le noyau "gele" ?*
Aujourd'hui il est experimental. Le gel est un jalon, pas un etat.

## Scope du ContentId

Un ContentId peut s'appliquer a plusieurs niveaux :

| Niveau | Contenu |
|---|---|
| Terme | un Id du Store (canonical form) |
| Definition | nom + terme + dependances |
| Module | liste de definitions + imports |
| Preuve | statement + proof + dependances + version noyau |
| EGraph artifact | resultat d'une saturation |
| Artifact compile | binaire QBE/WASM issu d'un terme |

**Choix : chaque niveau a son propre ContentId.** Un ContentId de
terme n'a pas la meme forme qu'un ContentId de module (qui inclut
les ContentIds de ses dependances). Ils se composent.

## Spine : ContentId, ProtocolId, ProcessId

Pour la distribution, trois identites distinctes mais liees :

    ContentId   identite d'un artefact (terme, preuve, module)
    ProtocolId  identite d'un protocole MPST (type global)
    ProcessId   identite d'un Bob ou acteur en execution

Relations :

- Un **ProtocolId** porte un **ContentId** de sa forme canonique.
  Deux protocoles equivalents ont le meme ProtocolId.
- Un **ProcessId** est **lie** a un ProtocolId (projection locale)
  et a un ContentId de code (le corps du Bob).
- Un ProcessId n'est **pas** un ContentId : c'est une instance,
  elle, ephemeres. Elle n'a pas besoin d'etre stable entre deux
  executions.

Question ouverte : *un Bob peut-il migrer entre vaisseaux tout en
gardant son ProcessId ?* A trancher au moment de la distribution.

## Ce qui n'est pas dans ce document

- **Algorithme de hash.** SHA-256, BLAKE3, autre. A decider au
  moment de l'implementation. Le choix n'affecte pas l'architecture.
- **Format de serialisation.** ContentId n'impose pas de format ;
  il impose qu'un terme puisse etre serialise de facon canonique.
  Voir `docs/spec/_serialize.md`.
- **Protocole de distribution.** Voir la section Fondation ->
  Distribution dans `ARCHITECTURAL_DISCIPLINE.md`.
- **Cache.** Decoule de ContentId, n'en est pas un prerequis.

## Prerequis avant implementation

1. Canonical form decidee (choix A ci-dessus, a preciser).
2. Fragment d'egalite inclus dans la normalisation, documente.
3. Politique de version du noyau actee (choix C ci-dessus,
   avec un jalon "noyau gele").
4. Serialisation canonique disponible (`_serialize.md`, existe
   partiellement dans `src/core/serialize.zig`).

## Trigger de reouverture (depuis _inspirations.md)

L'entree Unison du coffre liste : "Forme canonique du Core Expr
decidee (spec + prototype)". Ce document est la spec. Il reste
le prototype.

## Etat

| Element | Etat |
|---|---|
| Intention | figee (ce document) |
| Canonical form | choix A, fragment a preciser |
| Version noyau | choix C, jalon de gel a definir |
| Scope | multi-niveaux, a documenter par niveau |
| Spine ContentId/ProtocolId/ProcessId | esquisse |
| Hash algorithme | non decide |
| Serialisation | partielle (`serialize.zig`) |
| Prototype | non commence |

