# Vision Heaven

> Statut : **document de vision**. Ce que Heaven cherche a devenir.
> Pas une roadmap (voir docs/ROADMAP.md), pas une liste de
> fonctionnalites (voir docs/STATUS.md). L'intention, la direction,
> ce qui guide les decisions structurelles.

Heaven vient du Bobiverse : un systeme qui se replique, se disperse
et s'ameliore sans presence humaine. Le nom n'est pas decoratif : la
replication est primitive, pas une fonctionnalite ajoutee.

## Ce que Heaven veut etre

Trois choses que les langages modernes separent, et que Heaven
essaie de faire tenir ensemble :

1. **La rigueur d'un assistant de preuve.** Tout ce qu'on affirme
   peut etre prouve. Pas dans un DSL externe (Coq, Lean, Isabelle),
   dans le meme fichier, avec la meme syntaxe.

2. **La legerete d'un REPL.** On tape, on voit, on ajuste. Pas de
   compilation lourde, pas de setup, pas de framework.

3. **La reactivite d'un systeme d'acteurs distribue.** Erlang, pas
   JVM. Communication par messages, processus legers, isolation
   par defaut.

Ces trois mondes existent separement. Les coudre ensemble est le
probleme. La synthese d'Heaven : un langage Idris-flavore pour les
types et les preuves, un modele Erlang-flavore pour la concurrence
et la distribution.

## Les trois invariants

Le systeme entier cherche a tendre vers trois directions. Elles ne
sont pas orthogonales, elles se contredisent parfois. Le systeme
choisit le compromis selon le contexte, mais ne peut jamais
abandonner completement l'une des trois.

**Verite.** Seules les mathematiques sont source de verite. Le noyau
est CIC (Calcul des Constructions Inductives), comme Coq et Lean. Ce
qui est prouve est prouve, point. Les autres domaines (physique,
musique, sociologie) sont des modelisations mathematiques : ils
heritent de la verite par reduction, ils ne la produisent pas.

**Esthetique.** Le systeme cherche la solution elegante, pas seulement
la solution qui marche. Un theoreme prouve en 3 lignes vaut mieux
qu'un prouve en 30. Une fonction de 5 lignes vaut mieux qu'une de
50. Ce n'est pas du gout personnel : c'est une propriete mesurable
de l'objet produit (longueur minimale, symetrie, absence de cas
particuliers). L'esthetique est une **heuristique de recherche**,
pas une source de verite. Elle guide, elle ne decide pas.

**Performance energetique et thermique.** Chaque operation a un cout :
temps CPU, memoire, energie, chaleur. Le systeme mesure ces couts et
les optimise. Pas au detriment de la verite (on ne prouve pas moins
vite), pas au detriment de l'esthetique (on ne fait pas laid pour
gagner 2%). L'objectif : un systeme qui tourne des mois sans saturer
une machine.

Ces trois invariants sont les **directions** du systeme. Ils ne
changent pas. Mais leur **ponderation** s'adapte au contexte : un
agent qui fait des preuves formelles privilegie la verite, un agent
qui fait du calcul numerique privilegie la performance, un agent qui
ecrit du code privilegie l'esthetique.

## Le noyau CIC

Le noyau de chaque nœud est **CIC** (Calcul des Constructions
Inductives) - la meme fondation que Coq et Lean. C'est un choix
delibere, pas un heritage.

**Ce que CIC garantit :**
- Normalisation forte : tout programme du noyau termine.
- Decidabilite du typage : verifier une preuve est mecanique.
- Coherence (relativement a des ordinaux) : pas de paradoxe.

**Ce que CIC interdit :**
- Mutation, effets, IO directs.
- Recursion non-fondée.
- Distribution, concurrence, replication dans le noyau lui-meme.

Ces choses vivent **au-dessus** du noyau. Chaque nœud (Bob) est un
noyau CIC pur. Ce qui circule entre les nœuds (messages, protocoles,
replication) est hors CIC et decrit par des types de session (MPST).

## L'essaim

Heaven n'est pas un systeme unique. C'est un **essaim de nœuds**
(Bobs), chacun un noyau CIC, qui collaborent, se replicent et
s'enrichissent mutuellement.

