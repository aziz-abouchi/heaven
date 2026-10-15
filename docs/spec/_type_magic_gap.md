# Magic `type` : ecart

**Date** : 2026-10-15
**Statut** : commande REPL OK, magic absent.

## Ce qui marche

REPL web :
    heaven> type 42       -> Int
    heaven> type true     -> Bool
    heaven> type "hello"  -> String
    heaven> type 3.14     -> Float

## Ce qui ne marche pas

Dans un fichier .hvn :
    test "type":
      (type 42) == "Int"    -- echoue

Deux chemins distincts : Commands.eval (REPL) vs heaven.eval
(magic). `type` n'est pas un magic dans engine_expr.zig.

## Fix propose

Session dediee : ajouter un magic `type` qui appelle types_mod.
Effort : 30-60 min.
