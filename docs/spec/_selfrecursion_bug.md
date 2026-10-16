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