**Un nœud (Bob) est :**
- Un noyau CIC pur (mathématiques, preuves).
- Une arene memoire (allouee a sa naissance, liberee a sa mort).
- Une projection locale d'un protocole global (MPST).
- Un potentiel de replication (il peut en creer d'autres).

**Un nœud ne meurt pas de veillesse.** Sa vie correspond a un cycle
de traitement. Il peut etre termine, kille (crash), ou volontairement
arrete. A sa mort, son arene est liberee d'un bloc : pas de GC, pas
de scanning, la mort est l'operation memoire.

**Le vaisseau.** Sur chaque machine physique tourne un **vaisseau** :
une instance du runtime Heaven. Le vaisseau a une vie longue (jours,
semaines, annees), il heberge des Bobs courts et gere leur cycle de
vie, leur memoire, leur routage vers les autres vaisseaux. Un
vaisseau peut lancer des milliers de Bobs.

**Ce qui survit a un Bob :**
- Son **code** (il evolue, il se transmet a sa descendance).
- Son **etat lineaire QTT** (les ressources `1` : un checkpoint
  minimal pour reprendre son role).
- Sa **contribution a l'intelligence commune** (faits, theoremes,
  types globaux publies avant sa mort).

**Ce qui meurt avec lui :** son arene entiere (tout le `omega` local,
les intermediaires, les scratchs). Pas de partage memoire entre
Bobs : chaque message est une copie. Un Bob ne peut pas corrompre
un autre Bob.

**Replication.** Un Bob peut creer un autre Bob avec un sous-ensemble
de son code et de son etat. La divergence est legale : chaque Bob
peut evoluer differemment, tant qu'il reste dans la projection du
type global partage. C'est le modele Bobiverse : meme origine, memes
invariants, experiences specifiques.

**Intelligence commune.** Les Bobs publient leurs decouvertes
(theoremes, faits, nouveaux protocoles) dans un pool partage.
Chaque Bob voit le pool, peut l'enrichir, peut l'utiliser. Le pool
est un ensemble de **types globaux prouves** - pas une base de
donnees molle, un ensemble d'objets verifiables.

## Multi-syntaxes metier

Un physicien pense en physique. Un musicien pense en musique. Un
sociologue pense en relations. Heaven ne leur demande pas de penser
en langage de programmation.

La syntaxe par defaut (Idris + Erlang) est le **noyau commun**. Mais
chaque domaine peut avoir sa propre notation :

- **Mathematiques** : notations standard (`forall`, `exists`, `subset`,
  `integral`, formules LaTeX-like).
- **Physique** : unites, dimensions, equations de champ, tenseurs.
- **Musique** : portees, intervalles, transformations harmoniques.
- **Philosophie** : quantificateurs modaux, logiques non-classiques,
  arguments structures.
- **Sociologie / psychologie** : relations sociales, graphes
  d'influence, reseaux d'agents.

**Chaque syntaxe est une vue sur le meme noyau.** Un physicien qui
ecrit `F = m * a` produit un objet mathematique (une equation entre
grandeurs). Un musicien qui ecrit une fugue produit un objet
mathematique (une transformation sur un ensemble de notes). Un
sociologue qui ecrit un reseau produit un objet mathematique (un
graphe).

**Ce que Heaven ne fait pas :** elle ne verifie pas la physique
(accord au reel), elle ne verifie pas la musique (effet sur
l'ecoute). Elle verifie la **structure mathematique** que le
domaine utilise. C'est honnete : les sciences empiriques ne sont
pas des sources de verite, elles sont des modelisations.

**Une vue, plusieurs notations.** Le meme objet peut s'afficher
simultanement comme :
- `f(x) = x + 1` (notation math)
- `x |-> x + 1` (notation fonctionnelle)
- `Nat.succ` (notation Lean)
- `inc rax` (notation assembleur)

Tout cela est la meme chose, vue a travers des syntaxes differentes.

## Ontologies et sources externes

Heaven ne vit pas seul. Elle doit comprendre le monde exterieur et
echanger avec lui. Pour cela, elle a une couche **ontologie** :
concepts, relations, trust levels, provenance.

**Trois niveaux de trust :**
- `asserted` : vient d'une source externe non verifiee (DBpedia,
  fichier SMT-LIB, saisie utilisateur).
