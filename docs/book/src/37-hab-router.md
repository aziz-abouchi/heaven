# Hab Router — Optique + foncteur + HKT

> Le routeur compose trois structures théoriques.

## Optique : Lens(RouteState, Child)

RouteState = (Path, Child). Le lens isole le Child :

    router_get s     = (snd s)
    router_set v s   = (pair (fst s) v)
    router_over f s  = (pair (fst s) (f (snd s)))

Loi : `router_get (router_set (router_get s) s) = router_get s`.

## Foncteur : Path → A

`route_lookup` est **polymorphique en A** :

    route_lookup nil path default = default
    route_lookup routes path default =
      if (= (fst (head routes)) path)
        (snd (head routes))
        (route_lookup (tail routes) path default)

Foncteur List(Pair(Path, A)) × Path × A → A. Testé avec A = int.

## HKT : router_mk strat = ∀h

    router_mk strat h inits = (sup_spawn_v2 strat h inits)

Strat uniforme en h (one_for_one, one_for_all, rest_for_one).

## Dispatch pur

    router_dispatch child msg =
      (let many update = (child_update_fn child) in
       (dispatch_from update (child_model child) msg))

## Tests (3 outils)

- `tests/hab/router_basic.hvn` (5/5) : hit, second, miss, empty,
  lois Lens
- `tests/hab/router_quickcheck.hvn` (2/2)
- `tests/hab/router_smocker.hvn` (1/1)

## Pièges

- `(= X Y)` top-level ne matche pas (G.3) → `==`
- Loi Lens via helper nommé (scope)
