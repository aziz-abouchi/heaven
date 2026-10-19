<!-- HEAVEN:kernel-tests-gap -->
# Dette : tests kernel non câblés au `zig build test`

**Constat 2026-10-19.**

`src/kernel/` contient 4 fichiers de test :
- `test_pi.zig` (38 l.)
- `test_proof_irrelevance.zig` (49 l.)
- `test_quotient.zig` (28 l.) — **2/2 verts en isolation**
- `test_transform.zig` (42 l.)

Aucun n'a de `b.addTest(...)` dans `build.zig`. Ils ne tournent
**jamais en CI**. `zig build test` n'inclut que les tests des
modules câblés (expr, engine, canon, abi, egraph, etc.).

## Vérification manuelle

    zig test src/kernel/test_quotient.zig   # 2/2 OK
    zig test src/kernel/test_pi.zig          # à vérifier
    zig test src/kernel/test_proof_irrelevance.zig  # à vérifier
    zig test src/kernel/test_transform.zig   # à vérifier

## Risque

Câbler les 4 d'un coup en CI peut révéler des tests KO depuis
des semaines. À faire en session dédiée, test par test, avec
rollback si l'un est cassé.

## Impact quotients

`test_quotient.zig` passe en isolation (2/2). Le noyau quotients
(`ast.quot`, `typechecker.infer`, `conversion.lift`) est
**fonctionnel**. Il n'est pas exposé à Heaven pur (`.hvn`), mais
le noyau Zig est là.

## Prochaines étapes

1. **Session kernel-tests** : câbler un par un, vérifier verts.
2. **Session quotients-expose** : exposer `Quot`/`class`/`lift`
   en `.hvn` (parser + elaborator + tests).