- `derived` : derive par une regle interne valide (subsomption,
  reecriture).
- `certified` : prouve par `proof_core.zig`.

**Sources externes, par difficulte :**
- **SMT-LIB** (priorite 1) : format standard, parseur facile,
  oracle disponible (Z3, cvc5). Emission : `Heaven -> .smt2`.
- **OWL / RDF / SPARQL** (plus tard) : ontologies description-logic,
  raisonneurs matures (HermiT, ELK).
- **Lean / Rocq** (oracles seulement) : pas d'import semantique
  (leurs bibliotheques ne sont pas exportables), mais on peut les
  interroger via LSP pour verifier des enonces.
- **MLCPD** : dataset (tooling), pas runtime.

**Le pont est un pont d'oracles, pas un pont semantique.** Heaven
ne "comprend" pas Lean, elle l'interroge. Elle ne "comprend" pas
DBpedia, elle l'interroge. Chaque source a un contrat precis et une
frontiere claire. Toute traduction est mesuree en termes de ce qui
est preserve.

## Ce qui est hors scope

Ces sujets appartiennent a la vision mais ne sont pas planifies.
Ils presupposent des briques qui n'existent pas encore ou relevent
de la recherche.

- **IPFS / IPLD** : presuppose serialisation + reseau + swarm
  (serialisation faite, le reste non).
- **Swarm distribue** (Fed-LBAP, MinCost, stragglers thermiques) :
  rien dans le code, recherche ouverte.
- **QTT avec budgets temps/energie** : la QTT actuelle est multiplicite
  (usage lineaire/efface), pas budget temporel.
- **Couplage thermique runtime** : lecture temperature = 30 min Linux,
  mais correler avec le scheduler est un projet.
- **Brain cognitif complet** : `inference/neural/synthesis.zig`
  experimental.
- **Auto-hebergement total** : jalon, pas tache. Le noyau peut rester
  en Zig indefiniment ; ce qui compte c'est que le maximum soit en
  HVN au-dessus.

**Ces sujets vivent dans ce document, pas dans la roadmap.** Les
ajouter a la roadmap les transformerait en taches, ce qu'ils ne sont
pas.

## Questions ouvertes

Ce qui n'est pas tranche, mais qui devra l'etre un jour :

1. **Le point fixe.** Le noyau CIC est non-modifiable. Mais les trois
   invariants (verite, esthetique, performance) peuvent-ils etre
   modifies par le systeme lui-meme ? Aujourd'hui : non. Plus tard ?

2. **Le seuil de divergence.** Un Bob peut s'eloigner de son origine.
   Jusqu'ou ? Un Bob qui rejette la verite CIC est-il encore un Bob ?
   Ou devient-il un "autre" (au sens du Bobiverse) ?

3. **La langue des protocoles.** Les MPST decrivent les protocoles
   entre Bobs. Mais qui negocie le **premier** protocole (celui qui
   permet de negocier les suivants) ?

4. **La montee en echelle.** Un vaisseau heberge des milliers de
   Bobs. Une flotte de vaisseaux heberge des millions. Ou sont les
   limites ? A quel moment la memoire partagee, la latence, le
   partitionnement deviennent des problemes structurels ?

5. **La mort.** Un Bob meurt, son arene disparait. Mais son code et
   son etat lineaire survivent. Qui decide ce qui survit ? Le Bob
   lui-meme, son parent, un protocole de replication ?

Ces questions n'ont pas de reponse aujourd'hui. Elles ne bloquent
rien. Elles guident les decisions structurantes quand elles se
posent.

## Comment lire ce document

- **docs/ROADMAP.md** : quoi faire ensuite (specs actionnables).
- **docs/STATUS.md** : ce qui marche aujourd'hui (source de verite).
- **docs/DECISIONS.md** : pourquoi on a tranche (D1-D9).
- **docs/VISION.md** : ce document, la direction long terme.

La vision n'est pas un plan. C'est un cap. Les decisions concretes
sont dans DECISIONS, la progression dans STATUS, le travail imminent
dans ROADMAP. VISION dit *pourquoi* on fait tout ca.
