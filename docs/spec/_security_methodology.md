# Sécurité — méthodologie complète (2026-10-26)

## Contexte : les CVE 2026 qui motivent la décision

Les attaques récentes visent la chaîne de compilation elle-même,
pas seulement le code exécuté :

- **CVE-2026-77649** (Rust `internment 0.8.7`) : code malveillant
  exécuté À LA COMPILATION (CWE-506)
- **arrayref 0.3.10** : dépendance exécute un binaire distant au
  build (supply chain, attribution DPRK)
- **ChainDrop npm** : 1300 packages compromis, 2 milliards dl/mois
- **CVE-2026-115567** (Tokio) : use-after-free en SAFE Rust
- **CVE-2026-92392** (Zig/curl) : overflow non détecté
- **CVE-2026-27143** (Go cmd/compile) : analyse statique insuffisante
- **OSEC-2026-18** (OCaml Marshal) : régression d'un correctif
- **CVE-2026-58592** (Ladybird WASM) : dangling reference
- **CVE-2026-109618** (PHP) : OOM → état partiel → RCE
- **CVE-2026-109619** (PHP) : UAF via état global persistant
- **CVE-2025-14178** (PHP) : integer overflow → heap buffer
- **CVE-2025-14181** (PHP) : l'optimiseur supprime le check
- **CVE-2025-14177** (PHP) : mémoire non initialisée exposée

**Constat transversal** : la corruption mémoire et l'exécution
malveillante persistent même dans les langages "sûrs". La réponse
ne peut pas être "on va détecter" — elle doit être "on va empêcher".

## Niveau 0 — Capabilities (barrière structurelle)

Principe : un import s'exécute avec capabilities vides par défaut.
Tout accès non autorisé échoue fermé (CapabilityDenied), sans
détection préalable du code malveillant. Inverse le problème : on
ne cherche pas à savoir ce que le code fait, on contrôle ce qu'il
peut faire.

### Ce qui existe déjà

- `cap_acquire`, `@fs_read "fs:read"`, `@net_*` dans `evalMagic`
- Pattern capability dans les NOMS, pas dans l'APPLICATION

### Niveau A — raw_syscall avec capability

Chaque syscall déclare sa capability. `raw_syscall_fs` exige
`fs:write:*`, `raw_syscall_net` exige `net:connect:*`. Un `.hvn`
sans la cap ne peut pas appeler le syscall, même direct.

**Effet** : le bug `@intCast` (`evalMagic:1688`) devient
inatteignable depuis un import non autorisé.

### Niveau B — import en cap vide

`import "lib/foo.hvn"` charge `foo.hvn` dans un env où AUCUNE cap
n'est accordée par défaut. Seules les caps explicitement demandées
sont transmises :

    import "lib/foo.hvn" as F with (fs:read:./data, time:now)

**Effet** : internment (Rust), arrayref exécutés à la compilation
= neutralisés structurellement.

### Niveau C — élaboration sandboxée

Toute élaboration tourne avec zéro cap IO. Seuls `parser` et `elab`
travaillent, sans `fs:read`, sans `net`, sans `raw_syscall`, sans
`exec`.

**Effet** : arrayref (binaire distant au build) impossible.

### Sécurité additionnelle — thunks mémorisés

Un thunk mémoïsé retient ses capabilities. Fuite de capability
par persistance. Règle : un thunk mémoïsé ne survit pas à la
portée des capabilities capturées. Si le résultat doit survivre,
cap explicitement transférée (auditable).

### Limite honnête

Vérification statique (`Cap<T>` typée) exige `DependentChecker`
réel. Pas avant P5. Runtime-only suffit pour les niveaux B/C.

## Niveau 1 — Contrat de sûreté du Store

Chaque API publique du Store : précondition / postcondition /
comportement en cas de violation. Pas de `@panic` suivi
d'utilisation partielle. `store.get(id)` invalide → `Result`/erreur,
pas UB.

**Livrable** : `_store_safety_contract.md` (P5).

## Niveau 1.5 — Sûreté mémoire (CVE PHP)

Les CVE PHP 2026 montrent que la corruption mémoire persiste dans
les langages à GC. 4 règles pour Heaven :

### R1 — Allocation sûre
Toute allocation (`raw_alloc`, `store.lit`, `store.apply`) a un
chemin d'échec explicite. Pas de `@panic` suivi d'utilisation
partielle. Si l'alloc échoue, le Store revient à un état cohérent.

### R2 — Initialisation garantie
`raw_alloc` zéro-init OU `poke` complet avant lecture.
`poke_int64`/`peek_int64` vérifient les bornes AVANT d'écrire/lire.
Poison `0xAAAA` remplacé par `Result`/`Option` explicite.

