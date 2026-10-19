<!-- HEAVEN:h1-qualified-sym -->
# H1 — Symbole qualifié (module.Sym) non normalisé (2026-10-19)

## Symptôme (récidive 4x dans la session)

    -- module L exporte : data A = ANil | ACons Int A
    -- mk _ = (ACons 1 ANil)
    (= (L.mk 0) (L.ACons 1 L.ANil))  -- → false (attendu true)

Tests discriminants (h1b.hvn) :
- `(= (L.ACons 1 L.ANil) (L.ACons 1 L.ANil))` → ✅ true
- `(= (L.mk 0) (L.mk 0))` → ✅ true
- `(= (L.mk 0) (L.ACons 1 L.ANil))` → ❌ false

## Diagnostic

`L.mk 0` retourne un `.apply` avec `payload = Sym("ACons")` (Sym
original, produit par le module). `L.ACons 1 L.ANil` produit un
`.apply` avec `payload = Sym("L.ACons")` (Sym qualifié, jamais
résolu vers l'original à la construction).

`evalCmp` → `exprStructuralEq` compare les `payload` (Sym ids).
Sym("ACons") ≠ Sym("L.ACons") → false.

## Fix tenté (échoué)

Résolution dans `.sym` et `.apply` de `engine_expr.zig` :
- `.sym` : `env.get(L.ACons)` échoue → résoudre suffixe `ACons` → Sym
  original.
- `.apply` : `engine.fns.get(L.ACons)` échoue → résoudre suffixe.

**Résultat** : 2/4 et 4/5 (inchangé). Pourquoi : la résolution se
fait à l'**évaluation**, mais `exprStructuralEq` compare les Sym
**dans l'AST déjà construit**. Le Sym qualifié reste dans l'AST.

## Piste correcte

La résolution doit se faire **à la construction de l'AST** (au
parser/elaborator) : quand on voit `L.ACons` dans une expression,
produire le Sym original `ACons` dans le Store, pas un Sym
qualifié `L.ACons`.

Sites à traiter :
1. `expr_parser.parseExpression` : quand un Sym contient un `.` et
   que le suffixe est un Sym connu (env ou engine.fns), résoudre.
2. OU `import.zig` : enregistrer des alias au moment de l'import
   (`L.ACons` → `ACons`), pour que la construction du Sym pointât
   vers l'original.
3. OU `exprStructuralEq` : normaliser les deux Sym (strip prefix
   module) avant comparaison. Workaround localisé, mais ne résout
   pas le vrai problème (deux Syms coexistent dans le Store).

Effort : 1 session. Pas un bloc de fin.

## Impact

- MPST : 3 tests contournés (`dual_send_recv`, `trace_parse`,
  `json_obj_get` faux positif).
- HKT : comparaisons de constructeurs importés.
- Toute ADT importée.

## Contournement systématique actuel

Ne pas comparer directement des constructeurs qualifiés. Passer
par extraction d'Int/String avant `==`. Moche, mais stable.

## Priorité

**P1** (après H1 récidive 4x). Un seul fix propre débloque MPST,
HKT, JSON objects (H1/H2/H3), et toute ADT importée.
