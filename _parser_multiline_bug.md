# Parser : multi-ligne constructeurs imbriques (2026-10-20)

## Vrai symptome (corrige l'ancienne hypothese "limite ~180b")

PAS une limite de longueur. La cause est le **parsing multi-ligne pour
constructeurs imbriques** (`O.Kcons (...)` etale sur plusieurs lignes).

## Reproduce (fichier /tmp/p5.hvn)

    import "stdlib/ontology.hvn" as O
    kb _ = (O.Kcons
      (O.MkTriple "s" "teacherOf" "p")
      (O.Kcons
        (O.MkTriple "p" "teacherOf" "a")
        ...
        O.Knil))

Test `(O.kb_query (kb unit) "s" "teacherOf") == "p"` -> KO.

## Contre-exemple : meme KB sur UNE ligne -> OK (3/3)

## Ce qui marche en multi-ligne

    chain k t =
      let nxt = (O.kb_query k t "teacherOf") in
      if (= nxt "") then 0
      else (+ 1 (chain k nxt))

=> multi-ligne fonctionne pour `def = <suite>` et `let-in`.

## Ce qui casse

`kb _ = (O.Kcons` sur la meme ligne que `=`, avec continuations
indentees. Le pattern d'accumulation (`import.zig:237`, comme
`std_loader.zig`) ne reconstruit pas correctement les applications
nested de constructeurs.

## Impact

Les KB inline > ~4 triplets doivent etre sur une ligne (ou splittees
en plusieurs defs). Les tests existants (`test_ontology_*.hvn`)
utilisent la forme courte qui marche.

## Fix

~1 session parser : soit l'accumulation indentee doit gerer les
parentheses ouvertes sur la ligne `=` (tracker depth a travers les
lignes), soit il faut une autre strategie (parens-balanced accumulator
au lieu de "indented continuation").

Non bloquant : workaround = une ligne ou spliter en plusieurs defs.
