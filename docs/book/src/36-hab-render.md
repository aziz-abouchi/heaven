# Hab Render — HTML par catamorphisme

> `html_render = cata alg` sur l'arbre de rendu Hab.

## Théorie

Tree = Leaf(String) | Node(Tag, List(Tree)).

Le renderer est un **catamorphisme** : fold récursif qui remonte
l'arbre avec une algèbre par constructeur.

    html_render (leaf text)         = text
    html_render (node tag children) = "<tag>" + concat(map html_render children) + "</tag>"

## Implémentation

    html_render (pair t p) =
      if (= t "leaf")
        p
        (string_concat "<" (string_concat t
          (string_concat ">" (string_concat
            (html_children p)
            (string_concat "</" (string_concat t ">"))))))

## Tests (3 outils)

- `tests/hab/render_basic.hvn` (4/4)
- `tests/hab/render_quickcheck.hvn` (3/3) : terminaison, identité leaf
- `tests/hab/render_smocker.hvn` (2/2) : ordre LIFO

## Pièges

- λ 2-params ne parse pas (G.1)
- let-in en RHS de = (G.2)
- Définitions AVANT les tests (G.15)
