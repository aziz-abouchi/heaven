<!-- HEAVEN:json-parse -->
# Parseur JSON V0 — chantier (2026-10-19)

## Etat

`stdlib/json_parse.hvn` (73 l.) ecrit : parseur JSON V0
(num, str, bool, null) + accesseurs `json_as_int_s`, etc.

## Tests isoles (k1-k4 dans /tmp)

- k1 : `data JVal = ... | data JRes = ...` seuls -> 3/3.
- k2 : patterns imbriques `(JOk (JNum n) p)` -> 7/7 en local.
- k3 : import d'un fichier avec data JVal/JRes + accesseurs
  -> 2/2 (import fonctionne !).
- k4 : 0-pattern def vs let-in -> 7/7 (les deux formes OK).

## Test d'import de json_parse.hvn -> ECHEC SILENCIEUX

`import "stdlib/json_parse.hvn" as JP` fait sortir le process
avec exit 0 et "Memory clean" mais aucun test n'est liste.
C'est **exactement le fossile #4** documente dans
`lib/heaven_parse.hvn:4` : "l'import d'un fichier dont une clause
a un pattern de constructeur 0-arg qualifie en tete de plusieurs
patterns fait sortir le process silencieusement".

## Cause precise (a confirmer)

`json_parse.hvn` contient plusieurs fonctions avec des chaines
`if-then-else` imbriquees (`json_skip`, `json_digits_end`,
`json_str_end`, `json_parse2`). Peut-etre une combinaison
`data + if-then-else imbrique + import` declenche le fossile.

A discriminer en session dediee :
- reduire `json_parse.hvn` a une seule fonction `if` test
- voir si l'import seul suffit, ou si c'est cumulatif

## Distance

1 session pour identifier la cause exacte (reduction de
`json_parse.hvn` bissection).

## Contournement possible

Fusionner `json_parse.hvn` dans le fichier test (pas d'import).
Mais ca ne resout pas le fossile pour les autres fichiers.

## Autres tests reussis ce matin

- data natif (JVal/JRes) : OK.
- patterns imbriques : OK.
- import + data simple : OK.
- `if then else` en tete de corps de def natif (fix 011d934) : OK.
- `if then else` en tete de corps de def dans `heaven_parse.hvn` (fix bcecc94) : OK.

Seul le fossile #4 reste bloquant.


## Etat final V0 (2026-10-19)

V0 (num, bool, null, ws) : operationnel, 11 tests verts.
Commit 9db0214.

V1 (strings, arrays, objects) : **bloque** par deux bugs
distincts identifies :

1. `let x = (JArr JVNil) in (if (= x x) 1 0)` echoue silencieusement,
   alors que `f (ACons 7 ANil) = x` marche (rec2 6/6).
   - Probablement l'egalite `=` sur constructeur a argument
     constructeur, OU `let` avec constructeur en RHS.
   - Test discriminant : rec (2/4) vs rec2 (6/6).

2. Les `data` mutuellement recursifs (`JVal` reference `JListVal`
   qui reference `JVal`) parsent et enregistrent, mais l'eval
   de l'expression les impliquant echoue.

## Pour une session V1

Test discriminant minimal (deja identifie) :
    data A = ANil | ACons Int A     -- marche (rec2)
    data B = BNil | BCons A B       -- a tester
    f (BCons a b) = 0               -- a tester
    let x (BCons (ACons 1 ANil) BNil) in (if (= x x) 1 0)  -- ?

Ordre de diagnostic :
1. let + constructeur en RHS (sans `=`).
2. `=` sur constructeur a argument constructeur.
3. `data` mutuellement recursifs.

Effort : 1 session.
