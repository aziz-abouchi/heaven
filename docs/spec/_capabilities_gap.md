# Capabilities : dette (C5)

**Date** : 2026-10-16
**Impact** : toutes les APIs reseau, fichier, egraph.

## Symptome

`cap_acquire` est un magic no-op qui retourne toujours 42 :

    if (op == "cap_acquire") {
        _ = try evaluate(...);  // la chaine est ignoree
        return try store.lit(.{ .int = 42 });
    }

Les APIs reseau (`@net_*`) prennent `cap` en 1er arg mais ne
verifient jamais rien : `_ = try evaluate(...)`.

## Consequence

Aucun controle d'acces reel. N'importe quel programme Heaven peut
appeler `@net_sendto` avec n'importe quelle valeur en 1er arg.

## Ce qui existe

- Signature d'API : `net_sendto cap fd ip port data` -- coherente
- Discipline QTT : le cap devrait etre lineaire (consomme 1 fois)

## Ce qui manque

1. **Registre de caps** : table `cap_id -> permission` dans Engine.
2. **Acquisition** : `cap_acquire "net:sendto:8.8.8.8"` enregistre
   une cap avec le scope.
3. **Verification** : chaque magic `@net_*` verifie que la cap
   passe couvre l'operation demandee.
4. **Erreur** : `error.CapabilityDenied` si cap invalide.
5. **Lineaire** : la cap est consommee (QTT) apres usage.

## Effort

1 session complete.

## Priorite

**Basse pour V0** : sans protocole qui marche en prod, il n'y a
rien a proteger. **Haute pour V1** : avant tout deploiement
d'un serveur Heaven public.

## Reference

Voir D31 et C5 dans DECISIONS.md.
