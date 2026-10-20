# Bug : closure ne capture pas les arguments (2026-10-20)

## Symptome

    mk_adder n _ = (lambda x -> (+ x n))
    (mk_adder 3 unit) 5   -- attendu 8, obtenu (lambda x (+ x n))

La lambda `(lambda x -> (+ x n))` retournee par `mk_adder 3` ne
capture pas `n = 3`. `n` reste un symbole libre/non lie. Quand
la lambda est appelee plus tard, `n` n'est plus dans l'env de
`mk_adder`, donc l'evaluation ne resout pas `n` -> reste symbole.

## Discriminants

| Cas | Resultat |
|---|---|
| `(lambda x -> (+ x 3)) 5` (litteral) | ✅ 8 |
| `mk_inc _ = (lambda x -> (+ x 1))` puis `(mk_inc unit) 5` | ✅ 6 |
| `mk_adder n _ = (lambda x -> (+ x n))` puis `(mk_adder 3 unit) 5` | ❌ reste lambda |
| `mk_adder 3` inline puis apply | ❌ reste lambda |

**Conclusion** : la lambda est bien evaluee en valeur, mais
l'environnement au moment de sa creation n'inclut pas les
arguments de la fonction englobante (`n`). Closure by-name au
lieu de by-value (ou env non chaine).

## Impact

- `stdlib/profunctor.hvn` : `lmap`, `rmap`, `pcompose` ne marchent
  pas (utilisent `f`/`g`/`l`/`r` captures).
- Classy Optics (MonadReader) : bloque (Rank-2 + closures).
- Free monad generique (`Free f a`) : bloque (utilise `fmap f`).
- Fantomes d'ordre superieur en general (callbacks, handlers).

## Non impacte

- Fantasy Land (McKeenna) : ✅ (pas de closure d'argument).
- Optics (Lens/Prism/Iso) : ✅ (les lens contiennent deja `g`
  et `st` comme champs data, pas comme closures). Teste 4/4.
- Free monad tag-encoded : ✅ (tags + data, pas de closure capture).
- MaybeT : ✅ (pas de closure capture).

## Fix a faire (session dediee)

Zig : `src/core/engine_expr.zig` / `src/core/heaven_expr.zig`.

1. Chercher comment `lambda` est evalue.
2. Verifier si l'env de la lambda inclut les bindings de
   l'appel en cours (`n` lie a `3`).
3. Si oui : fuite de scope (env libere avant appel).
   Si non : capture absente.

Effort : 1 session (diagnostic 2-3 blocs + fix + tests).
Priorite : P0 (bloque Profunctor + Classy Optics + Free
generique + callbacks).

## Workaround temporaire

Ecrire `profunctor.hvn` avec les lambdas en parametres directs
(pas capturees) :
    dimap f g (MkProfunctor l r) = (MkProfunctor f g)
puis composer a l'appel. Verbeux, perte de l'abstraction.
