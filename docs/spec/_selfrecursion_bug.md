<!-- HEAVEN:selfrecursion-bug -->
# Bug : auto-recursion dans if-else retourne une valeur fausse

## Constat

    count n = if (= n 0) then 0 else (count (- n 1))
    (count 0)  -- OK : 0
    (count 1)  -- KO : != 0
    (count 2)  -- KO : != 0

Teste sur HEAD~20 (20510f5) : meme comportement. **Pre-existant**.

## Perimetre

- Fonctions qui appellent **d'autres** fonctions : OK (twice x = inc (inc x)).
- Auto-recursion **hors if** : OK (g n = (g ...) s'enregistre).
- Auto-recursion dans if-else : **KO**.
- Non-tail (avec + 0 autour) : KO aussi. **Ce n'est pas le TCO**.

## Impact

Tout parcours recursif en Heaven :
- DNS parser (dns_qname_end scan de labels).
- JSON parser (nested values).
- HTTP body parser.
- AST walkers.
- BigInt bdiv/bmod (D20 connexe).

## Hypotheses

1. Le binding du parametre n'est pas refait au self-call -> n reste
   a sa valeur initiale -> boucle detectee comme infinie -> retour
   d'une valeur sentinelle.
2. Le TCO (self-tail-call) est mal resolu et renvoie une valeur
   partielle.
3. Le cache d'appel (spine TCO) confond le frame courant et la cible.

## A reproduire

    count n = if (= n 0) then 0 else (count (- n 1))
    test "c1": (count 1) == 0

## Chantier

Session dediee 2-4h. Priorite haute (bloque N2 self-hosting).
Tracer dans engine_expr.zig : evaluer (count 1) en mode debug,
voir si le parametre est bien rebinde lors de l'auto-appel.

## Contournements connus

- Derouler la recursion (bounded, max N niveaux).
- Utiliser une boucle via add_task/schedule (scheduler).
- Ecrire le parser en natif (Zig) et l'appeler via FFI (pas Heaven pur).

## Workaround dns_v1 (non retenu)

Derouler dns_qname_end sur 8 niveaux (couvre QNAME < 255 bytes a
labels courts). Non retenu : masque le bug, ne resout rien pour les
chantiers suivants.


## Indices supplementaires (2026-10-16)

Traces ajoutees a evalFunction + evaluate + evalMagic. Resultat sur
`c4 n = if (= n 0) then 0 else (c4 (- n 1))` :

    [evalFunction] EVAL_ARG c4[0] arg_id=5756     -- litt. 1 passe au test
    [evalFunction] EVAL_ARG_RESULT c4[0] val_id=5756
    [evalFunction] ENTER c4 args_len=1
    [evalFunction] LOOP c4 arg0=5756
    [evalMagic] dispatch c4 env.n=5756            -- env A BIEN n binde
    [evalFunction] EVAL_ARG c4[0] arg_id=5752     -- (- n 1)
    [evaluate] ENTER id=5752 depth=0
    [evaluate] ENTER id=5748 depth=1              -- n
    [evaluate] ENTER id=5751 depth=1              -- 1
    [evaluate] ENTER id=5758 depth=0              -- ???
    (pas de EVAL_ARG_RESULT, pas de 2e ENTER c4)

### Observations

1. Le binding `n=5756` dans l'env du self-call est **correct**.
2. `evaluate(5752)` (= `(- n 1)`) entre mais **ne retourne pas**.
3. `evaluate(5758)` a depth=0 depuis un calcul imbrique — incoherent,
   sauf si le TCO a saute un `evalFunction`.

### Discriminants

| Forme | Resultat |
|---|---|
| `f x = x`, `(f (- 5 1))` | OK |
| `count_lit n = if (= n 0) then 0 else (count_lit 0)` | OK |
| `c4 n = if (= n 0) then 0 else (c4 (- n 1))` | KO |
| `v3 n = if (= n 0) then 0 else (let m = (- n 1) in (v3 m))` | OK |
| `v1 n = if (= n 0) then 0 else (v1 (sub1 n))` | OK |

**Discriminant net** : self-call avec arg = expression **directement**
dans l'apply : KO. Meme expression dans un `let` ou via un helper : OK.

### Hypothese la plus probable

Le TCO_BOUNCE saute l'appel `evalFunction` sous certaines conditions,
ou bien `evalMagic` (branche TCO l.885) reevalue l'arg dans le mauvais
env (`env` au lieu de `new_env`). La trace ne permet pas de trancher.

### Prochaines etapes

1. Instrumenter `evalMagic` TCO l.886 : tracer `env == new_env` ?
2. Instrumenter le retour `TCO_BOUNCE` : qui le consomme ?
3. Tests de bisection sur `evalCmp` / `store.int` sur un Id `-`.

Chantier dedie 2-4h. Bloque N2, JSON, HTTP body, AST walkers.
