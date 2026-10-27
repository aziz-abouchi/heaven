# Smocker — design

**Date** : 2026-10-27
**Statut** : v1 livrée (DI helpers), v2 (label-aware) backlog.

## V1 — Dependency Injection

`core/std/smocker.hvn` fournit :

- `fixed value` : stub d'arite 1.
- `fixed2 value` : stub d'arite 2 (curry).
- `fixed3 value` : stub d'arite 3 (curry).
- `const_fn value` : alias nomme de `fixed`.

Usage : la fonction sous test prend son effet en parametre, le test
passe un stub.

    process http_get url = (http_get url)
    test "process" : (process (S.fixed "FAKE") "http://x") == "FAKE"

Aucune ligne Zig. Utilise le curry (deja dans le noyau).

## Limite v1

`handle_rec` actuel ne distingue pas les labels :
`perform "Log" 42` remonte au handler avec `val = 42`, pas `"Log"`.
Un vrai mock `mock "Log" 42 body` demanderait que `perform` porte
le label.

## V2 (backlog) — perform label-aware

Cible syntaxique (deja dans le livre, ch. 6) :

    perform (Accept cap) cap_payload

Ou `perform` prend une operation (`Accept cap`) qui inclut son nom.
Le handler fait un pattern match sur l'operation :

    handle_rec thunk (lambda (op, k) -> switch op with
        | Log msg -> k (mock_log msg)
        | NetConnect fd -> k fake_fd
    ) init

Chantier : modifier `perform`/`handle_rec` dans `engine_expr.zig`.
~1 session.
