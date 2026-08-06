// Exemple de flux end-to-end : Pipeline Linguistique ↔ Proof Assistant
// Fichier : src/core/linguistic_demo_test.zig

const std = @import("std");
const expect = std.testing.expect;
const ExprStore = @import("expr.zig").ExprStore;

test "Linguistic End-to-End Pipeline: 'Chaque chat est un felin'" {
    const allocator = std.testing.allocator;
    var store = try ExprStore.init(allocator);
    defer store.deinit();

    // --- ÉTAPE 1 : Ingestion du langage naturel via CST/AST ---
    // En entrée, une chaîne brute. Tree-sitter produit l'arbre syntaxique,
    // que Heaven transmute immédiatement en relations sémantiques.
    const input_phrase = "Chaque chat est un felin";

    // Simulation du comportement du forge/universal.zig sur la grammaire FR
    // "Chaque chat est un felin" -> ∀x. chat(x) -> felin(x)
    const semantic_ast = try store.buildSemanticRelation(input_phrase);

    // --- ÉTAPE 2 : Injection dans la Base de Connaissances (Prolog/Ontologie) ---
    // Le système enregistre la règle de subsomption de manière métacirculaire
    try store.registerOntologicalRule(semantic_ast);
    // Internement stocké sous forme de clause : felin(X) :- chat(X).

    // --- ÉTAPE 3 : Requête et Vérification Formelle ---
    // On pose la question au système : "Si minou est un chat, est-ce un felin ?"
    try store.injectFact("chat", "minou"); // chat(minou)

    const query_ast = try store.parseString("felin(minou)");

    // Le moteur interroge l'E-graph saturation et l'abduction Prolog
    const proof_term = try store.proveQuery(query_ast);

    // --- ÉTAPE 4 : Validation de la cohérence ---
    try expect(proof_term.is_proved == true);
    // Le système est capable de restituer l'arbre d'explication sémantique
    const explanation = try proof_term.formatExplanation();

    platform.debug.print("\n[LINGUISTIC PROOF] Result: {s}\n", .{explanation});
    // Affiche : "Prouvé: minou est un chat et chaque chat est un felin."
}
