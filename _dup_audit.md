# Audit duplication heaven_expr <-> engine_expr <-> expr_parser (2026-10-20)

## Verdict : PROPRE (pas de duplication dangereuse)

### QTT (let-linear/erased/many)
- UNIQUEMENT dans expr_parser.zig (6 occurrences, meme zone)
- heaven_expr.zig:1122 convertit juste (native -> S-expr), delegue au parser
- => single source of truth

### data / import / module / class / instance
- UNIQUEMENT dans heaven_expr.zig
- => OK, pas de doublon

### Dettes de consolidation (non bloquant)

| Keyword | Localisations | Action future |
|---|---|---|
| fn | heaven(100) + engine(51) + parser(6) | Triple, consolider 1 session |
| perform | heaven(4) + engine(31) | Double, verifier si reel |
| handle | heaven(22) + engine(108) | Double, verifier si reel |
| type | heaven(40) + engine(5) | Verifier si type metier ou syntaxe |

Aucune n'est un bug actif. Documentees pour sessions futures.

## P0 reste : bug `(print (f 0))`

Decouverte 2026-10-20 :
    h _ = 42
    (print (h 0))   -- SILENCIEUX (ni 42, ni erreur)
    
    g _ = let n = 16 in n
    (print (g 0))   -- RecursionLimitExceeded
    
    (print 42)       -- OK
    (print (+ 1 2))  -- OK

=> Bug specifique : print + fonction utilisateur = silence ou crash.
   Piste : markArgDone/fuel dans branche print magic.

P0 fiche dans _qtt_runtime_bug.md section "CORRECTION MAJEURE".
