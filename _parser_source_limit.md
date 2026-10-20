# Parser : limite taille source (~180-210 bytes)

## Symptome (2026-10-20)
KB ontologie inline > ~180 bytes -> InvalidSyntax ou valeurs fausses.
8 triplets noms courts (~160b) OK. 7 triplets noms longs (~210b) KO.

## Reproduce
- /tmp/f.hvn : 6 triplets ~180b -> OK
- /tmp/a.hvn : 7 triplets ~210b -> KO

## Impact
Splitter les KB en fichiers courts. 2 fichiers test_ontology_*.hvn.

## Effort
1 session parser (tokenizer ou buffer limite). Non bloquant.
