# Sérialisation canonique du Core (D7)

Format binaire pour sauvegarder/recharger un `Store` entier.

## Format v1 (HVN1)

Little-endian, tailles fixes. Pas de varint, pas de compression.

### Header (14 octets)

    [4]  magic   "HVN1"
    [1]  version 0x01
    [1]  flags   0x00
    [4]  node_count     (u32 LE)
    [4]  pool_count     (u32 LE)
    [4]  lit_count      (u32 LE)
    [4]  interner_count (u32 LE)

### Section Interner

    Pour chaque chaîne (0..interner_count) :
      [4]     len     (u32 LE)
      [len]   bytes   (UTF-8, non terminé)

### Section Literals

    Pour chaque lit (0..lit_count) :
      [1]     tag     (0=int, 1=float, 2=str, 3=boolean)
      [8]     payload selon tag
              - int   : i64 LE
              - float : f64 LE (bitcast u64)
              - str   : u32 LE (Sym vers intern)
              - bool  : u8 (0|1), suivi de 7 octets de padding

### Section Nodes

    Pour chaque node (0..node_count) :
      [1]     tag          (u8, discriminant Tag)
      [4]     payload      (u32 LE)
      [4]     aux          (u32 LE)
      [4]     span_a.start (u32 LE)
      [2]     span_a.len   (u16 LE)
      [4]     span_b.start (u32 LE)
      [2]     span_b.len   (u16 LE)
    Total : 21 octets par node.

### Section Pool

    Pour chaque Id (0..pool_count) :
      [4]     id (u32 LE)

## Décisions non prises (v2)

- **Reachable subset** : sérialiser seulement les nodes atteignables depuis
  un Id racine. Nécessite renumérotation (ou offsets). À faire quand IPFS
  ou échange entre process sera concret.
- **Compression** : zstd ou lz4. Pas prioritaire.
- **Canonicalisation α** : si deux Stores ont des Syms différents mais
  les mêmes chaînes, les bytes diffèrent. Fixé en v2 par un tri des
  interners par ordre lexicographique.

## Erreurs

- `InvalidMagic` : les 4 premiers octets ne sont pas "HVN1"
- `UnsupportedVersion` : version != 1
- `Truncated` : lecture qui atteint EOF
- `Corrupted` : tag de Lit inconnu, ou longueur incohérente
- `InvalidTag` : discriminant de Tag invalide
- `OutOfMemory`

## API cible

    pub fn encode(store: *const Store, writer: anytype) Error!void
    pub fn decode(reader: anytype, allocator: Allocator) Error!Store

    pub fn encodeToBytes(store: *const Store, allocator: Allocator) Error![]u8
    pub fn decodeFromBytes(bytes: []const u8, allocator: Allocator) Error!Store

## Usage prévu

1. **Cache disque** : sauver un Store après parsing, recharger.
2. **Tests reproductibles** : figer un Store golden en bytes.
3. **Session save/restore** : REPL persistant.
4. **Prérequis réseau** : futur canal d'échange inter-process.

## Section Profils — format HVP1 (2026-09-30)

Extension de `_serialize.md` liée à `_metrics.md` et `_platform.md`.
Le format **HVP1** est le pendant de HVN1 pour un `Profile` unique.

### Décision : deux formats séparés

HVN1 sérialise un `Store` (nœuds, termes, interner).
HVP1 sérialise un `Profile` (métriques d'un scope).

Les deux formats sont **indépendants** :

- HVN1 peut exister sans profils (programme non profilé).
- HVP1 peut exister sans Store (mesure isolée d'un sous-système).
- Un fichier `.hvn` peut référencer des `ProfileId` via un index
  optionnel (voir §Index de profils, v2).
- Un fichier `.hvp` est self-contained.

Raison : coupler HVN1 et HVP1 forcerait tout consommateur de
profils à dépendre du modèle `Store`, ce qui est faux — un profil
peut concerner un test d'intégration sans Store associé.

### Format HVP1 (v1)

Little-endian, tailles fixes. Pas de varint, pas de compression.

#### Header (6 octets)

    [4]  magic   "HVP1"
    [1]  parent  (0 = null, 1 = present)
    [1]  scope   (0=local, 1=remote, 2=nested)

Si `parent == 1`, un `u64` LE suit immédiatement (le ProfileId du
parent).

#### Section Métriques (7 champs ordonnés)

Ordre fixe, un champ par métrique :

    1. wall_time
    2. cpu_time
    3. rss
    4. peak_rss
    5. energy
    6. instructions
    7. allocations

Chaque champ :

    [1]  tag       (0=unavailable, 1=measured, 2=estimated)
    [8]  valeur    (seulement si tag != 0)

Les champs 1,2,3,4,6,7 sont des `u64` LE.
Le champ 5 (energy) est un `f64` LE (bits réinterprétés).

Taille d'un profil rempli : 4 + 1 + 1 + 8 (parent) + 7*(1+8) = 77 octets.
Taille d'un profil vide : 4 + 1 + 1 = 6 octets.

#### L'id n'est PAS sérialisé

`serialize` n'écrit pas `ProfileId`. `deserialize` le recalcule via
`computeId()` en fin de lecture.

Propriété obtenue : deux profils identiques produisent les mêmes
bytes et le même `id`. La déduplication est automatique (content-
addressed).

### Erreurs de décodage

    DecodeError = BadMagic | BadTag | BadScope | UnexpectedEof | InvalidData

Les tags et scopes invalides sont des erreurs explicites, jamais des
panics. Conforme à `_platform.md` P5 (une erreur unique, pas de
fallback silencieux).

### API cible (implémentée)

    serialize(profile: Profile, writer: anytype) !void
    deserialize(reader: anytype) !Profile

Implémentées dans `src/platform/abi/profile_ser.zig`.
Tests : round-trip vide, round-trip rempli, précision préservée,
parent + scope préservés, déterminisme byte-level, 3 cas de
corruption.

### Index de profils dans HVN1 (v2, non implémenté)

Un fichier `.hvn` pourra porter un index optionnel de profils,
sous forme d'un chunk supplémentaire après la section Pool :

    [4]  profile_count (u32 LE)
    Pour chaque profil :
      [8]  profile_id  (u64 LE)
      [4]  length      (u32 LE)
      [length]  bytes  (HVP1 self-contained)

Le `profile_id` est redondant avec `computeId()` du contenu — il
sert d'index rapide pour lookup sans scanner les profils.

Non implémenté en v1. Reporté à v2 quand un consommateur (EGraph
dans `_metrics.md`) exprimera le besoin.

### Usage prévu

1. **Cache de benchmark** : `store.save("bench.hvn")` +
   `profiles.save("bench.hvp")`. Le second est plus petit, plus
   souvent réécrit.
2. **Comparaison de runs** : charger deux `.hvp`, `diff(p1, p2)`,
   décider si un changement d'implémentation a amélioré une
   métrique.
3. **Alimentation EGraph** : injecter un `Profile` dans l'EGraph
   (v2, cf. `_metrics.md` §Boucle).
4. **Distribution** : un acteur distant peut envoyer un `.hvp`
   pour partager une mesure. Le parent + scope permettent de
   reconstruire la hiérarchie.

### Ce que HVP1 n'est pas

- Un format d'échange entre versions majeures. La stabilité est
  garantie tant que `magic` reste `HVP1`.
- Un format pour les `Metric(K, P)` compile-time (cf.
  `platform/abi/metric.zig`). Ceux-ci sont des types, pas des
  valeurs ; ils n'ont pas de représentation binaire.
- Un conteneur pour du texte ou des logs. C'est une mesure unique,
  pas un flux d'événements.

