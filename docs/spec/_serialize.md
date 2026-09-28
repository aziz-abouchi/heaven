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
