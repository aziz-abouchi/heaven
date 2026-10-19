# Bug : `let _ = e in body` n'evalue pas `e` (2026-10-19)

## Symptome

Reproducteur (une ligne, aucun split) :

    let _ = (print "A") in let _ = (print "B") in (print "C")

Sortie observee : `"C"` uniquement. A et B ne s'affichent pas.

## Impact

- Tout programme Heaven imperatif casse silencieusement.
- `http_server.hvn` (racine, non-tracke) : `let _ = (@net_listen ...)`,
  `let _ = (@net_write ...)` ne font rien. Le serveur se termine
  sans avoir ecoute. C'est un faux positif observe en E4-triage.
- `core/http_server.hvn` : idem, mais il n'utilise pas `let _` (il
  bind des noms reels) — a reverifier.

## Hypotheses (non verifiees)

1. Desugaring de `let _ = e in body` : si `_` est traite comme
   wildcard de pattern et que le RHS est *skippe* (pas juste ignore),
   `e` n'est jamais evalue. Voir `heaven_expr.zig:713`
   (`if (std.mem.eql(u8, nm, "_")) continue;`) et `convertLetIn`
   (`heaven_expr.zig:1988`).
2. `let` est lazy en general, et `_` (sans usage) empeche la
   forcage. A tester : `let x = (print "A") in (print "B")` — si
   A ne sort pas, c'est `let` qui est lazy, pas `_`.

## Correctif possible (a valider en session)

- Soit forcer le RHS a l'eval pour `let _` (mais alors `let x`
  aussi ? a verifier la coherence).
- Soit desugar `let _ = e in body` en `seq e body` (si `seq` force
  bien ses deux args).

## Comportement annexe (PAS un bug)

`splitStatements` (`test_runner.zig:36`) traite chaque ligne non
indentee comme un statement separe. Un let-chain multi-ligne a
colonne 0 = N statements orphelins. C'est *voulu* pour les fichiers
de tests (clauses, gardes). **Workaround** : ecrire les let-chain
sur une seule ligne (ou indenter les continuations).

## Prochaine session

1. Discriminant : `let x = (print "A") in (print "B")` (une ligne).
2. Si `let x` force, patch `_` uniquement (~10 lignes).
3. Si `let x` ne force pas non plus, patch `let` general (parser
   ou eval), tests unitaires requis.
4. Puis E4b : `http_server.hvn` reecrit en une ligne (contournement
   B2) avec `let _` remplaces par `seq` ou `let r = e in`.

## Fichiers

- `src/core/heaven_expr.zig:713, 1501, 1988` (parsing `_`, `let-in`)
- `src/core/engine_expr.zig` (eval, pas de `.let =>` grep-match :
  desugaring en amont, a tracer via `parseExpression` sur un mini
  fichier)
- `src/runtime/test_runner.zig:36-90` (splitStatements)
