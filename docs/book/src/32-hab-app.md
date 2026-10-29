# Hab — App complète

> N composants MVU supervisés, state-threading pur.

## Structure

Une app Hab est une liste de couples (update_fn, mvu_state).
Le superviseur sup_tick_all applique un message à tous les enfants.

## API

    import "hab/app.hvn"

    app_mk children        -- children : liste de child_mk
    app_tick_all app msg   -- dispatch le msg à tous les enfants
    app_tick_at app i msg  -- dispatch au i-ème enfant seulement
    app_tick_list app msgs -- dispatch séquentiellement N msgs
    app_child_model app i  -- lit l'état du i-ème enfant
    app_count app          -- nombre d'enfants

## Exemple

    inc s m = (s + m)

    test "2 children":
      (let many c1 = (child_mk inc 0) in
       (let many c2 = (child_mk inc 10) in
        (let many app = (app_mk (cons c1 (cons c2 nil))) in
         (let many app2 = (app_tick_all app 5) in
          (app_count app2))))) == 2

## Imports unprefixed

ATTENTION : le qualifié (SV.foo) casse les fonctions 2-args (thunk).
On importe sans as X, tout unprefixed. Voir _runtime_gaps.md.

## Limites

- Pas de vrai acteur mailbox (component_actor_spawn partiel)
- Pas de composition de lens (fst-in-lambda bug)
- Pas de render/view (MVU sans le V)
