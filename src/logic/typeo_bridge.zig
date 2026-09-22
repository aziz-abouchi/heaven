//! Pont synthèse typée → EGraph.
//!
//! Compose trois couches :
//!   typeo (moteur de typage)  → Term
//!   term_bridge (passerelle)  → Id Core
//!   egraph (réécriture)       → ClassId
//!
//! Cas d'usage principal : synthétiser un programme d'un type donné,
//! l'enregistrer dans un EGraph, et le laisser être réécrit par les
//! règles de réécriture.

const std = @import("std");
const kanren = @import("kanren");
const expr = @import("expr");
const typeo_mod = @import("typeo");
const term_bridge = @import("term_bridge");
const egraph_mod = @import("egraph");

const Term = kanren.Term;
const Store = expr.Store;
const Id = expr.Id;

pub const BridgeError = error{
    /// `typeo.query` n'a retourné aucune réponse pour cette requête.
    InferenceFailed,
    /// La réponse de `typeo` contient des variables libres — impossible
    /// à enregistrer dans l'EGraph (assertCoreExpr rejette `.hole`).
    UnresolvedTerm,
    /// Échec lors de la conversion Term → Id.
    BridgeFailed,
    /// Échec côté EGraph (expression non-primitive, etc.).
    EGraphFailed,
    OutOfMemory,
};

/// Retourne vrai si `term` contient au moins un `.Var` quelque part.
fn hasFreeVar(term: Term) bool {
    return switch (term) {
        .Var => true,
        .Pair => |p| hasFreeVar(p.head) or hasFreeVar(p.tail),
        else => false,
    };
}

/// Synthétise une expression close de type `target_type`.
///
/// - Crée une variable logique fraîche pour l'expression à synthétiser ;
/// - Demande à `typeo` une réponse pour `(query, target_type)` ;
/// - Convertit le `Term` résultant en `Id` Core ;
/// - L'enregistre récursivement dans `egraph`.
///
/// Retourne l'`Id` Core synthétisé (encore vivant dans `store`) et sa
/// classe EGraph. L'appelant peut ensuite lire `egraph.extract` pour
/// obtenir la forme réécrite.
pub fn synthesizeAndAddToEGraph(
    store: *Store,
    egraph: *egraph_mod.EGraph,
    typeo: *typeo_mod.Typeo,
    target_type: Term,
) BridgeError!struct { id: Id, class: egraph_mod.ClassId } {
    // 1. Variable logique représentant le programme à synthétiser.
    const var_expr = Term.freshVar("__synth");

    // 2. Interroger le moteur de typage.
    const term = (typeo.query(var_expr, target_type) catch
        return BridgeError.InferenceFailed) orelse
        return BridgeError.InferenceFailed;

    // 3. Refuser les synthèses partielles (variables libres résiduelles).
    if (hasFreeVar(term)) return BridgeError.UnresolvedTerm;

    // 4. Term → Id Core.
    const id = term_bridge.termToId(store, term) catch
        return BridgeError.BridgeFailed;

    // 5. Enregistrer dans l'EGraph (récursif, hash-consing).
    const class = egraph.addExpr(id) catch
        return BridgeError.EGraphFailed;

    return .{ .id = id, .class = class };
}

/// Infère le type d'un `Id` Core présent dans `store`.
pub fn inferExprType(
    store: *Store,
    typeo: *typeo_mod.Typeo,
    expr_id: Id,
) BridgeError!Term {
    var arena = std.heap.ArenaAllocator.init(typeo.engine.allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    // Sans 'try' devant, car 'catch' gère directement l'erreur
    const expr_term = term_bridge.idToTerm(temp_alloc, store, expr_id) catch
        return BridgeError.BridgeFailed;

    const var_type = Term.freshVar("__type");

    const inferred = (typeo.query(expr_term, var_type) catch
        return BridgeError.InferenceFailed) orelse
        return BridgeError.InferenceFailed;

    if (hasFreeVar(inferred)) return BridgeError.UnresolvedTerm;

    return inferred;
}

/// Vérifie qu'une expression `Id` Core possède bien le type `expected_type`.
pub fn checkExprType(
    store: *Store,
    typeo: *typeo_mod.Typeo,
    expr_id: Id,
    expected_type: Term,
) BridgeError!bool {
    var arena = std.heap.ArenaAllocator.init(typeo.engine.allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    const expr_term = term_bridge.idToTerm(temp_alloc, store, expr_id) catch
        return BridgeError.BridgeFailed;

    const res = typeo.query(expr_term, expected_type) catch
        return BridgeError.InferenceFailed;

    return res != null;
}

// ─────────────────────────────────────────────────────────────────
// Tests additionnels
// ─────────────────────────────────────────────────────────────────

test "typeo_bridge — inférence de type depuis un Id Core" {
    const allocator = testing.allocator;

    var engine = kanren.KanrenEngine.init(allocator);
    defer engine.deinit();

    var typeo = typeo_mod.Typeo.init(&engine);
    try typeo.registerRules();

    var store = Store.init(allocator);
    defer store.deinit();

    // Expression littérale d'entier (lit 10) dans le Store Core
    const int_id = try store.int(10);
    const lit_sym = try store.sym("lit");
    const lit_expr_id = try store.apply(lit_sym, &.{int_id});

    // Inférence : lit 10 doit être de type Int
    const inferred_type = try inferExprType(&store, &typeo, lit_expr_id);
    try testing.expectEqualStrings("Int", inferred_type.Atom);

    // Vérification directe
    const is_valid = try checkExprType(&store, &typeo, lit_expr_id, Term.sym("Int"));
    try testing.expect(is_valid);
}

// ─────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────

const testing = std.testing;

test "typeo_bridge — synthèse Bool produit une expression Core valide" {
    const allocator = testing.allocator;

    // Arène pour les TermPair transitoires (cf. contrat kanren.zig).
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var engine = kanren.KanrenEngine.init(allocator);
    defer engine.deinit();

    var typeo = typeo_mod.Typeo.init(&engine);
    try typeo.registerRules();

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = egraph_mod.EGraph.init(&store, allocator);
    defer egraph.deinit();

    const result = try synthesizeAndAddToEGraph(
        &store,
        &egraph,
        &typeo,
        Term.sym("Bool"),
    );

    // L'Id produit doit être une primitive Core.
    try testing.expect(store.isCore(result.id));

    // Et il doit être enregistré dans une classe valide.
    const found = egraph.find(result.id);
    try testing.expect(found != null);
    try testing.expectEqual(result.class, found.?);
}

test "typeo_bridge — type sans règle échoue proprement" {
    const allocator = testing.allocator;

    var engine = kanren.KanrenEngine.init(allocator);
    defer engine.deinit();

    var typeo = typeo_mod.Typeo.init(&engine);
    try typeo.registerRules();

    var store = Store.init(allocator);
    defer store.deinit();

    var egraph = egraph_mod.EGraph.init(&store, allocator);
    defer egraph.deinit();

    // Aucune clause ne produit un programme de type "Gribouille".
    const err = synthesizeAndAddToEGraph(
        &store,
        &egraph,
        &typeo,
        Term.sym("Gribouille"),
    );
    try testing.expectError(BridgeError.InferenceFailed, err);
}
