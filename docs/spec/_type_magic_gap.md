# Magic `type` : ecart

**Date** : 2026-10-15
**Statut** : commande REPL OK, magic absent.

## Ce qui marche

Dans le REPL web :
    heaven> type 42       -> Int
    heaven> type true     -> Bool
    heaven> type "hello"  -> String
    heaven> type 3.14     -> Float

## Ce qui ne marche pas

Dans un fichier .hvn :
    test "type":
      (type 42) == "Int"    -- echoue

## Cause

Deux chemins distincts :

| Contexte | Dispatch |
|---|---|
| REPL web : type X | Commands.eval -> typeOf |
| Fichier : (type X) | heaven.eval (magic) |

`type` n'est pas un magic dans engine_expr.zig. Pour l'ajouter,
il faudrait acces a types_mod.Infer (pas dispo dans ce scope).

## Fix propose

Session dediee : ajouter le magic dans engine_expr.zig, ou
exposer typeOf via une API accessible.

## Effort

30-60 min.
