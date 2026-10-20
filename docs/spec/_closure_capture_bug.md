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

## Section 2 -- bug residuel : ctor pattern 2-arg + ctor body (2026-10-20)

Apres fix `bound_syms` (closure2 8/8, ctor_cap 4/4, Dcrash 2/2,
wc A/B/C, H1min 8/8), un cas residuel SIGSEGV :

    data B2 = MkB2 (Int -> Int) (Int -> Int)
    mk_ds (MkB2 _ r) = (MkB2 r r)         -- SIGSEGV
    ext_ds (MkB2 f g) = (g 0)
    ((ext_ds (mk_ds (MkB2 id (lambda x -> (+ x 1))))) 0)

Idem `mk_d (MkB2 _ r) = (MkB2 r (lambda x -> (r x)))`.

**Ce qui marche** :
- `Dcrash` : `mk_apply r _ = (lambda x -> (r x))` (pas de ctor
  pattern) -> 6 OK.
- `ctor_cap` : `wrap_add n _ = (MkWrap (lambda x -> (+ x n)))`
  (1 sous-pattern) -> 8 OK.
- `H1min/H1b` : `mkb_h1 f (MkB2 l r) = (MkB2 f r)` (2 sous-patterns,
  var en body, PAS de lambda autour) -> 6 OK.
- `wc` A/B/C : wildcard, bind var, `mk_c (MkB2 _ r) = (MkB2 r r)`
  -> 6 OK (sans `ext_ds` pattern ctor).

**Difference** : `mk_ds` combine ctor pattern 2-arg + ctor body
avec la 2e var capturée + `ext_ds` (ctor pattern 2-arg). Une des
trois choses casse.

**Hypothese** : `bound_syms[bound_count]` accumule les syms des
sous-patterns (f, r ou l, r), et `substSym` substitue la 2e var
dans le body `(MkB2 r r)`. Si `substSym` sur `.apply` reconstruit
un apply avec `span_a` malformé, le body résultant peut contenir
un apply dont `payload` est le ctor `MkB2` et `span_a` = [r_val,
r_val]. À l'éval, `MkB2 r_val r_val` où `r_val` est le lambda_id.
Le ctor est évalué (ligne 1810, ctor_arity) et évalue chaque arg.
Peut-être que l'arg `r_val` (lambda_id) est évalué deux fois et
la 2e fois il est dangling.

**Prochaine session** : reproduire `mk_ds` + `ext_ds` isolément,
capturer le backtrace avec gdb, fixer dans `evalFunction` ou
`substSym`. Effort : 1 session.

**Priorite** : P1 (ne bloque pas Fantasy Land, Optics, Free,
MaybeT ; bloque seulement `stdlib/profunctor.hvn` complet et
`Classy Optics` rank-2 encode).

## Section 2 -- REFUTE (2026-10-20)

Le "SIGSEGV" de `mk_ds` etait un **test malforme**, pas un bug
runtime :

    ext_ds (MkB2 f g) = (g 0)   -- retourne 1 (deja applique)
    ((ext_ds (mk_ds ...)) 0)    -- (1 0) = erreur de type

V1 (`mk1 (MkB2 _ r) = r`) et V2 (`mk2 (MkB2 _ r) = (MkB2 r r)`)
passent 3/3 et 4/4. Test propre `(ext_ds (mk_ds ...)) == 1` passe.

**Conclusion** : la closure capture fonctionne pour tous les cas
testes. Pas de bug residuel. Section 2 close.

`stdlib/profunctor.hvn` : les tests `lmap`/`rmap`/`pcompose` de
`/tmp/pf_ok.hvn` echouent pour une **autre raison** (test malforme
ou dispatch `@dispatch_instance` avec lambda en argument, a
investiguer en session fraiche si prioritaire).

