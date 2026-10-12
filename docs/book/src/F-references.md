# Annexe F — Références

Ce livre s'appuie sur des travaux existants — bibliothèques,
articles, livres, idées philosophiques. Cette annexe les liste
tous, classés par catégorie, avec des liens.

## Sources directes

Bibliothèques dont Heaven s'inspire pour ses modules std et ses
chapitres avancés.

- **`maryamyriameliamurphies.js`** — Steven J. Syrek.
  Bibliothèque Haskell-style en JavaScript. Structure des modules
  (`base`, `ord`, `eq`, `functor`, `monad`, `foldable`) réutilisée
  pour `core/std/`. Le nom vient de *Finnegans Wake* (Joyce).
  https://github.com/sjsyrek/maryamyriameliamurphies.js

- **Fantasy Land** — Brian McKenna et contributeurs.
  Spécification d'interopérabilité pour les structures algébriques
  en JavaScript. 24 algèbres avec lois et signatures. Sert de
  contrat pour les type classes de Heaven V1.
  https://github.com/fantasyland/fantasy-land

- **`lens`** — Edward Kmett et contributeurs.
  Optiques (lenses, prisms, traversals). Inspiration pour
  `core/std/lens.hvn` et le chapitre 15.
  https://github.com/ekmett/lens

- **`recursion-schemes`** — Edward Kmett.
  Catamorphismes, anamorphismes, hylomorphismes, paramorphismes.
  Inspiration pour `core/std/recursion.hvn` et le chapitre 14.
  https://github.com/ekmett/recursion-schemes

- **`free`** — Edward Kmett et contributeurs.
  Free monads, monades libres, interpréteurs.
  Inspiration pour `core/std/free.hvn` et le chapitre 16.
  https://github.com/ekmett/free

## Idées fondatrices

- **CIC** (Calcul des Constructions Inductives) — Thierry Coquand
  et Christine Paulin-Mohring, 1988. Noyau mathématique de Heaven.

- **Correspondance de Curry-Howard** — Haskell Curry (1934) et
  William Alvin Howard (1969). « Une preuve est un programme, une
  proposition est un type. »

- **Monades en programmation fonctionnelle** — Eugenio Moggi (1989),
  Philip Wadler (1992). Inspiration pour les effets algébriques.

- **Type-driven development** — Edwin Brady, Idris (2007-).
  Inspiration pour le trou (`?`) et `:hole`/`:refine`.

- **Lenses (van Laarhoven)** — Twan van Laarhoven (2009).
  Encodage de lens comme fonctions.

- **Profunctor optics** — Matthew Pickering, Jeremy Gibbons,
  Nicolas Wu (2017). Généralisation des optiques.

- **Modèle d'acteurs** — Carl Hewitt (1973), Joe Armstrong
  (Erlang, 1986). Inspiration pour `spawn`/`tell`/`recv`.

- **Session types (MPST)** — Kohei Honda (1993), Nobuko Yoshida,
  Marco Carbone. Inspiration pour la concurrence typée.

- **QTT** (Quantitative Type Theory) — Robert Atkey (2018),
  Conor McBride. Inspiration pour D19.

- **Théorie des catégories** — Samuel Eilenberg et Saunders
  Mac Lane (1945). Inspiration pour les chapitres 14-17.

- **Lemme de Yoneda** — Nobuo Yoneda (1954). Inspiration pour
  l'esthétique du langage (« un objet est déterminé par ses
  morphismes »).

- **Logique linéaire** — Jean-Yves Girard (1987). Inspiration
  pour QTT et les capacités.

## Livres et articles

- Miran Lipovača, *Learn You a Haskell for Great Good!*,
  No Starch Press, 2011. Structure pédagogique du book.

- Bartosz Milewski, *Category Theory for Programmers*,
  auto-publié, 2019.

- Saunders Mac Lane, *Categories for the Working Mathematician*,
  Springer, 1971.

- Benjamin C. Pierce, *Types and Programming Languages*,
  MIT Press, 2002.

- Harold Abelson et Gerald Jay Sussman, *Structure and
  Interpretation of Computer Programs*, MIT Press, 1985.

- Daniel P. Friedman et Matthias Felleisen, *The Little Schemer*,
  4e éd., MIT Press, 1995.

- Jean-Yves Girard, Yves Lafont, Paul Taylor, *Proofs and Types*,
  Cambridge University Press, 1989.

- The Univalent Foundations Program, *Homotopy Type Theory:
  Univalent Foundations of Mathematics*, 2013.

- Graham Hutton, *Programming in Haskell*, 2e éd.,
  Cambridge University Press, 2016.

- Sandy Maguire, *Thinking with Types*, auto-publié, 2018.

## Outils

- **Zig** — Andrew Kelley. Langage d'implémentation.
  https://ziglang.org

- **QBE** — Quentin Carbonneaux. Backend de compilation.
  https://c9x.me/compile/

- **Tree-sitter** — Max Brunsfeld. Parser incrémental (D21).
  https://tree-sitter.github.io

- **WebAssembly** — W3C. Cible de compilation.
  https://webassembly.org

- **D3.js** — Mike Bostock. Visualisation egraph.
  https://d3js.org

- **miniKanren** — William Byrd, Daniel Friedman.
  https://minikanren.org

- **e-graphs / egg** — Max Willsey et al.
  https://egraphs-good.github.io

## Philosophie et littérature

Ces références ne sont pas techniques. Elles éclairent la
philosophie du projet : esthétique, vérité, structure.

- Nicolas Boileau, *Art poétique* (1674). « Ce qui se conçoit
  bien s'énonce clairement. »

- Ludwig Wittgenstein, *Tractatus logico-philosophicus* (1921).
  Sur la structure logique du langage.

- Ludwig Wittgenstein, *Investigations philosophiques* (1953).
  Sur les jeux de langage.

- Michel Foucault, *Les Mots et les Choses* (1966). Sur la
  classification et les distinctions fondatrices.

- Jorge Luis Borges, *La Bibliothèque de Babel* (1941). Sur
  l'infini combinatoire.

- James Joyce, *Finnegans Wake* (1939). Source du nom
  `maryamyriameliamurphies`.

- Gottlob Frege, *Begriffsschrift* (1879). Fondation de la
  logique moderne.

- Willard Van Orman Quine, *Le Mot et la chose* (1960). Sur la
  toile de croyances et la traduction.

## RFC internes

- **RFC-0001** — Extraction du parser (`expr_parser.zig`).
- **RFC-0002** — Bitstrings (destructuration + construction).
  https://github.com/aziz-abouchi/heaven/blob/main/RFC-0002.md
