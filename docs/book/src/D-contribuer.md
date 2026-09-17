# Annexe D — Contribuer

Heaven est un projet ouvert. Voici comment participer, quel que soit
votre niveau.

## Signaler un bug

Le plus utile. Si vous rencontrez un comportement inattendu :

1. **Vérifiez** que ce n'est pas documenté (annexe B).
2. **Reproduisez** le bug dans un fichier `.hvn` minimal.
3. **Ouvrez une issue** sur GitHub avec :
   - Le fichier `.hvn` qui reproduit.
   - La sortie observée.
   - La sortie attendue.
   - Votre OS et la version de Zig.

Un bug bien rapporté vaut trois bugs corrigés.

## Proposer une amélioration

Avant de coder, ouvrez une issue pour discuter. Cela évite de
travailler dans le vide. Décrivez :

- Le problème que vous voulez résoudre.
- Votre approche proposée.
- Les alternatives envisagées.

## Corriger un bug

1. **Forkez** le dépôt.
2. **Créez une branche** : `git checkout -b fix/nom-du-bug`.
3. **Corrigez**, en ajoutant un test qui échouait avant.
4. **Vérifiez** que la suite complète passe : `bash tests.sh`.
5. **Ouvrez une pull request**.

Les commits doivent être atomiques, avec un message clair. Préfixes
utilisés : `fix:`, `feat:`, `docs:`, `test:`, `refactor:`.

## Écrire de la documentation

La documentation est dans `docs/book/`. Si vous voyez une faute, une
formule obscure, un exemple faux : corrigez.

```bash
cd docs/book
mdbook serve --open
