<!-- HEAVEN:stub-macos-status -->
# Stub aarch64_macos : etat et impasse (2026-10-16)

## Constat

Tentative d'alignement du stub `aarch64_macos.zig` sur le contrat
`x86_64_linux.zig`. Apres ~10 iterations (shim io_console, target,
Thread, fs.File, writeStdout, etc.), il reste >= 10 erreurs :

- `type 'type' not a function` (x5) : `sp.TreeSitterParser` attendu
  par bridge/dispatch/heaven_expr/import/io_handler, absent du stub.
- `time.milliTimestamp` / `nanoTimestamp` manquants (profiler, egraph).
- `ts` (tree-sitter cImport) manquant (elab).
- `net.listenTcp` retourne `std.net.Server` au lieu d'un i64 -> type
  incompatible avec le contrat.
- `cmdArgs` (ex `args`) attendu par main.zig.

## Blocages structurels

1. **Non testable sans SDK macOS** : `zig build -Dtarget=aarch64-macos`
   compile, mais aucune execution possible sur cette machine (Guix
   Linux). Le code produit ne sera jamais valide avant une session
   sur machine macOS.

2. **Pas un "stub" : une reimplementation complete.** Le fichier
   actuel (78 l.) doit croitre a ~400 l. pour couvrir le contrat.
   Ce n'est pas une session d'alignement, c'est un port.

3. **Risque de regression multipliee** : chaque symbole ajoute
   au stub peut casser une autre cible (le contrat est partage).
   Sans test cross-cible automatise, chaque patch est un coup
   dans le noir.

## Options

- **A (fait)** : rollback + documenter. Debloque la session.
- **B (chantier)** : session dediee 4-6h avec SDK macOS installe
  (`zig fetch --save system_sdk` ou equivalent 0.15). Necessite
  acces a un Mac ou une CI macOS.
- **C (alignement mecanique)** : copier `x86_64_linux.zig` et
  retirer les branches Windows, garder Darwin/POSIX. Rapide mais
  non teste.

## Recommandation

Option B en session dediee. Meme situation pour `x86_64_windows.zig`
(chantier suivant) : sans SDK ni machine cible, c'est de l'ecriture
a l'aveugle.

Priorite reelle : les bugs moteur traces (auto-recursion if-else,
D20 bigint) sont plus impactants que ces stubs non testables.