### R3 — Composition de spans avec overflow check
Toute composition de deux `Span` vérifie `len_a + len_b <= u32.max`
et retourne une erreur, pas un span tronqué.
Fix exact de CVE-2025-14178.

### R4 — Checks de sûreté non-optimisables
Vérifications de borne dans `raw_syscall` et `store.get` marquées
`@setRuntimeSafety(true)` ou équivalent, JAMAIS optimisées.
Fix exact de CVE-2025-14181 (l'optimiseur PHP supprimait le check).

### Tests de rejet obligatoires (niveau 1.5)
- Allocation qui échoue → Store cohérent, pas de panic
- `poke_int64` hors bornes → erreur, pas d'écriture
- `peek_int64` après free → erreur, pas de poison
- composition de spans > `u32.max` → erreur, pas de troncature
- `raw_syscall` avec taille négative → erreur (fix `evalMagic:1688`)

## Niveau 2 — Fuzzing différentiel

Fuzzer l'interpréteur : entrées aléatoires (syntaxe valide,
sémantique invalide) → erreur, JAMAIS panic.
Fuzzer différentiel : même programme → interpréteur vs QBE vs
WASM → comparer sorties ET erreurs.
Fuzzer imports : fichier qui importe fichier qui importe →
détecter cycles, profondeur excessive, fuites.

**Livrable** : `tests/fuzz/` + `tools/fuzz_interp.sh` (P5+).

## Niveau 3 — Avertissements compile-time

Heaven doit AVERTIR (pas seulement accepter) sur :
- `raw_syscall` avec constantes non validées (taille négative,
  fd arbitraire, pointeur non vérifié)
- `@panic`/`unreachable` accessibles depuis `.hvn` (chemin d'attaque)
- Cascades `if` > 5-6 niveaux (`_cascade_if_bug.md`)
- Imports non résolus ou cycliques
- `poke_int64`/`peek_int64` sans vérification de bornes

Sévérité : `error` / `warning` / `info`.
**Livrable** : `_security_warnings.md` (P0b).

## Niveau 4 — Supply chain Heaven

Heaven n'a pas de registre, mais :
- `import "stdlib/..."` et `import "lib/..."` sont des dépendances
- Les 25 fichiers auto-chargés au boot = surface d'attaque
- Un `.hvn` importé peut exécuter du code à l'élaboration

### Règles à poser MAINTENANT
1. Tout import résolu statiquement (pas de chemin dynamique)
2. Tout import hashé (SHA-256 dans un lockfile)
3. Les imports n'exécutent PAS de code à l'élaboration
   (seulement parser + élaborer)
4. Mode `--strict-imports` refuse tout import non déclaré

**Livrable** : `_import_security.md` + `heaven.lock` (P0b/P5).

## Niveau 5 — Audit chaîne de compilation

Pas avant E1-E3 + bootstrap. Mais à prévoir :
- Reproductibilité : deux compilations = binaires identiques
- Diversification : auto-compilation vérifiée par binaire de confiance
- Préservation sémantique : chaque passe (elab → MIR → QBE)
  a un théorème de préservation + test différentiel

C'est le niveau où le noyau de preuves (`DependentChecker` réel,
pas stub) devient critique pour la sécurité.

## Règle transversale

Aucune garantie de sécurité annoncée sans :
- une API identifiée
- un test de rejet (entrée malformée → erreur, pas panic)
- un warning documenté quand le rejet n'est pas possible

## Priorité

**Immédiat (P0b)** :
- ch8, ch2, ch26 : retirer les garanties non démontrées, lier
  aux niveaux 3 (warnings) et 5 (audit chaîne)
- Créer `_security_warnings.md` et `_import_security.md`

**Après P5 (D12-bis)** :
- Niveau 0 (capabilities) : B + C en premier (pas de typechecker)
- Niveau 1.5 (R1-R4)
- Niveau 2 (fuzzing)
- Niveau 3 (warnings)
- Niveau 4 (lockfile)

**Après auto-hébergement** :
- Niveau 5 (audit chaîne)

## Vecteurs d'attaque à documenter (recherche)

1. **Preuves Cubical** : si D0 est acté, un théorème peut exécuter
   du code (`transp`/`hcomp`). Vecteur d'attaque à traiter au
   niveau 5.
2. **Macros** : si `quote`/`unquote` (branche
   `backup-wip-20260914`) est mergée, une macro peut exécuter du
   code arbitraire à l'élaboration. Même traitement que l'import
   hostile (sandboxing, capabilities).
