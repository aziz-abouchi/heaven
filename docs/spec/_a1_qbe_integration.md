# A1 : Intégration QBE pour build reproductible

## Objectif

Permettre à Heaven de se compiler lui-même via QBE (backend C minimal) au lieu de dépendre uniquement du compilateur Zig hôte.

## État actuel

- QBE installé dans `vendor/qbe/`
- TCC disponible dans `vendor/tcc/`
- Pipeline de compilation : Heaven → MIR → QBE → C → TCC → binaire

## Pipeline de build

1. **Heaven source** (.hvn) → AST
2. **AST** → MIR (Middle Intermediate Representation)
3. **MIR** → QBE IR
4. **QBE IR** → C code
5. **C code** → binaire via TCC

## Tests à implémenter

- [ ] Compiler `hello.hvn` via QBE
- [ ] Vérifier que le binaire produit est identique au binaire Zig
- [ ] Tester les closures et constructeurs (A2)
- [ ] Mesurer la profondeur de récursion (A3)
- [ ] Réactiver le leak check (A4)

## Prochaines étapes

1. Créer un script `build_qbe.sh` qui compile Heaven via QBE
2. Comparer les binaires produits (Zig vs QBE)
3. Identifier les fonctionnalités MIR manquantes pour le bootstrapping
