# Tuto : expand, integrate, solve — les trois magics d'algebre

Heaven expose trois operations d'algebre symbolique. Ce tuto les fait
tourner en 5 minutes.

## Regle de base

Un seul magic par invocation, un seul argument :

    expand(<expr>)      -- developpe un polynome
    integrate(<expr>)   -- primitive en x
    solve(<expr>)       -- racines du polynome

L'argument est une expression. Le resultat est un AST, rendu en infixe.

## Etape 1 — expand

    echo 'expand((x+1)^2)' | heaven --eval-file /dev/stdin
    # -> (+ (+ (^ x 2) (* 2 x)) 1)

C'est `x^2 + 2x + 1`, en forme prefixe.

## Etape 2 — integrate

    echo 'integrate(x^2)' | heaven --eval-file /dev/stdin
    # -> (/ (^ x 3) 3)

La constante `+ C` est retiree automatiquement par le backend.

## Etape 3 — solve

    echo 'solve(x^2 - 4)' | heaven --eval-file /dev/stdin
    # -> (= (= x (2 ou x)) -2)

Deux racines : `2` et `-2`. Le format infixe est encore imparfait
(`(= (= x (2 ou x)) -2)` au lieu de `x = 2 | x = -2`) mais les valeurs
sont correctes.

## Utilisation dans un fichier .hvn

Les magics sont utilisables dans un fichier .hvn normal :

    fn roots _ = (solve (^ x 2) - 4)
    (roots 0)

`heaven --eval-file fichier.hvn` ou `heaven run fichier.hvn`.

## Combiner avec d'autres operations

    expand((x+1)*(x-1))       -- -> (+ (^ x 2) -1)
    integrate((^ x 3))        -- -> (/ (^ x 4) 4)
    solve((^ x 2) - 1)        -- -> x = 1 ou x = -1

Les magics renvoient un AST, donc reutilisables tels quels dans
d'autres calculs.

## Limites connues

- Variable `x` uniquement (pas de `y`, `z`).
- Format `solve` imparfait (cosmetique).
- Multivarie, limites, equations differentielles : absents.

## Voir aussi

- `docs/spec/_magics.md` — spec formelle.
- `docs/book/src-v2/28b-magics.md` — chapitre du livre.
- `docs/spec/_integrate_bug.md` — bug historique (resolu 2026-11-26).
