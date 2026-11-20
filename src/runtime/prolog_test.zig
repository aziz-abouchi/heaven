const std = @import("std");
const prolog_lib = @import("prolog");
const matrix_lib = @import("matrix_lib");

test "Prolog addFactDup accepte huit arguments" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{
        "a", "b", "c", "d", "e", "f", "g", "h",
    };

    try engine.addFactDup("eight", &args);

    try std.testing.expectEqual(@as(usize, 1), engine.clauses.items.len);
    try std.testing.expectEqual(@as(u8, 8), engine.clauses.items[0].head.arity);
    try std.testing.expectEqualStrings("h", engine.clauses.items[0].head.args[7]);
}

test "Prolog addFactDup conserve ses propres copies" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const pred = try std.testing.allocator.dupe(u8, "temporary_predicate");
    defer std.testing.allocator.free(pred);

    const arg = try std.testing.allocator.dupe(u8, "temporary_value");
    defer std.testing.allocator.free(arg);

    const args = [_][]const u8{arg};
    try engine.addFactDup(pred, &args);

    try std.testing.expectEqualStrings(
        "temporary_predicate",
        engine.clauses.items[0].head.pred,
    );
    try std.testing.expectEqualStrings(
        "temporary_value",
        engine.clauses.items[0].head.args[0],
    );
}

test "Prolog charge les faits et règles depuis Matrix" {
    var matrix = matrix_lib.Matrix.init(std.testing.allocator);
    defer matrix.deinit();

    _ = try matrix.addUniqueSymbol("FACT:father(ada,bob)");
    _ = try matrix.addUniqueSymbol("RULE:parent(X,Y) :- father(X,Y)");

    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try engine.loadFromMatrix(&matrix);

    try std.testing.expect(engine.loaded);
    try std.testing.expectEqual(@as(usize, 2), engine.clauses.items.len);

    var found_fact = false;
    var found_rule = false;

    for (engine.clauses.items) |clause| {
        if (std.mem.eql(u8, clause.head.pred, "father")) {
            found_fact = true;
            try std.testing.expectEqual(@as(u8, 0), clause.body_len);
        } else if (std.mem.eql(u8, clause.head.pred, "parent")) {
            found_rule = true;
            try std.testing.expectEqual(@as(u8, 1), clause.body_len);
            try std.testing.expectEqualStrings("father", clause.body[0].pred);
        }
    }

    try std.testing.expect(found_fact);
    try std.testing.expect(found_rule);
}


test "Prolog addFactDup rejette plus de huit arguments sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    const args = [_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i"};
    try std.testing.expectError(error.TooManyArguments, engine.addFactDup("nine", &args));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog parseRule rejette une règle mal formée sans insertion" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try std.testing.expectError(error.InvalidRule, engine.parseRule("parent(X,Y) :- father(X,Y),"));
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog parseRule rejette plus de huit atomes dans le corps" {
    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try std.testing.expectError(
        error.TooManyBodyAtoms,
        engine.parseRule("target(X) :- a(X), b(X), c(X), d(X), e(X), f(X), g(X), h(X), i(X)"),
    );
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}

test "Prolog loadFromMatrix annule le chargement en cas de label invalide" {
    var matrix = matrix_lib.Matrix.init(std.testing.allocator);
    defer matrix.deinit();

    _ = try matrix.addUniqueSymbol("FACT:valid(ada,bob)");
    _ = try matrix.addUniqueSymbol("FACT:malformed");

    var engine = prolog_lib.PrologEngine.init(std.testing.allocator);
    defer engine.deinit();

    try std.testing.expectError(error.InvalidFact, engine.loadFromMatrix(&matrix));
    try std.testing.expect(!engine.loaded);
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);

    // Un nouvel essai ne doit pas considérer la base comme déjà chargée.
    try std.testing.expectError(error.InvalidFact, engine.loadFromMatrix(&matrix));
    try std.testing.expect(!engine.loaded);
    try std.testing.expectEqual(@as(usize, 0), engine.clauses.items.len);
}
